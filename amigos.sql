-- Amigos e invitaciones de STUD€NTIA. Ejecuta este script UNA vez en Supabase: SQL Editor -> New query -> Run.
-- ORDEN: schema.sql -> migracion.sql -> retos.sql -> este archivo (amigos.sql). Se puede ejecutar varias veces.
-- Requisitos: tablas de grupos (grupos, grupo_miembros, función unirse_grupo) y las tablas de retos de retos.sql.
-- SEGURIDAD: RLS sin políticas (solo se accede por las funciones), mínimo privilegio (revoke + grant execute
-- solo a "authenticated"), search_path fijo, código de amigo de 10 caracteres y límites de longitud.

create table if not exists public.amigos_perfil (
  user_id uuid primary key,
  codigo text not null unique default substr(replace(gen_random_uuid()::text, '-', ''), 1, 10),
  nombre text
);

create table if not exists public.amistades (
  id uuid primary key default gen_random_uuid(),
  de uuid not null,
  para uuid not null,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'aceptada')),
  created_at timestamptz not null default now(),
  check (de <> para)
);
create unique index if not exists amistades_par_uq on public.amistades (least(de, para), greatest(de, para));

create table if not exists public.invitaciones (
  id uuid primary key default gen_random_uuid(),
  tipo text not null check (tipo in ('reto', 'grupo')),
  ref uuid not null,
  titulo text,
  de uuid not null,
  para uuid not null,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'aceptada', 'rechazada')),
  created_at timestamptz not null default now()
);

-- Los códigos de amigo antiguos (6 caracteres) se pueden adivinar: los nuevos son de 10.
alter table public.amigos_perfil alter column codigo set default substr(replace(gen_random_uuid()::text, '-', ''), 1, 10);

-- Límites de longitud (NOT VALID: solo se aplican a lo que se escriba desde ahora)
do $$
declare c record;
begin
  for c in select * from (values
    ('amigos_perfil', 'amigos_perfil_nombre_len', 'check (nombre is null or char_length(nombre) <= 80)'),
    ('invitaciones',  'invitaciones_titulo_len',  'check (titulo is null or char_length(titulo) <= 80)')
  ) as v(t, n, d) loop
    if not exists (select 1 from pg_constraint where conname = c.n and conrelid = ('public.' || c.t)::regclass) then
      execute format('alter table public.%I add constraint %I %s not valid', c.t, c.n, c.d);
    end if;
  end loop;
end $$;

-- Sin políticas: nadie lee ni escribe estas tablas directamente; todo pasa por las funciones de abajo.
alter table public.amigos_perfil enable row level security;
alter table public.amistades enable row level security;
alter table public.invitaciones enable row level security;

-- Tu código de amigo, tus amigos, solicitudes e invitaciones pendientes
create or replace function public.mi_red(mi_nombre text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare yo uuid := auth.uid(); cod text;
begin
  if yo is null then raise exception 'Inicia sesión primero'; end if;
  insert into amigos_perfil (user_id, nombre) values (yo, left(trim(mi_nombre), 80))
    on conflict (user_id) do update set nombre = coalesce(nullif(left(trim(mi_nombre), 80), ''), amigos_perfil.nombre);
  select codigo into cod from amigos_perfil where user_id = yo;
  return jsonb_build_object(
    'codigo', cod,
    'amigos', coalesce((select jsonb_agg(jsonb_build_object('id', o.otro, 'nombre', coalesce(p.nombre, 'Amigo')) order by p.nombre)
        from (select case when a.de = yo then a.para else a.de end as otro from amistades a
              where a.estado = 'aceptada' and yo in (a.de, a.para)) o
        left join amigos_perfil p on p.user_id = o.otro), '[]'::jsonb),
    'recibidas', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'nombre', coalesce(p.nombre, 'Alguien')))
        from amistades a left join amigos_perfil p on p.user_id = a.de
        where a.para = yo and a.estado = 'pendiente'), '[]'::jsonb),
    'enviadas', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'nombre', coalesce(p.nombre, 'Alguien')))
        from amistades a left join amigos_perfil p on p.user_id = a.para
        where a.de = yo and a.estado = 'pendiente'), '[]'::jsonb),
    'invitaciones', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'tipo', i.tipo, 'titulo', i.titulo, 'de', coalesce(p.nombre, 'Un amigo')) order by i.created_at)
        from invitaciones i left join amigos_perfil p on p.user_id = i.de
        where i.para = yo and i.estado = 'pendiente'
          and ((i.tipo = 'reto' and exists (select 1 from retos r where r.id = i.ref))
            or (i.tipo = 'grupo' and exists (select 1 from grupos g where g.id = i.ref)))), '[]'::jsonb)
  );
end $$;

-- Pedir amistad con el código de otra persona (si ya te la había pedido, os hacéis amigos)
create or replace function public.pedir_amistad(cod text, mi_nombre text)
returns void language plpgsql security definer set search_path = public as $$
declare yo uuid := auth.uid(); otro uuid; ex record;
begin
  if yo is null then raise exception 'Inicia sesión primero'; end if;
  insert into amigos_perfil (user_id, nombre) values (yo, left(trim(mi_nombre), 80))
    on conflict (user_id) do update set nombre = coalesce(nullif(left(trim(mi_nombre), 80), ''), amigos_perfil.nombre);
  select user_id into otro from amigos_perfil where codigo = lower(trim(cod));
  if otro is null then raise exception 'Código de amigo no válido'; end if;
  if otro = yo then raise exception 'Ese es tu propio código'; end if;
  select * into ex from amistades where least(de, para) = least(yo, otro) and greatest(de, para) = greatest(yo, otro);
  if found then
    if ex.estado = 'aceptada' then raise exception 'Ya sois amigos';
    elsif ex.de = otro then update amistades set estado = 'aceptada' where id = ex.id;
    else raise exception 'Ya le has enviado una solicitud';
    end if;
  else
    if (select count(*) from amistades where de = yo and estado = 'pendiente') >= 50 then
      raise exception 'Demasiadas solicitudes pendientes';
    end if;
    insert into amistades (de, para) values (yo, otro);
  end if;
end $$;

create or replace function public.responder_amistad(aid uuid, aceptar boolean)
returns void language plpgsql security definer set search_path = public as $$
declare yo uuid := auth.uid();
begin
  if yo is null then raise exception 'Inicia sesión primero'; end if;
  if aceptar then update amistades set estado = 'aceptada' where id = aid and para = yo and estado = 'pendiente';
  else delete from amistades where id = aid and para = yo and estado = 'pendiente';
  end if;
end $$;

create or replace function public.quitar_amigo(otro uuid)
returns void language plpgsql security definer set search_path = public as $$
declare yo uuid := auth.uid();
begin
  if yo is null then raise exception 'Inicia sesión primero'; end if;
  delete from amistades where least(de, para) = least(yo, otro) and greatest(de, para) = greatest(yo, otro);
end $$;

-- Invitar a un amigo a un reto o a un grupo en el que ya participas
create or replace function public.invitar_amigo(tipo text, ref uuid, amigo uuid)
returns void language plpgsql security definer set search_path = public as $$
declare yo uuid := auth.uid(); tit text;
begin
  if yo is null then raise exception 'Inicia sesión primero'; end if;
  if not exists (select 1 from amistades where estado = 'aceptada'
      and least(de, para) = least(yo, amigo) and greatest(de, para) = greatest(yo, amigo)) then
    raise exception 'Solo puedes invitar a tus amigos';
  end if;
  if tipo = 'reto' then
    select nombre into tit from retos where id = ref;
    if not exists (select 1 from reto_miembros where reto_id = ref and user_id = yo) then raise exception 'No participas en ese reto'; end if;
    if exists (select 1 from reto_miembros where reto_id = ref and user_id = amigo) then raise exception 'Ya participa en el reto'; end if;
  elsif tipo = 'grupo' then
    select nombre into tit from grupos where id = ref;
    if not exists (select 1 from grupo_miembros where grupo_id = ref and user_id = yo) then raise exception 'No estás en ese grupo'; end if;
    if exists (select 1 from grupo_miembros where grupo_id = ref and user_id = amigo) then raise exception 'Ya está en el grupo'; end if;
  else
    raise exception 'Tipo de invitación no válido';
  end if;
  if exists (select 1 from invitaciones i where i.tipo = invitar_amigo.tipo and i.ref = invitar_amigo.ref and i.para = amigo and i.estado = 'pendiente') then
    raise exception 'Ya tiene una invitación pendiente';
  end if;
  if (select count(*) from invitaciones i where i.de = yo and i.estado = 'pendiente') >= 50 then
    raise exception 'Demasiadas invitaciones pendientes';
  end if;
  insert into invitaciones (tipo, ref, titulo, de, para) values (tipo, ref, left(tit, 80), yo, amigo);
end $$;

-- Aceptar o rechazar una invitación (al aceptar, entras en el reto o el grupo).
-- Devuelve 'ok' o 'caducada' (si el reto o el grupo ya se borró: la invitación se elimina y no da error).
drop function if exists public.responder_invitacion(uuid, boolean, text);
create or replace function public.responder_invitacion(inv uuid, aceptar boolean, mi_nombre text)
returns text language plpgsql security definer set search_path = public as $$
declare yo uuid := auth.uid(); i record; cod text; n text := coalesce(nullif(left(trim(mi_nombre), 80), ''), 'Amigo');
begin
  if yo is null then raise exception 'Inicia sesión primero'; end if;
  select * into i from invitaciones where id = inv and para = yo and estado = 'pendiente';
  if not found then raise exception 'Invitación no válida'; end if;
  if not aceptar then
    update invitaciones set estado = 'rechazada' where id = inv;
    return 'ok';
  end if;
  if i.tipo = 'reto' then
    if not exists (select 1 from retos where id = i.ref) then
      delete from invitaciones where id = inv;
      return 'caducada';
    end if;
    insert into reto_miembros (reto_id, user_id, nombre) values (i.ref, yo, n)
      on conflict (reto_id, user_id) do nothing;
  else
    select codigo into cod from grupos where id = i.ref;
    if cod is null then
      delete from invitaciones where id = inv;
      return 'caducada';
    end if;
    perform public.unirse_grupo(cod, n);
  end if;
  update invitaciones set estado = 'aceptada' where id = inv;
  return 'ok';
end $$;

-- Si se borra un reto o un grupo, sus invitaciones desaparecen con él
create or replace function public.limpiar_invitaciones() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from invitaciones where ref = old.id and tipo = tg_argv[0];
  return old;
end $$;
drop trigger if exists limpiar_invitaciones_reto on public.retos;
create trigger limpiar_invitaciones_reto after delete on public.retos
  for each row execute function public.limpiar_invitaciones('reto');
drop trigger if exists limpiar_invitaciones_grupo on public.grupos;
create trigger limpiar_invitaciones_grupo after delete on public.grupos
  for each row execute function public.limpiar_invitaciones('grupo');

-- Limpieza única: invitaciones que apuntan a retos o grupos que ya no existen
delete from public.invitaciones i
 where (i.tipo = 'reto'  and not exists (select 1 from public.retos  r where r.id = i.ref))
    or (i.tipo = 'grupo' and not exists (select 1 from public.grupos g where g.id = i.ref));

-- Reparación: la clave externa de reto_miembros debe apuntar a public.retos (id uuid)
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'retos'
             and column_name = 'id' and data_type = 'uuid')
     and to_regclass('public.reto_miembros') is not null then
    delete from public.reto_miembros m where not exists (select 1 from public.retos r where r.id = m.reto_id);
    alter table public.reto_miembros drop constraint if exists reto_miembros_reto_id_fkey;
    alter table public.reto_miembros add constraint reto_miembros_reto_id_fkey
      foreign key (reto_id) references public.retos(id) on delete cascade;
  end if;
end $$;
-- Permisos (mínimo privilegio): nadie toca las tablas directamente y solo usuarios con sesión ejecutan las funciones
revoke all on public.amigos_perfil, public.amistades, public.invitaciones from anon, authenticated;
revoke execute on function
  public.mi_red(text), public.pedir_amistad(text, text), public.responder_amistad(uuid, boolean),
  public.quitar_amigo(uuid), public.invitar_amigo(text, uuid, uuid), public.responder_invitacion(uuid, boolean, text),
  public.limpiar_invitaciones()
  from public, anon;
grant execute on function
  public.mi_red(text), public.pedir_amistad(text, text), public.responder_amistad(uuid, boolean),
  public.quitar_amigo(uuid), public.invitar_amigo(text, uuid, uuid), public.responder_invitacion(uuid, boolean, text)
  to authenticated;

-- Los pagos entre miembros de un grupo llevan fecha (para reflejarlos en el ticket del mes correcto)
alter table public.grupo_pagos add column if not exists fecha date not null default current_date;
notify pgrst, 'reload schema';

-- OPCIONAL: renovar los códigos de amigo antiguos (de 6 caracteres). Tendrás que pasar de nuevo tu código.
-- update public.amigos_perfil set codigo = substr(replace(gen_random_uuid()::text, '-', ''), 1, 10) where char_length(codigo) < 10;
