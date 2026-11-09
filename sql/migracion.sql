-- REPARACIÓN Y ENDURECIMIENTO para un Supabase donde ya ejecutaste schema.sql.
-- Se puede ejecutar varias veces sin problema. Pégalo en SQL Editor > Run.
-- Si ya tenías datos, no se borra nada: las reglas nuevas se aplican a lo que se escriba desde ahora.

-- 1) Columnas que usa la app en "perfiles"
alter table perfiles add column if not exists ccaa text;
alter table perfiles add column if not exists ambito text;
alter table perfiles add column if not exists datos jsonb;
alter table perfiles add column if not exists gustos text[] not null default '{}';
alter table perfiles add column if not exists updated_at timestamptz not null default now();
-- la app ahora solo tiene dos modos: 'normal' y 'sos'
alter table perfiles drop constraint if exists perfiles_modo_check;
update perfiles set modo = 'normal' where modo not in ('normal','sos');
alter table perfiles add constraint perfiles_modo_check check (modo in ('normal','sos'));

-- 2) Códigos de invitación fuertes (10 caracteres aleatorios) para los grupos NUEVOS
alter table grupos alter column codigo set default substr(replace(gen_random_uuid()::text, '-', ''), 1, 10);

-- 3) Integridad: el pagador de un gasto y las partes de un pago deben ser del MISMO grupo
create unique index if not exists grupo_miembros_id_grupo_uk on grupo_miembros (id, grupo_id);

-- Si un usuario borra su cuenta, que siga existiendo como "persona sin cuenta" en sus grupos
alter table grupo_miembros drop constraint if exists grupo_miembros_user_id_fkey;
alter table grupo_miembros add constraint grupo_miembros_user_id_fkey
  foreign key (user_id) references auth.users on delete set null;

-- Reglas nuevas (NOT VALID: se aplican a lo que se inserte desde ahora, sin tocar filas antiguas)
do $$
declare c record;
begin
  for c in select * from (values
    ('perfiles',       'perfiles_nombre_len',    'check (char_length(nombre) between 1 and 80)'),
    ('perfiles',       'perfiles_edad_rango',    'check (edad is null or edad between 0 and 120)'),
    ('perfiles',       'perfiles_datos_tam',     'check (pg_column_size(datos) <= 262144)'),
    ('gastos',         'gastos_concepto_len',    'check (char_length(concepto) <= 200)'),
    ('eventos',        'eventos_titulo_len',     'check (char_length(titulo) <= 120)'),
    ('grupos',         'grupos_nombre_len',      'check (char_length(nombre) between 1 and 80)'),
    ('grupo_miembros', 'grupo_miembros_nombre_len','check (char_length(nombre) between 1 and 80)'),
    ('grupo_gastos',   'grupo_gastos_concepto_len','check (char_length(concepto) <= 200)'),
    ('grupo_gastos',   'grupo_gastos_pagador_grupo','foreign key (pagador_id, grupo_id) references grupo_miembros (id, grupo_id) on delete cascade'),
    ('grupo_pagos',    'grupo_pagos_de_grupo',   'foreign key (de_id, grupo_id) references grupo_miembros (id, grupo_id) on delete cascade'),
    ('grupo_pagos',    'grupo_pagos_a_grupo',    'foreign key (a_id, grupo_id) references grupo_miembros (id, grupo_id) on delete cascade')
  ) as v(t, n, d) loop
    if not exists (select 1 from pg_constraint where conname = c.n and conrelid = ('public.' || c.t)::regclass) then
      execute format('alter table public.%I add constraint %I %s not valid', c.t, c.n, c.d);
    end if;
  end loop;
end $$;

-- 4) Funciones
create or replace function es_miembro(g uuid) returns boolean
language sql security definer stable set search_path = public as
$$ select exists (select 1 from grupo_miembros where grupo_id = g and user_id = auth.uid()) $$;

-- El miembro al que se reparte un gasto debe ser del mismo grupo que el gasto
create or replace function reparto_mismo_grupo() returns trigger
language plpgsql set search_path = public as $$
begin
  if not exists (
    select 1 from grupo_gastos x join grupo_miembros m on m.grupo_id = x.grupo_id
    where x.id = new.gasto_id and m.id = new.miembro_id) then
    raise exception 'El miembro no pertenece al grupo de este gasto';
  end if;
  return new;
end $$;
drop trigger if exists reparto_mismo_grupo on grupo_reparto;
create trigger reparto_mismo_grupo before insert or update on grupo_reparto
  for each row execute function reparto_mismo_grupo();

-- Unirse a un grupo con su código (solo usuarios con sesión)
create or replace function unirse_grupo(cod text, mi_nombre text) returns uuid
language plpgsql security definer set search_path = public as $$
declare g uuid; n text := left(trim(coalesce(mi_nombre, '')), 80);
begin
  if auth.uid() is null then raise exception 'Inicia sesión primero'; end if;
  if n = '' then raise exception 'Escribe tu nombre'; end if;
  select id into g from grupos where codigo = lower(trim(coalesce(cod, '')));
  if g is null then raise exception 'Código de grupo no válido'; end if;
  insert into grupo_miembros (grupo_id, user_id, nombre) values (g, auth.uid(), n)
    on conflict (grupo_id, user_id) do nothing;
  return g;
end $$;

-- 5) Reglas de seguridad (se borran y se vuelven a crear)
alter table perfiles enable row level security;
drop policy if exists propio on perfiles;
create policy propio on perfiles for all to authenticated using (id = auth.uid()) with check (id = auth.uid());

do $$ declare t text; begin
  foreach t in array array['gastos_fijos','gastos','eventos','planes_usuario','ayudas_usuario','retos_usuario'] loop
    if to_regclass(format('public.%I', t)) is not null then
      execute format('alter table %I enable row level security', t);
      execute format('drop policy if exists propio on %I', t);
      execute format('create policy propio on %I for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
    end if;
  end loop;
  foreach t in array array['grupo_gastos','grupo_pagos'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists miembros on %I', t);
    execute format('create policy miembros on %I for all to authenticated using (es_miembro(grupo_id)) with check (es_miembro(grupo_id))', t);
  end loop;
end $$;

-- Catálogo de ayudas: solo lectura y solo con sesión (antes lo podía leer cualquiera sin sesión)
alter table ayudas enable row level security;
drop policy if exists lectura on ayudas;
create policy lectura on ayudas for select to authenticated using (true);

alter table grupos enable row level security;
drop policy if exists ver on grupos;    create policy ver    on grupos for select to authenticated using (es_miembro(id) or creado_por = auth.uid());
drop policy if exists crear on grupos;  create policy crear  on grupos for insert to authenticated with check (creado_por = auth.uid());
drop policy if exists borrar on grupos; create policy borrar on grupos for delete to authenticated using (creado_por = auth.uid());

alter table grupo_miembros enable row level security;
drop policy if exists ver on grupo_miembros;
create policy ver on grupo_miembros for select to authenticated using (es_miembro(grupo_id));
-- Se puede añadir: a uno mismo, o a una persona SIN cuenta (user_id nulo). Nunca a otro usuario con cuenta.
drop policy if exists anadir on grupo_miembros;
create policy anadir on grupo_miembros for insert to authenticated with check (
  (user_id is null or user_id = auth.uid())
  and (es_miembro(grupo_id)
       or exists (select 1 from grupos g where g.id = grupo_id and g.creado_por = auth.uid())));
-- Se puede quitar: a uno mismo, a personas sin cuenta, o a cualquiera si eres el creador del grupo.
drop policy if exists quitar on grupo_miembros;
create policy quitar on grupo_miembros for delete to authenticated using (
  user_id = auth.uid()
  or (user_id is null and es_miembro(grupo_id))
  or exists (select 1 from grupos g where g.id = grupo_id and g.creado_por = auth.uid()));

alter table grupo_reparto enable row level security;
drop policy if exists miembros on grupo_reparto;
create policy miembros on grupo_reparto for all to authenticated
  using (exists (select 1 from grupo_gastos x where x.id = gasto_id and es_miembro(x.grupo_id)))
  with check (exists (select 1 from grupo_gastos x where x.id = gasto_id and es_miembro(x.grupo_id)));

-- 6) Permisos (mínimo privilegio). Antes: "grant all" a todos los usuarios con sesión
--    (incluía TRUNCATE, que se salta la RLS) y ejecución de funciones abierta a "anon".
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on functions from public, anon, authenticated;

-- (se comprueba que cada tabla exista: retos.sql borra la tabla antigua "retos_usuario")
do $$ declare t text; begin
  foreach t in array array['perfiles','gastos_fijos','gastos','eventos','planes_usuario','ayudas_usuario','retos_usuario',
                           'grupo_gastos','grupo_pagos','grupo_reparto'] loop
    if to_regclass(format('public.%I', t)) is not null then
      execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    end if;
  end loop;
end $$;
grant select, insert, delete on grupos, grupo_miembros to authenticated;
grant select on ayudas to authenticated;
grant execute on function es_miembro(uuid), unirse_grupo(text, text) to authenticated;

-- Las tablas de retos (retos.sql) también necesitan sus permisos si ya existen
do $$ begin
  if to_regclass('public.reto_miembros') is not null and to_regclass('public.reto_checks') is not null
     and exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'retos' and column_name = 'creador') then
    grant select, insert, delete on public.retos, public.reto_miembros, public.reto_checks to authenticated;
    grant execute on function public.es_miembro_reto(uuid), public.unirse_reto(text, text) to authenticated;
  end if;
end $$;

-- 7) Que PostgREST (la API) vea los cambios al momento
notify pgrst, 'reload schema';
