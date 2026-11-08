-- Retos compartidos de STUD€NTIA. Ejecuta este script UNA vez en Supabase: SQL Editor -> New query -> Run.

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
  codigo text not null unique default substr(md5(random()::text || clock_timestamp()::text), 1, 6),
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

alter table public.retos enable row level security;
alter table public.reto_miembros enable row level security;
alter table public.reto_checks enable row level security;

-- ¿Soy miembro de este reto? (security definer evita recursión en las políticas)
create or replace function public.es_miembro_reto(rid uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (select 1 from public.reto_miembros where reto_id = rid and user_id = auth.uid());
$$;

drop policy if exists retos_select on public.retos;
create policy retos_select on public.retos for select using (creador = auth.uid() or public.es_miembro_reto(id));
drop policy if exists retos_insert on public.retos;
create policy retos_insert on public.retos for insert with check (creador = auth.uid());
drop policy if exists retos_delete on public.retos;
create policy retos_delete on public.retos for delete using (creador = auth.uid());

drop policy if exists miembros_select on public.reto_miembros;
create policy miembros_select on public.reto_miembros for select using (user_id = auth.uid() or public.es_miembro_reto(reto_id));
drop policy if exists miembros_insert on public.reto_miembros;
create policy miembros_insert on public.reto_miembros for insert with check (user_id = auth.uid());
drop policy if exists miembros_delete on public.reto_miembros;
create policy miembros_delete on public.reto_miembros for delete using (user_id = auth.uid());

-- Cada integrante solo puede apuntar (o quitar) sus propios días; todos los miembros ven los de los demás.
drop policy if exists checks_select on public.reto_checks;
create policy checks_select on public.reto_checks for select using (public.es_miembro_reto(reto_id));
drop policy if exists checks_insert on public.reto_checks;
create policy checks_insert on public.reto_checks for insert with check (user_id = auth.uid() and public.es_miembro_reto(reto_id));
drop policy if exists checks_delete on public.reto_checks;
create policy checks_delete on public.reto_checks for delete using (user_id = auth.uid());

-- Unirse a un reto con su código
create or replace function public.unirse_reto(cod text, mi_nombre text)
returns uuid language plpgsql security definer set search_path = public as $$
declare rid uuid;
begin
  if auth.uid() is null then raise exception 'Inicia sesión primero'; end if;
  select id into rid from public.retos where codigo = lower(trim(cod));
  if rid is null then raise exception 'Código de reto no válido'; end if;
  insert into public.reto_miembros (reto_id, user_id, nombre) values (rid, auth.uid(), mi_nombre)
    on conflict (reto_id, user_id) do nothing;
  return rid;
end $$;

-- Permisos y recarga de la API
grant all on public.retos, public.reto_miembros, public.reto_checks to authenticated;
grant execute on function public.es_miembro_reto(uuid), public.unirse_reto(text, text) to authenticated;
notify pgrst, 'reload schema';
