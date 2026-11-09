-- STUD€NTIA / Fin de Mes · esquema para Supabase (PostgreSQL)
-- Pega este archivo entero en Supabase > SQL Editor > Run.
-- Importes siempre en céntimos (enteros) para evitar errores de redondeo.
--
-- SEGURIDAD (qué hace este esquema):
--  * Cada tabla tiene RLS activada: un usuario solo ve y toca SUS filas
--    (o las de los grupos/retos a los que pertenece). Nadie ve a usuarios ajenos.
--  * Mínimo privilegio: el rol "authenticated" solo recibe SELECT/INSERT/UPDATE/DELETE
--    donde la app lo necesita (sin TRUNCATE, TRIGGER, REFERENCES). "anon" no recibe nada.
--  * Las funciones con SECURITY DEFINER solo las puede ejecutar un usuario con sesión.
--  * Códigos de invitación de 10 caracteres aleatorios (no adivinables por fuerza bruta).
--  * Un miembro no puede meter a terceros con cuenta, ni expulsar a otros usuarios.
--  * Límites de longitud/tamaño para evitar que alguien llene la base de datos de basura.

create extension if not exists pgcrypto;

-- ===== Datos personales =====
create table perfiles (
  id uuid primary key references auth.users on delete cascade,
  nombre text not null check (char_length(nombre) between 1 and 80),
  edad int check (edad is null or edad between 0 and 120),
  estudios text check (char_length(estudios) <= 120),
  ccaa text check (char_length(ccaa) <= 60),
  centro text check (char_length(centro) <= 120),
  ambito text check (char_length(ambito) <= 60),
  vivienda text check (char_length(vivienda) <= 60),
  modo text not null default 'normal' check (modo in ('normal','sos')),
  gustos text[] not null default '{}',
  datos jsonb check (pg_column_size(datos) <= 262144),   -- estado completo de la app (máx. 256 KB)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table gastos_fijos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  tipo text not null check (char_length(tipo) <= 60),
  importe_cents int not null check (importe_cents >= 0)
);
create table gastos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  fecha date not null default current_date,
  categoria text not null check (char_length(categoria) <= 60),
  concepto text check (char_length(concepto) <= 200),
  importe_cents int not null check (importe_cents > 0),
  pago text not null default 'tarjeta' check (pago in ('tarjeta','efectivo'))
);
create table eventos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  titulo text not null check (char_length(titulo) <= 120),
  fecha date not null, tipo text check (char_length(tipo) <= 60),
  importe_cents int not null default 0
);
create table planes_usuario (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  plan_id text not null, objetivo_cents int not null, mensual_cents int not null,
  ahorrado_cents int not null default 0, activo boolean not null default true,
  primary key (user_id, plan_id)
);

-- ===== Catálogos (solo lectura, solo con sesión) =====
create table ayudas (id text primary key, titulo text not null, categoria text, requisitos jsonb, plazo text);
create table retos  (id text primary key, titulo text not null, dias int not null, puntos int not null);

create table ayudas_usuario (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  ayuda_id text not null references ayudas on delete cascade,
  estado text not null check (estado in ('guardada','descartada')),
  primary key (user_id, ayuda_id)
);
create table retos_usuario (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  reto_id text not null references retos on delete cascade,
  inicio date not null default current_date, checks date[] not null default '{}',
  primary key (user_id, reto_id)
);

-- ===== Grupos (estilo Tricount) =====
create table grupos (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (char_length(nombre) between 1 and 80),
  -- 10 caracteres hexadecimales de un generador criptográficamente seguro (~1,1 billones de combinaciones)
  codigo text not null unique default substr(replace(gen_random_uuid()::text, '-', ''), 1, 10),
  creado_por uuid not null default auth.uid() references auth.users,
  created_at timestamptz not null default now()
);
create table grupo_miembros (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos on delete cascade,
  -- null = persona sin cuenta (solo nombre). Si el usuario borra su cuenta, queda como persona sin cuenta
  -- y los saldos del grupo siguen cuadrando.
  user_id uuid references auth.users on delete set null,
  nombre text not null check (char_length(nombre) between 1 and 80),
  unique (grupo_id, user_id),
  unique (id, grupo_id)                       -- permite comprobar que pagador y grupo coinciden
);
create table grupo_gastos (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos on delete cascade,
  concepto text not null check (char_length(concepto) <= 200),
  importe_cents int not null check (importe_cents > 0),
  pagador_id uuid not null,
  fecha date not null default current_date,
  -- el pagador TIENE que ser miembro del mismo grupo
  foreign key (pagador_id, grupo_id) references grupo_miembros (id, grupo_id) on delete cascade
);
create table grupo_reparto (
  gasto_id uuid not null references grupo_gastos on delete cascade,
  miembro_id uuid not null references grupo_miembros on delete cascade,
  primary key (gasto_id, miembro_id)
);
create table grupo_pagos (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos on delete cascade,
  de_id uuid not null,
  a_id  uuid not null,
  importe_cents int not null check (importe_cents > 0), fecha date not null default current_date,
  foreign key (de_id, grupo_id) references grupo_miembros (id, grupo_id) on delete cascade,
  foreign key (a_id,  grupo_id) references grupo_miembros (id, grupo_id) on delete cascade
);

-- ===== Funciones =====
-- ¿Soy miembro de este grupo? (security definer evita recursión en las políticas)
create function es_miembro(g uuid) returns boolean
language sql security definer stable set search_path = public as
$$ select exists (select 1 from grupo_miembros where grupo_id = g and user_id = auth.uid()) $$;

-- El miembro al que se reparte un gasto debe ser del mismo grupo que el gasto
create function reparto_mismo_grupo() returns trigger
language plpgsql set search_path = public as $$
begin
  if not exists (
    select 1 from grupo_gastos x join grupo_miembros m on m.grupo_id = x.grupo_id
    where x.id = new.gasto_id and m.id = new.miembro_id) then
    raise exception 'El miembro no pertenece al grupo de este gasto';
  end if;
  return new;
end $$;
create trigger reparto_mismo_grupo before insert or update on grupo_reparto
  for each row execute function reparto_mismo_grupo();

-- Unirse a un grupo con su código de invitación (solo usuarios con sesión)
create function unirse_grupo(cod text, mi_nombre text) returns uuid
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

-- ===== Seguridad (RLS) =====
alter table perfiles enable row level security;
create policy propio on perfiles for all to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

do $$ declare t text; begin
  foreach t in array array['gastos_fijos','gastos','eventos','planes_usuario','ayudas_usuario','retos_usuario'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy propio on %I for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
  end loop;
  foreach t in array array['grupo_gastos','grupo_pagos'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy miembros on %I for all to authenticated using (es_miembro(grupo_id)) with check (es_miembro(grupo_id))', t);
  end loop;
end $$;

alter table ayudas enable row level security;
alter table retos  enable row level security;
create policy lectura on ayudas for select to authenticated using (true);
create policy lectura on retos  for select to authenticated using (true);

alter table grupos enable row level security;
create policy ver    on grupos for select to authenticated using (es_miembro(id) or creado_por = auth.uid());
create policy crear  on grupos for insert to authenticated with check (creado_por = auth.uid());
create policy borrar on grupos for delete to authenticated using (creado_por = auth.uid());

alter table grupo_miembros enable row level security;
create policy ver on grupo_miembros for select to authenticated using (es_miembro(grupo_id));
-- Se puede añadir: a uno mismo, o a una persona SIN cuenta (user_id nulo). Nunca a otro usuario con cuenta:
-- esos entran solos con el código de invitación (unirse_grupo).
create policy anadir on grupo_miembros for insert to authenticated with check (
  (user_id is null or user_id = auth.uid())
  and (es_miembro(grupo_id)
       or exists (select 1 from grupos g where g.id = grupo_id and g.creado_por = auth.uid())));
-- Se puede quitar: a uno mismo, a personas sin cuenta, o a cualquiera si eres el creador del grupo.
create policy quitar on grupo_miembros for delete to authenticated using (
  user_id = auth.uid()
  or (user_id is null and es_miembro(grupo_id))
  or exists (select 1 from grupos g where g.id = grupo_id and g.creado_por = auth.uid()));

alter table grupo_reparto enable row level security;
create policy miembros on grupo_reparto for all to authenticated
  using (exists (select 1 from grupo_gastos x where x.id = gasto_id and es_miembro(x.grupo_id)))
  with check (exists (select 1 from grupo_gastos x where x.id = gasto_id and es_miembro(x.grupo_id)));

-- ===== Permisos (mínimo privilegio) =====
-- Quitamos los permisos "para todo" que Supabase concede por defecto y damos solo los necesarios.
-- Ojo: si añades una tabla nueva, tendrás que darle sus permisos (y su RLS) a mano.
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on functions from public, anon, authenticated;

grant select, insert, update, delete on
  perfiles, gastos_fijos, gastos, eventos, planes_usuario, ayudas_usuario, retos_usuario,
  grupo_gastos, grupo_pagos, grupo_reparto to authenticated;
grant select, insert, delete on grupos, grupo_miembros to authenticated;
grant select on ayudas, retos to authenticated;
grant execute on function es_miembro(uuid), unirse_grupo(text, text) to authenticated;

notify pgrst, 'reload schema';
