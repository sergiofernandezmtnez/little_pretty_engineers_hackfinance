-- REPARACIÓN para un Supabase donde ya ejecutaste schema.sql.
-- Se puede ejecutar varias veces sin problema. Pégalo en SQL Editor > Run.

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

-- 2) Permisos básicos (Supabase ya los pone por defecto; esto asegura que no falten)
grant usage on schema public to anon, authenticated;
grant all on all tables in schema public to authenticated;
grant select on ayudas to anon, authenticated;
grant execute on all functions in schema public to authenticated;

-- 3) Función de pertenencia a grupos y alta por código
create or replace function es_miembro(g uuid) returns boolean
language sql security definer stable set search_path = public as
$$ select exists (select 1 from grupo_miembros where grupo_id = g and user_id = auth.uid()) $$;

create or replace function unirse_grupo(cod text, mi_nombre text) returns uuid
language plpgsql security definer set search_path = public as $$
declare g uuid;
begin
  select id into g from grupos where codigo = lower(trim(cod));
  if g is null then raise exception 'Código de grupo no válido'; end if;
  insert into grupo_miembros (grupo_id, user_id, nombre) values (g, auth.uid(), mi_nombre)
    on conflict (grupo_id, user_id) do nothing;
  return g;
end $$;

-- 4) Reglas de seguridad (se borran y se vuelven a crear)
alter table perfiles enable row level security;
drop policy if exists propio on perfiles;
create policy propio on perfiles for all using (id = auth.uid()) with check (id = auth.uid());

alter table grupos enable row level security;
drop policy if exists ver on grupos;    create policy ver    on grupos for select using (es_miembro(id) or creado_por = auth.uid());
drop policy if exists crear on grupos;  create policy crear  on grupos for insert with check (creado_por = auth.uid());
drop policy if exists borrar on grupos; create policy borrar on grupos for delete using (creado_por = auth.uid());

alter table grupo_miembros enable row level security;
drop policy if exists ver on grupo_miembros;    create policy ver    on grupo_miembros for select using (es_miembro(grupo_id));
drop policy if exists anadir on grupo_miembros; create policy anadir on grupo_miembros for insert with check (
  es_miembro(grupo_id) or exists (select 1 from grupos g where g.id = grupo_id and g.creado_por = auth.uid()));
drop policy if exists quitar on grupo_miembros; create policy quitar on grupo_miembros for delete using (es_miembro(grupo_id));

do $$ declare t text; begin
  foreach t in array array['grupo_gastos','grupo_pagos'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists miembros on %I', t);
    execute format('create policy miembros on %I for all using (es_miembro(grupo_id)) with check (es_miembro(grupo_id))', t);
  end loop;
end $$;

alter table grupo_reparto enable row level security;
drop policy if exists miembros on grupo_reparto;
create policy miembros on grupo_reparto for all
  using (exists (select 1 from grupo_gastos x where x.id = gasto_id and es_miembro(x.grupo_id)))
  with check (exists (select 1 from grupo_gastos x where x.id = gasto_id and es_miembro(x.grupo_id)));

-- 5) Que PostgREST (la API) vea los cambios al momento
notify pgrst, 'reload schema';
