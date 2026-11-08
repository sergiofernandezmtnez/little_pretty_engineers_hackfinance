-- STUD€NTIA / Fin de Mes · esquema para Supabase (PostgreSQL)
-- Pega este archivo entero en Supabase > SQL Editor > Run.
-- Importes siempre en céntimos (enteros) para evitar errores de redondeo.

create extension if not exists pgcrypto;

-- ===== Datos personales =====
create table perfiles (
  id uuid primary key references auth.users on delete cascade,
  nombre text not null, edad int, estudios text, ccaa text, centro text, ambito text, vivienda text,
  modo text not null default 'normal' check (modo in ('normal','sos')),
  gustos text[] not null default '{}',
  datos jsonb,                                  -- estado completo de la app (perfil, ingresos, gastos, planes...)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table gastos_fijos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  tipo text not null, importe_cents int not null check (importe_cents >= 0)
);
create table gastos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  fecha date not null default current_date, categoria text not null, concepto text,
  importe_cents int not null check (importe_cents > 0),
  pago text not null default 'tarjeta' check (pago in ('tarjeta','efectivo'))
);
create table eventos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  titulo text not null, fecha date not null, tipo text, importe_cents int not null default 0
);
create table planes_usuario (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  plan_id text not null, objetivo_cents int not null, mensual_cents int not null,
  ahorrado_cents int not null default 0, activo boolean not null default true,
  primary key (user_id, plan_id)
);

-- ===== Catálogos (lectura pública) =====
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
  nombre text not null,
  codigo text not null unique default substr(md5(random()::text || clock_timestamp()::text), 1, 6),
  creado_por uuid not null default auth.uid() references auth.users,
  created_at timestamptz not null default now()
);
create table grupo_miembros (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos on delete cascade,
  user_id uuid references auth.users,      -- null = persona sin cuenta (solo nombre)
  nombre text not null,
  unique (grupo_id, user_id)
);
create table grupo_gastos (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos on delete cascade,
  concepto text not null, importe_cents int not null check (importe_cents > 0),
  pagador_id uuid not null references grupo_miembros on delete cascade,
  fecha date not null default current_date
);
create table grupo_reparto (
  gasto_id uuid not null references grupo_gastos on delete cascade,
  miembro_id uuid not null references grupo_miembros on delete cascade,
  primary key (gasto_id, miembro_id)
);
create table grupo_pagos (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos on delete cascade,
  de_id uuid not null references grupo_miembros on delete cascade,
  a_id  uuid not null references grupo_miembros on delete cascade,
  importe_cents int not null check (importe_cents > 0), fecha date not null default current_date
);

-- ===== Seguridad (RLS) =====
create function es_miembro(g uuid) returns boolean
language sql security definer stable set search_path = public as
$$ select exists (select 1 from grupo_miembros where grupo_id = g and user_id = auth.uid()) $$;

alter table perfiles enable row level security;
create policy propio on perfiles for all using (id = auth.uid()) with check (id = auth.uid());

do $$ declare t text; begin
  foreach t in array array['gastos_fijos','gastos','eventos','planes_usuario','ayudas_usuario','retos_usuario'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy propio on %I for all using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
  end loop;
  foreach t in array array['grupo_gastos','grupo_pagos'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy miembros on %I for all using (es_miembro(grupo_id)) with check (es_miembro(grupo_id))', t);
  end loop;
end $$;

alter table ayudas enable row level security;
alter table retos  enable row level security;
create policy lectura on ayudas for select using (true);
create policy lectura on retos  for select using (true);

alter table grupos enable row level security;
create policy ver on grupos for select using (es_miembro(id) or creado_por = auth.uid());
create policy crear on grupos for insert with check (creado_por = auth.uid());
create policy borrar on grupos for delete using (creado_por = auth.uid());

alter table grupo_miembros enable row level security;
create policy ver on grupo_miembros for select using (es_miembro(grupo_id));
create policy anadir on grupo_miembros for insert with check (
  es_miembro(grupo_id) or exists (select 1 from grupos g where g.id = grupo_id and g.creado_por = auth.uid()));
create policy quitar on grupo_miembros for delete using (es_miembro(grupo_id));

alter table grupo_reparto enable row level security;
create policy miembros on grupo_reparto for all
  using (exists (select 1 from grupo_gastos x where x.id = gasto_id and es_miembro(x.grupo_id)))
  with check (exists (select 1 from grupo_gastos x where x.id = gasto_id and es_miembro(x.grupo_id)));

-- Unirse a un grupo con su código de invitación
create function unirse_grupo(cod text, mi_nombre text) returns uuid
language plpgsql security definer set search_path = public as $$
declare g uuid;
begin
  select id into g from grupos where codigo = lower(trim(cod));
  if g is null then raise exception 'Código de grupo no válido'; end if;
  insert into grupo_miembros (grupo_id, user_id, nombre) values (g, auth.uid(), mi_nombre)
    on conflict (grupo_id, user_id) do nothing;
  return g;
end $$;
