# 💸🎓 STUD€NTIA 🧑‍🎓💰
## El gestor de finanzas 100% diseñado para estudiantes
Con STUD€NTIA, poder llevar las finanzas de uno mismo a la vez que poder estudiar sin tener quebraderos de cabeza es una realidad!
Un gestor personal dedicado a estudiantes que te hace más fácil las finanzas, con ayudas al estudiante como cupones de descuentos, asistentes de IA, diferentes planes adaptados a tu presupuesto, gestor de deudas, calendario de eventos, comparador de precios, simuladores de precios.

## Cómo ejecutarlo
Abre `index.html` en el navegador. Sin configurar nada funciona en **modo local** (los datos se guardan en el navegador).

## Activar la nube (grupos compartidos con amigos)
1. Crea un proyecto en [supabase.com](https://supabase.com).
2. En *SQL Editor*, ejecuta **por este orden** (cada uno: pegar y pulsar *Run*): `sql/schema.sql`, después `sql/retos.sql`.
   Si ya tenías la base creada con una versión anterior, ejecuta `sql/migracion.sql` y luego `sql/retos.sql`: aplican las mejoras de seguridad sin borrar datos (se pueden repetir sin problema).
3. En *Project Settings > API*, copia la **Project URL** y la clave **anon public**.
4. En `index.html`, busca `var SB_URL='',SB_KEY='';` y pega ahí los dos valores.
5. En *Authentication > Providers > Email*, desactiva "Confirm email" si quieres entrar sin confirmar el correo en la demo.

La clave `anon` es pública por diseño: la seguridad la dan las reglas RLS de `sql/`. **Nunca** pegues la clave `service_role`.

## Seguridad de los datos
- **Aislamiento por usuario (RLS):** cada persona solo ve sus propias filas y las de los grupos o retos a los que pertenece. Un usuario no puede ver el perfil, los gastos ni los grupos de otro.
- **Mínimo privilegio:** el rol `authenticated` solo tiene SELECT/INSERT/UPDATE/DELETE donde la app lo necesita (sin TRUNCATE) y el rol `anon` (sin sesión) no tiene acceso a ninguna tabla ni función.
- **Entrada a grupos y retos solo con código**, de 10 caracteres aleatorios. Un miembro no puede añadir a otros usuarios con cuenta ni expulsar a otros usuarios.
- **Integridad:** el pagador de un gasto y el reparto deben ser miembros del mismo grupo; hay límites de longitud para evitar basura en la base de datos.
- **Secretos:** la clave de Claude vive solo en la Edge Function de Supabase (o en `.env`, que está en `.gitignore`). Usa `.env.example` como plantilla y no subas nunca un `.env` real.
- En producción activa la confirmación de correo (*Confirm email*), que aquí se desactiva solo para la demo.

## Qué usa la base de datos hoy
Solo la pestaña **Grupos** (cuentas, gastos, pagos e invitación por código). El resto de secciones guarda en el navegador; sus tablas ya están en el esquema para conectarlas después.

## Estado
Prototipo de hackathon. Ayudas, cuantías y plazos son orientativos: verifícalos antes de presentarlos como datos oficiales.

## Chatbot con Claude
El asistente usa la API de Claude a través de una Edge Function de Supabase (`supabase/functions/chat`), así la clave nunca llega al navegador. Solo responde a usuarios con sesión iniciada; sin sesión, la app usa el asistente básico por reglas.

1. Instala la [CLI de Supabase](https://supabase.com/docs/guides/cli) y enlaza el proyecto: `supabase link --project-ref TU_REF`
2. Sube la clave como secreto desde tu `.env` local (que está en `.gitignore`): `supabase secrets set --env-file .env`
3. Publica la función: `supabase functions deploy chat`
4. (Opcional) Cambia de modelo: `supabase secrets set CLAUDE_MODEL=claude-haiku-5-5`

Las órdenes con efecto (bloquear tarjeta, recordatorios, Modo Supervivencia) siguen resolviéndose en la app; el resto va a Claude con tu presupuesto, ayudas y deudas de grupo como contexto. Al IA le llegan tu nombre, edad, estudios, los dos primeros dígitos del código postal y tus cifras del mes.
