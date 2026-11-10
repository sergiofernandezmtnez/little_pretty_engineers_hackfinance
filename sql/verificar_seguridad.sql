-- COMPROBACIÓN de seguridad. Pégalo en Supabase (SQL Editor) y ejecútalo. No modifica nada.
-- Cada fila debe decir "OK". Si alguna dice "FALLO", ejecuta sql/seguridad.sql y vuelve a probar.

select 'Tabla con RLS activada: ' || c.relname as comprobacion,
       case when c.relrowsecurity then 'OK' else 'FALLO' end as resultado
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'

union all
select 'perfiles: política "' || policyname || '" solo para usuarios con sesión y limitada a su dueño',
       case when roles = '{authenticated}' and qual like '%auth.uid()%' and with_check like '%auth.uid()%' then 'OK' else 'FALLO' end
from pg_policies where schemaname = 'public' and tablename = 'perfiles'

union all
select 'perfiles: número de políticas (debe ser 1)',
       case when count(*) = 1 then 'OK' else 'FALLO' end
from pg_policies where schemaname = 'public' and tablename = 'perfiles'

union all
select 'Sin sesión (anon) NO puede leer/escribir/borrar: ' || table_name,
       'FALLO'
from information_schema.role_table_grants
where table_schema = 'public' and grantee = 'anon'

union all
select 'Sin sesión (anon) no tiene permisos sobre ninguna tabla',
       case when not exists (select 1 from information_schema.role_table_grants
                             where table_schema = 'public' and grantee = 'anon') then 'OK' else 'FALLO' end

union all
select 'Con sesión nadie puede hacer TRUNCATE: ' || table_name,
       'FALLO'
from information_schema.role_table_grants
where table_schema = 'public' and grantee = 'authenticated' and privilege_type = 'TRUNCATE'

order by 2 desc, 1;

-- PRUEBA REAL (opcional): simula a alguien SIN sesión intentando leer los perfiles.
-- Debe dar el error "permission denied for table perfiles". Ejecútalo por separado:
--   begin; set local role anon; select * from public.perfiles; rollback;
