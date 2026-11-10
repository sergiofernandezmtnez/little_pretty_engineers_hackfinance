-- Catálogo de becas y ayudas de STUD€NTIA. Ejecuta este script en Supabase: SQL Editor -> New query -> Run.
-- ORDEN: schema.sql -> migracion.sql -> retos.sql -> amigos.sql -> ESTE ARCHIVO -> seguridad.sql
-- Se puede ejecutar todas las veces que quieras: actualiza los datos sin duplicar nada.
--
-- LOS DATOS SE EDITAN EN  datos/becas_y_ayudas.csv  (no a mano en este archivo):
--   1) Edita o añade filas en el CSV.
--   2) Ejecuta:  python scripts/csv_a_sql.py   (reescribe SOLO el bloque de datos de más abajo)
--   3) Pega este archivo entero en el SQL Editor de Supabase y pulsa Run.
--
-- SEGURIDAD: es información pública (sin datos personales), pero aun así:
--   * RLS activada. Solo se puede LEER y solo con sesión iniciada (el rol "anon" no tiene acceso).
--   * Nadie puede escribir desde la app ni desde la API: los datos solo cambian desde el SQL Editor.
--   * Límites de longitud y enlaces solo https.

create table if not exists public.becas_ayudas (
  id             int  primary key,
  titulo         text not null check (char_length(titulo) between 1 and 200),
  organismo      text not null check (char_length(organismo) <= 200),
  categoria      text not null check (char_length(categoria) <= 80),
  cuantia_maxima text          check (char_length(cuantia_maxima) <= 400),
  requisitos     text          check (char_length(requisitos) <= 1000),
  plazo          text          check (char_length(plazo) <= 200),
  estado         text not null check (estado in ('Abierta','Próximamente','Permanente','Cerrada')),
  ambito         text not null check (char_length(ambito) <= 40),
  enlace_oficial text          check (enlace_oficial ~ '^https://[^[:space:]]+$' and char_length(enlace_oficial) <= 500),
  actualizado    timestamptz not null default now()
);

alter table public.becas_ayudas enable row level security;
drop policy if exists lectura on public.becas_ayudas;
create policy lectura on public.becas_ayudas for select to authenticated using (true);

revoke all on public.becas_ayudas from anon, authenticated;
grant select on public.becas_ayudas to authenticated;

-- BEGIN DATOS (generado por scripts/csv_a_sql.py: no lo edites a mano)
insert into public.becas_ayudas (id, titulo, organismo, categoria, cuantia_maxima, requisitos, plazo, estado, ambito, enlace_oficial) values
  (1, 'Beca General MEC - Grado y Máster Universitario', 'Ministerio de Educación, Formación Profesional y Deportes', 'Universitaria', 'Matrícula 100% + Fija hasta 2.700 € (Residencia) + 1.700 € (Renta) + Variable', 'Matrícula de al menos 60 créditos, cumplimiento de umbrales de renta familiar y nota media mínima exigida según estudio.', 'Marzo - Mayo (según convocatoria anual)', 'Próximamente', 'Nacional', 'https://www.becaseducacion.gob.es/becas-y-ayudas/universidad-grado-master.html'),
  (2, 'Beca General MEC - Bachillerato, FP y Otros Estudios', 'Ministerio de Educación, Formación Profesional y Deportes', 'FP / Bachillerato', 'Cuantía básica (300 €) + Residencia (2.700 €) + Renta (1.700 €) + Excelencia (50-125 €)', 'Estar matriculado en curso completo (o mínimo 50% de asignaturas/módulos), nota media >= 5.0 y cumplir umbrales de renta.', 'Marzo - Mayo', 'Próximamente', 'Nacional', 'https://www.becaseducacion.gob.es/becas-y-ayudas/fp-bachillerato-otros.html'),
  (3, 'Bono Alquiler Joven', 'Ministerio de Vivienda y Comunidades Autónomas', 'Alquiler y Vivienda', '250 €/mes durante 24 meses (Total 6.000 €)', 'Jóvenes de 18 a 35 años, contrato de alquiler (máx. 600€-900€ piso / 300€-450€ habitación) e ingresos inferiores a 3x IPREM.', 'Abierto según convocatoria autonómica', 'Abierta', 'Autonómico', 'https://www.mivau.gob.es/vivienda/bono-alquiler-joven'),
  (4, 'Ayuda de Movilidad Internacional Erasmus+', 'Unión Europea / SEPIE', 'Movilidad / Erasmus', '250 € a 500 €/mes (según país de destino y nivel de renta)', 'Estudiantes universitarios o de FP Grado Superior admitidos en programa de movilidad Erasmus+.', 'Convocatoria anual de cada universidad / centro', 'Abierta', 'Internacional', 'https://sepie.es/educacion-superior/erasmus.html'),
  (5, 'Becas de Excelencia Académica para Estudios Universitarios', 'Comunidades Autónomas (ej. Comunidad de Madrid)', 'Excelencia', '3.000 € directos', 'Nota media destacada (habitualmente superior a 8.0-9.0 según titulación) y matriculado en universidad autonómica.', 'Septiembre - Octubre', 'Próximamente', 'Autonómico', 'https://sede.comunidad.madrid/ayudas-becas-subvenciones'),
  (6, 'Ayudas para Necesidades Específicas de Apoyo Educativo (NEAE)', 'Ministerio de Educación, Formación Profesional y Deportes', 'Apoyo Educativo', 'Subsidio de cuantía fija + reeducación + 400 € ayuda subsidio general', 'Acreditar necesidad específica derivada de discapacidad, trastorno grave o altas capacidades intelectuales.', 'Mayo - Septiembre', 'Próximamente', 'Nacional', 'https://www.becaseducacion.gob.es/becas-y-ayudas/necesidades-especificas.html'),
  (7, 'Becas Segunda Oportunidad (FP y Formación)', 'Comunidades Autónomas y Fondos Europeos', 'FP / Bachillerato', 'Hasta 2.800 € para cubrir coste del curso', 'Jóvenes entre 16 y 30 años inscritos en Garantía Juvenil que deseen retomar sus estudios profesionales.', 'Julio - Septiembre', 'Próximamente', 'Autonómico', 'https://www.sepe.es/HomeSepe/Personas/encontrar-trabajo/Garantia-Juvenil.html'),
  (8, 'Becas Santander Estudios - Progreso y Movilidad', 'Banco Santander / Universidades', 'Universitaria', '1.000 € a 4.000 €', 'Buen expediente académico, haber sido beneficiario de beca MEC el curso anterior y matricularse en titulación universitaria.', 'Noviembre - Marzo', 'Abierta', 'Nacional', 'https://www.app.santanderopenacademy.com/es/program/search'),
  (9, 'Ayuda al Transporte y Comedor Universitario', 'Universidades Públicas y CCAA', 'Transporte / Comedor', 'Descuento del 50% al 100% en abono transporte / Vouchers de comedor', 'Estudiantes matriculados en universidad pública con residencia a cierta distancia del campus y bajos ingresos familiares.', 'Octubre - Noviembre', 'Abierta', 'Autonómico', 'https://www.crdpu.es'),
  (10, 'Ayudas para la Obtención del Carnet de Conducir B / Profesional', 'Comunidades Autónomas (ej. Madrid, La Rioja, Galicia)', 'Movilidad / Empleo', '600 € a 2.000 € de préstamo o subvención a fondo perdido', 'Jóvenes desempleados o estudiantes empadronados en la CCAA entre 18 y 30 años.', 'Convocatoria abierta todo el año', 'Permanente', 'Autonómico', 'https://www.comunidad.madrid/servicios/transporte/ayudas-carnet-conducir'),
  (11, 'Beca de Colaboración en Departamentos Universitarios (curso 2026-27)', 'Ministerio de Educación, Formación Profesional y Deportes', 'Universitaria', '2.000 € (cuantía fija)', 'Estudiantes de Grado o de primer curso de Máster oficial matriculados en 2026-27 que presenten un proyecto de colaboración avalado por un departamento. Compatible con las becas generales del Ministerio.', 'Del 21/07/2026 al 22/09/2026', 'Cerrada', 'Nacional', 'https://sede.educacion.gob.es'),
  (12, 'Bono Cultural Joven 2026', 'Ministerio de Cultura', 'Cultura y Ocio', '400 € en tarjeta prepago (12 meses para gastarlos)', 'Cumplir 18 años en 2026 (nacidos en 2008) con nacionalidad española o residencia legal en España. Sin requisito de renta.', 'Del 22/06/2026 al 31/10/2026 (23:59)', 'Cerrada', 'Nacional', 'https://bonoculturajoven.gob.es'),
  (13, 'Abono Joven de Transporte de Madrid', 'Consorcio Regional de Transportes de Madrid (CRTM)', 'Transporte', '10 €/mes para todas las zonas (50 % de descuento sobre el precio normal)', 'Tener entre 15 y 25 años (se puede usar hasta cumplir los 26) y una Tarjeta Transporte Público personal.', 'Sin plazo de solicitud. Bonificación vigente hasta el 31/12/2026', 'Abierta', 'Autonómico', 'https://www.crtm.es'),
  (14, 'Ayudas FPU 2026 (contratos predoctorales)', 'Ministerio de Ciencia, Innovación y Universidades / Agencia Estatal de Investigación', 'Investigación', '143.350 € por ayuda (contrato predoctoral de hasta 4 años)', 'Para hacer una tesis doctoral en una universidad o centro de investigación español. Pesa sobre todo la nota media ponderada del expediente.', 'Del 20/10/2026 al 12/11/2026 (hay fuentes que indican el 20/11: confirmar en la web de la AEI)', 'Abierta', 'Nacional', 'https://www.aei.gob.es/convocatorias/buscador-convocatorias/ayudas-formacion-profesorado-universitario-fpu-2026')
on conflict (id) do update set
  titulo = excluded.titulo,
  organismo = excluded.organismo,
  categoria = excluded.categoria,
  cuantia_maxima = excluded.cuantia_maxima,
  requisitos = excluded.requisitos,
  plazo = excluded.plazo,
  estado = excluded.estado,
  ambito = excluded.ambito,
  enlace_oficial = excluded.enlace_oficial,
  actualizado = now();

-- El CSV manda: lo que ya no esté en el CSV se borra de la tabla
delete from public.becas_ayudas where id not in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14);
-- END DATOS

notify pgrst, 'reload schema';
