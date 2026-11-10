-- BLINDAJE de la base de datos. Ejecútalo en Supabase (SQL Editor > New query > Run) DESPUÉS de
-- schema.sql, migracion.sql, retos.sql y amigos.sql. Se puede ejecutar todas las veces que quieras.
--
-- Qué arregla (los 3 fallos que detectó un revisor de ciberseguridad):
--   1) GET  /rest/v1/perfiles          -> lista los perfiles de TODOS los usuarios
--   2) POST /rest/v1/perfiles          -> escribe datos de otros usuarios conociendo su ID
--   3) DELETE /rest/v1/perfiles?id=eq. -> borra perfiles ajenos
-- Los tres ocurren si la tabla "perfiles" NO tiene RLS activada, o tiene una política abierta
-- (por ejemplo creada a mano desde el panel de Supabase), o el rol "anon" conserva permisos.
-- Este script lo fuerza todo al estado correcto, aunque la base de datos esté a medias.
--
-- Sobre la "inyección SQL": "eq." en PostgREST no es SQL sin sanear; el valor viaja como parámetro y
-- no se puede inyectar. El riesgo real era la falta de RLS, que es lo que se corrige aquí.

-- 1) RLS activada en TODAS las tablas de public (una tabla sin políticas queda cerrada para todos)
do $$ declare t record; begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t.tablename);
  end loop;
end $$;

-- 2) Tablas personales: se borran TODAS las políticas que existan (también las creadas a mano y abiertas)
--    y se deja solo "cada usuario ve y toca únicamente lo suyo".
do $$ declare p record; begin
  for p in select schemaname, tablename, policyname from pg_policies
           where schemaname = 'public'
             and tablename in ('perfiles','gastos_fijos','gastos','eventos','planes_usuario','ayudas_usuario','retos_usuario',
                               'amigos_perfil','amistades','invitaciones') loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

create policy propio on public.perfiles for all to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

do $$ declare t text; begin
  foreach t in array array['gastos_fijos','gastos','eventos','planes_usuario','ayudas_usuario','retos_usuario'] loop
    if to_regclass(format('public.%I', t)) is not null then
      execute format('create policy propio on public.%I for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
    end if;
  end loop;
end $$;
-- (amigos_perfil, amistades e invitaciones se quedan SIN políticas a propósito: solo se usan a través de sus funciones)

-- 3) Sin sesión (rol "anon") no se puede tocar nada: ni tablas ni funciones
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from public, anon;
alter default privileges in schema public revoke all on tables    from anon;
alter default privileges in schema public revoke all on functions from public, anon;

-- 4) Con sesión: nada de TRUNCATE (se salta la RLS), REFERENCES ni TRIGGER
revoke truncate, references, trigger on all tables in schema public from authenticated;

-- 5) Las funciones siguen disponibles para usuarios con sesión (todas comprueban auth.uid() dentro)
grant execute on all functions in schema public to authenticated;

-- 6) Un perfil solo puede tener el id de su dueño
alter table public.perfiles alter column id set not null;

notify pgrst, 'reload schema';
