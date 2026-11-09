-- Retos compartidos de STUD€NTIA. Ejecuta este script en Supabase: SQL Editor -> New query -> Run.
-- Se puede ejecutar varias veces sin problema (también para aplicar las mejoras de seguridad).
--
-- SEGURIDAD: RLS en las tres tablas, mínimo privilegio, código de invitación de 10 caracteres
-- aleatorios y entrada a un reto SOLO con el código (no se puede insertar uno mismo a mano).

-- 0) Limpieza: schema.sql creó una tabla "retos" antigua (catálogo con id de texto) que la app NO usa.
--    Chocaba con la nueva (id uuid). Solo se borra si es la antigua.
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'retos'
               and column_name = 'id' and data_type = 'text') then
    drop table if exists public.retos_usuario;
    drop table public.retos cascade;
  end if;
end $$;

create table if not exists public.retos (
  id uuid primary key default gen_random_uuid(),
  creador uuid not null default auth.uid(),
  nombre text not null,
  descripcion text,
  dias int not null check (dias between 1 and 365),
  ahorro_dia numeric not null default 0,
  inicio date not null default current_date,
  codigo text not null unique default substr(replace(gen_random_uuid()::text, '-', ''), 1, 10),
  created_at timestamptz not null default now()
);

create table if not exists public.reto_miembros (
  id uuid primary key default gen_random_uuid(),
  reto_id uuid not null references public.retos(id) on delete cascade,
  user_id uuid not null default auth.uid(),
  nombre text not null,
  unique (reto_id, user_id)
);

create table if not exists public.reto_checks (
  reto_id uuid not null references public.retos(id) on delete cascade,
  user_id uuid not null default auth.uid(),
  fecha date not null,
  primary key (reto_id, user_id, fecha)
);

-- Si las tablas ya existían (versión anterior), ponemos el código fuerte a los retos NUEVOS.
-- (Los retos ya creados conservan su código de 6 caracteres; ver el final del archivo para renovarlos.)
alter table public.retos alter column codigo set default substr(replace(gen_random_uuid()::text, '-', ''), 1, 10);

-- Límites de longitud (NOT VALID: se aplican a lo que se inserte desde ahora, sin tocar filas antiguas)
do $$
declare c record;
begin
  for c in select * from (values
    ('retos',         'retos_nombre_len',        'check (char_length(nombre) between 1 and 80)'),
    ('retos',         'retos_descripcion_len',   'check (descripcion is null or char_length(descripcion) <= 500)'),
    ('retos',         'retos_ahorro_rango',      'check (ahorro_dia between 0 and 100000)'),
    ('reto_miembros', 'reto_miembros_nombre_len','check (char_length(nombre) between 1 and 80)')
  ) as v(t, n, d) loop
    if not exists (select 1 from pg_constraint where conname = c.n and conrelid = ('public.' || c.t)::regclass) then
      execute format('alter table public.%I add constraint %I %s not valid', c.t, c.n, c.d);
    end if;
  end loop;
end $$;

alter table public.retos enable row level security;
alter table public.reto_miembros enable row level security;
alter table public.reto_checks enable row level security;

-- ¿Soy miembro de este reto? (security definer evita recursión en las políticas)
create or replace function public.es_miembro_reto(rid uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (select 1 from public.reto_miembros where reto_id = rid and user_id = auth.uid());
$$;

drop policy if exists retos_select on public.retos;
create policy retos_select on public.retos for select to authenticated
  using (creador = auth.uid() or public.es_miembro_reto(id));
drop policy if exists retos_insert on public.retos;
create policy retos_insert on public.retos for insert to authenticated with check (creador = auth.uid());
drop policy if exists retos_delete on public.retos;
create policy retos_delete on public.retos for delete to authenticated using (creador = auth.uid());

drop policy if exists miembros_select on public.reto_miembros;
create policy miembros_select on public.reto_miembros for select to authenticated
  using (user_id = auth.uid() or public.es_miembro_reto(reto_id));
-- Insertar a mano solo puede hacerlo el CREADOR del reto (para apuntarse a su propio reto).
-- Los demás entran únicamente con el código, a través de unirse_reto().
drop policy if exists miembros_insert on public.reto_miembros;
create policy miembros_insert on public.reto_miembros for insert to authenticated
  with check (user_id = auth.uid()
              and exists (select 1 from public.retos r where r.id = reto_id and r.creador = auth.uid()));
drop policy if exists miembros_delete on public.reto_miembros;
create policy miembros_delete on public.reto_miembros for delete to authenticated using (user_id = auth.uid());

-- Cada integrante solo puede apuntar (o quitar) sus propios días; todos los miembros ven los de los demás.
-- No se pueden apuntar días futuros ni de hace más de un año.
drop policy if exists checks_select on public.reto_checks;
create policy checks_select on public.reto_checks for select to authenticated
  using (public.es_miembro_reto(reto_id));
drop policy if exists checks_insert on public.reto_checks;
create policy checks_insert on public.reto_checks for insert to authenticated
  with check (user_id = auth.uid() and public.es_miembro_reto(reto_id)
              and fecha between current_date - 365 and current_date + 1);
drop policy if exists checks_delete on public.reto_checks;
create policy checks_delete on public.reto_checks for delete to authenticated using (user_id = auth.uid());

-- Unirse a un reto con su código (solo usuarios con sesión)
create or replace function public.unirse_reto(cod text, mi_nombre text)
returns uuid language plpgsql security definer set search_path = public as $$
declare rid uuid; n text := left(trim(coalesce(mi_nombre, '')), 80);
begin
  if auth.uid() is null then raise exception 'Inicia sesión primero'; end if;
  if n = '' then raise exception 'Escribe tu nombre'; end if;
  select id into rid from public.retos where codigo = lower(trim(coalesce(cod, '')));
  if rid is null then raise exception 'Código de reto no válido'; end if;
  insert into public.reto_miembros (reto_id, user_id, nombre) values (rid, auth.uid(), n)
    on conflict (reto_id, user_id) do nothing;
  return rid;
end $$;

-- Permisos (mínimo privilegio) y recarga de la API
revoke all on public.retos, public.reto_miembros, public.reto_checks from anon, authenticated;
grant select, insert, delete on public.retos, public.reto_miembros, public.reto_checks to authenticated;
revoke execute on function public.es_miembro_reto(uuid), public.unirse_reto(text, text) from public, anon;
grant  execute on function public.es_miembro_reto(uuid), public.unirse_reto(text, text) to authenticated;
notify pgrst, 'reload schema';

-- OPCIONAL: renovar los códigos de los retos que ya existen (los códigos antiguos de 6 caracteres
-- se podrían adivinar). Si lo ejecutas, tendrás que volver a pasar el código nuevo a tus amigos.
-- Quita los "--" de la línea siguiente para aplicarlo:
-- update public.retos set codigo = substr(replace(gen_random_uuid()::text, '-', ''), 1, 10) where char_length(codigo) < 10;
