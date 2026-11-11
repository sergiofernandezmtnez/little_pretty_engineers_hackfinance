# 💸🎓 STUD€NTIA 🧑‍🎓💰
## El gestor de finanzas 100% diseñado para estudiantes

**Versión publicada:** <https://studentia-eta.vercel.app> · **Repositorio:** <https://github.com/sergiofernandezmtnez/little_pretty_engineers_hackfinance>

- [1. Descripción](#1-descripción)
- [2. Requisitos](#2-requisitos)
- [3. Instalación](#3-instalación)
- [4. Configuración](#4-configuración)
- [5. Ejecución](#5-ejecución)
- [6. Prueba](#6-prueba)
- [7. Seguridad](#7-seguridad)
- [8. Estructura del repositorio](#8-estructura-del-repositorio)

---

## 1. Descripción

**El problema:** muchos estudiantes llegan a fin de mes sin saber cuánto pueden gastar, no conocen las becas y ayudas a las que tienen derecho y no tienen educación financiera ni dinero para un asesor.

**La solución:** STUD€NTIA es una aplicación web que, a partir de lo que entra y sale cada mes, te dice **cuánto puedes gastar hoy**, qué ayudas te corresponden y si te salen las cuentas para independizarte. Un asistente de IA (Claude) responde dudas usando tu presupuesto como contexto. No se conecta a ningún banco.

| Sección | Qué hace |
|---|---|
| **Inicio** | Tu presupuesto del mes y el límite diario de gasto |
| **Ayudas** | Ayudas que encajan con tu perfil y un **catálogo oficial de becas y ayudas** (plazo, cuantía, requisitos y enlace a la convocatoria) |
| **Calendario** | Eventos y fechas con gasto |
| **Retos** | Retos de ahorro que puedes compartir con amigos mediante un código |
| **Grupos** | Cuentas compartidas (gastos, reparto y pagos entre amigos) |
| **Mensajes** | Recordatorios amables entre amigos; la IA revisa que el mensaje sea respetuoso y trate de dinero |
| **Emancipación** | Simulación de si te salen las cuentas para independizarte |
| **Planes** | Planes de ahorro con objetivo y aportación mensual |
| **Asistente** | Chat con Claude. Con sesión, cada respuesta se puede **escuchar en voz alta** con una voz generada por IA (ElevenLabs), de hombre o de mujer. Sin sesión iniciada, funciona un asistente básico por reglas |
| **Intereses** | Explicación del interés simple y compuesto y de la diferencia con invertir |

**Tecnología:** una sola página (`index.html`, HTML + CSS + JavaScript, sin paso de compilación) · [Supabase](https://supabase.com) (autenticación, PostgreSQL con RLS y Edge Functions) · API de Claude (Anthropic) · API de texto a voz de [ElevenLabs](https://elevenlabs.io) (voz del asistente).

**Dos modos de uso:** sin configurar nada funciona en **modo local** (los datos se guardan en el navegador). Con cuenta, los datos se guardan en la nube y los grupos, retos y mensajes se comparten entre usuarios.

---

## 2. Requisitos

**Para probar la aplicación** solo necesitas un navegador moderno (Chrome, Edge, Firefox o Safari) y conexión a internet.

**Para montar tu propia instancia:**

| Qué | Para qué | Obligatorio |
|---|---|---|
| Cuenta de [Supabase](https://supabase.com) (plan gratuito) | Cuentas de usuario, base de datos y función del chat | Solo para la nube |
| Clave de API de [Anthropic](https://console.anthropic.com) | Asistente con Claude y moderación de mensajes | Solo para el chat con IA |
| Cuenta de [ElevenLabs](https://elevenlabs.io): clave de API e IDs de las voces (hombre y mujer) | Voz del asistente (texto a voz) | Solo para la voz con IA |
| [Git](https://git-scm.com) | Clonar el repositorio | No (vale el ZIP) |
| [Python](https://www.python.org) 3.10+ | `server.py` (chat en local) y `scripts/csv_a_sql.py` | No |
| [Node.js](https://nodejs.org) 18+ | Servidor de desarrollo y build con Vite | No |
| [CLI de Supabase](https://supabase.com/docs/guides/cli) | Publicar la función del chat | Solo si despliegas la función a mano |

---

## 3. Instalación

```bash
git clone https://github.com/sergiofernandezmtnez/little_pretty_engineers_hackfinance.git
cd little_pretty_engineers_hackfinance
```

Si has descargado el **ZIP** (*Code → Download ZIP*), descomprímelo y entra en la carpeta.

**`index.html` no necesita instalar nada.** Las dependencias solo hacen falta para las partes opcionales:

```bash
# Chat con Claude en local (server.py)
python -m pip install -r ordenador/requirements.txt

# Servidor de desarrollo / build con Vite
npm install
```

---

## 4. Configuración

> **Si solo quieres probarlo, no tienes que configurar nada:** `index.html` ya apunta al proyecto de Supabase del equipo (cuentas, grupos, catálogo y chat con IA incluidos). Esta sección es para montar una instancia propia.

### 4.1 Base de datos (Supabase)
1. Crea un proyecto en [supabase.com](https://supabase.com).
2. En **SQL Editor**, ejecuta **por este orden** (cada archivo: pegar y pulsar *Run*):
   `sql/schema.sql` → `sql/migracion.sql` → `sql/retos.sql` → `sql/amigos.sql` → `sql/becas_ayudas.sql` → **`sql/seguridad.sql`**
3. Ejecuta `sql/verificar_seguridad.sql`: **todas las filas deben decir `OK`**.
4. En *Project Settings → API*, copia la **Project URL** y la clave **anon / publishable**, y pégalas en `index.html`, en la línea que empieza por `var SB_URL=`:
   ```js
   var SB_URL='https://TU-PROYECTO.supabase.co',SB_KEY='TU_CLAVE_PUBLISHABLE'
   ```
   Esa clave es pública por diseño: la seguridad la dan las reglas RLS. **Nunca** pegues la clave `service_role`.
5. En *Authentication → Providers → Email*, desactiva **Confirm email** si quieres entrar sin confirmar el correo durante la demo (en producción, déjalo activado).

Los scripts `seguridad.sql` y `becas_ayudas.sql` se pueden repetir cuantas veces haga falta. Si ya tenías la base creada con una versión anterior, ejecuta `sql/migracion.sql` y vuelve a pasar `retos.sql`, `amigos.sql`, `becas_ayudas.sql` y `seguridad.sql`.

### 4.2 Clave de Claude
La clave **nunca** va en el navegador ni en el repositorio.
```bash
cp .env.example .env        # en Windows (Git Bash) también vale
# edita .env y rellena:  ANTHROPIC_API_KEY=sk-ant-...
```
`.env` está en `.gitignore`. Variables opcionales (ver `.env.example`): `CLAUDE_MODEL`, `CLAUDE_MODERATION_MODEL`.

### 4.3 Función del chat (Edge Function de Supabase)
Es el puente seguro entre la app y la API de Claude (`supabase/functions/chat`). Solo responde a usuarios con sesión iniciada.
```bash
supabase link --project-ref TU_REF
supabase secrets set --env-file .env
supabase functions deploy chat --no-verify-jwt
```
(La función comprueba por sí misma que quien escribe tiene la sesión iniciada, por eso se publica con `--no-verify-jwt`.)

**Publicación automática (opcional):** el repositorio incluye dos workflows de GitHub Actions. `deploy-web.yml` publica la web en GitHub Pages en cada push a `main`. `deploy-function.yml` vuelve a publicar las funciones `chat` y `tts` cuando cambia `supabase/functions/**` y necesita el secreto `SUPABASE_ACCESS_TOKEN` en *Settings → Secrets and variables → Actions*; edita en ese archivo el `PROJECT_REF` para que apunte a tu proyecto.

### 4.4 Voz del asistente (ElevenLabs)
Las respuestas del asistente se pueden escuchar con una **voz generada por IA**, de hombre o de mujer (se elige en la barra de voz del asistente). La voz de hombre es un **clon de la voz de Adri** (Adrián González, del equipo) y la de mujer, un **clon de la voz de Clara**. Las dos se crearon con *Instant Voice Clone* de ElevenLabs y con el consentimiento de ambos. La función `supabase/functions/tts` hace de puente: comprueba la sesión, limita el uso y llama a ElevenLabs. La clave y los IDs de las voces **nunca** llegan al navegador: este solo dice «hombre» o «mujer».

1. En [elevenlabs.io](https://elevenlabs.io), crea una clave de API en <https://elevenlabs.io/app/settings/api-keys> (si te deja, limítala a texto a voz y ponle un tope de créditos) y copia el **ID de cada voz** (en *Voices*, abre la voz y copia su ID).
2. Guárdalos como secretos de Supabase y publica la función:
   ```bash
   supabase secrets set ELEVENLABS_API_KEY=tu_clave ELEVENLABS_VOICE_ID=id_voz_hombre ELEVENLABS_VOICE_ID_MUJER=id_voz_mujer
   supabase functions deploy tts --no-verify-jwt
   ```
   También se pueden poner a mano en el panel de Supabase (*Edge Functions → Secrets*). Si los tienes en `.env`, vale `supabase secrets set --env-file .env`, pero solo con todos los valores rellenos. Para usar la voz con `server.py`, basta con tenerlos en `.env` (ver `.env.example`). Si falta `ELEVENLABS_VOICE_ID_MUJER`, la opción «Mujer» usa la voz del navegador.
3. Opcional: `ELEVENLABS_MODEL` (por defecto `eleven_flash_v2_5`, el de menor latencia; `eleven_multilingual_v2` suena algo mejor pero tarda más) y los ajustes de voz `ELEVENLABS_STABILITY` (0,5) y `ELEVENLABS_SIMILARITY_BOOST` (0,75), entre 0 y 1.

**Consumo:** cada audio gasta créditos de ElevenLabs según su número de caracteres. Para ahorrar, la app recorta cada respuesta a unos 600 caracteres y guarda en memoria los últimos 20 audios, y la función admite como mucho 20 audios cada 10 minutos por usuario. Si la voz de IA falla (sin créditos, sin red, límite superado o más de 15 s de espera), la app lee la respuesta con la voz del navegador y lo indica.

### 4.5 Catálogo de becas y ayudas (CSV → Supabase)
Los datos viven en **`datos/becas_y_ayudas.csv`** (columnas: `id, titulo, organismo, categoria, cuantia_maxima, requisitos, plazo, estado, ambito, enlace_oficial`). `estado` solo admite `Abierta`, `Próximamente`, `Permanente` o `Cerrada`, y los enlaces deben empezar por `https://`.

Para añadir o cambiar ayudas:
1. Edita el CSV (Excel vale: guarda como *CSV UTF-8*).
2. Ejecuta `python scripts/csv_a_sql.py`. Valida el CSV (indica la fila y el motivo si algo falla) y reescribe solo el bloque de datos de `sql/becas_ayudas.sql`.
3. Pega `sql/becas_ayudas.sql` en Supabase (*SQL Editor → Run*). Actualiza lo que cambie y borra lo que ya no esté en el CSV.

Plazos y cuantías son orientativos: verifícalos siempre en la convocatoria oficial.

---

## 5. Ejecución

**Opción A: abrir la web (la más sencilla).** Abre `index.html` en el navegador, o mejor, sírvelo en local:
```bash
python -m http.server 8000
# abre http://localhost:8000
```

**Opción B: servidor de desarrollo con Vite.**
```bash
npm run dev      # abre la URL que muestra (normalmente http://localhost:5173)
```

**Opción C: chat con IA ejecutándose en tu ordenador** (en lugar de las Edge Functions). Necesita `ANTHROPIC_API_KEY` en `.env` y, para la voz, `ELEVENLABS_API_KEY` y `ELEVENLABS_VOICE_ID`:
```bash
python server.py     # escucha en http://127.0.0.1:5000/chat y http://127.0.0.1:5000/tts
```
Al abrir la app desde `localhost` o `file://`, el asistente y la voz prueban primero ese servidor y, si no está, usan las funciones de Supabase. Sigue siendo necesario iniciar sesión.

**Opción D: versión publicada.** <https://studentia-eta.vercel.app> (se despliega sola con cada push a `main`).

---

## 6. Prueba

### 6.1 Prueba rápida, sin cuenta (2 minutos)
1. Abre la app (Ejecución, opción A o D).
2. Pulsa **Ver con un perfil de ejemplo**. Aparece el aviso "Estás viendo un perfil de ejemplo".
3. En **Inicio** comprueba que ves tu presupuesto del mes y cuánto puedes gastar hoy.
4. Recorre las pestañas (Ayudas, Calendario, Retos, Grupos, Mensajes, Emancipación, Planes, Asistente, Intereses): cada una debe cargar sin pantalla en blanco.
5. En **Asistente**, escribe una pregunta: sin sesión responde el asistente básico por reglas. El botón **🔊 Escuchar** no aparece: un aviso explica que la voz necesita iniciar sesión.
6. Al final de la página, pulsa **Borrar mis datos** para volver a empezar.

### 6.2 Prueba con cuenta (nube)
1. En la pantalla de inicio, escribe un email y una contraseña (mínimo 6 caracteres) y pulsa **Crear cuenta**. Completa el perfil.
2. **Grupos:** crea un grupo, añade un gasto y comprueba que se calculan los saldos.
3. En otro navegador, o en una ventana de incógnito, crea una **segunda cuenta**, ve a **Grupos** y únete con el código de invitación del grupo (10 caracteres). Debe ver el grupo y sus saldos.
4. **Aislamiento:** la segunda cuenta **no** debe ver el perfil, los gastos ni otros grupos de la primera.
5. **Ayudas → Catálogo oficial:** con sesión iniciada aparece el listado (hay una ayuda por cada fila del CSV, 14 ahora) con filtro por estado y enlace a la convocatoria. Sin sesión pide iniciar sesión.
6. **Asistente:** con sesión, pregunta algo como "¿puedo permitirme salir a cenar hoy?". Responde Claude usando tu presupuesto.
7. **Voz:** en esa respuesta, pulsa **🔊 Escuchar**. El botón pasa a «Generando voz…», empieza a sonar, cambia a «Detener» y aparece la etiqueta «Voz generada por IA». Pulsa otra vez para pararlo. Cambia entre **Hombre** y **Mujer** y vuelve a escucharla: cambia la voz. Después activa «Leer en voz alta las respuestas nuevas» y haz otra pregunta: la respuesta se lee sola (con la lectura automática, la IA contesta con frases cortas, pensadas para oírse). Si la voz de IA no está disponible, se oye la voz del navegador con el aviso «Voz del navegador».
8. **Mensajes:** envía un recordatorio de dinero a un amigo. Un mensaje irrespetuoso o ajeno al dinero debe rechazarse.

### 6.3 Pruebas técnicas
| Comprobación | Cómo | Resultado esperado |
|---|---|---|
| Seguridad de la base de datos | Ejecutar `sql/verificar_seguridad.sql` en el SQL Editor | Todas las filas con `OK` |
| Datos del catálogo | `python scripts/csv_a_sql.py` | `OK: 14 ayudas volcadas en sql/becas_ayudas.sql` (o el error con la fila exacta) |
| Compilación | `npm install && npm run build` | Termina sin errores y crea `dist/index.html` |
| Repetir los SQL | Volver a ejecutar `seguridad.sql` o `becas_ayudas.sql` | Sin errores y sin datos duplicados |
| Voz: texto que se lee en alto | `python -m http.server 8000` y abrir `http://localhost:8000/scripts/test_voz.html` | `OK: 29 pruebas superadas` |
| Voz: ruta `/tts` de `server.py` | `python scripts/test_tts_server.py` (sin red ni claves: Supabase y ElevenLabs simulados) | `Ran 12 tests` … `OK` |
| Voz: función `tts` publicada | `curl` de abajo con un token de sesión | Se guarda `prueba.mp3` y se oye; sin token, error 401 |

Para el `curl`, entra en la app y copia tu token de sesión desde la consola del navegador (F12): `JSON.parse(localStorage.getItem('sb-TU_REF-auth-token')).access_token`. `SB_KEY` es la clave *publishable* de `index.html`.
```bash
curl -X POST "https://TU_REF.supabase.co/functions/v1/tts" \
  -H "Authorization: Bearer $TOKEN" -H "apikey: $SB_KEY" -H "Content-Type: application/json" \
  -d '{"text":"Hola, soy la voz de Studentia."}' --output prueba.mp3
```

### 6.4 Problemas frecuentes
- **El asistente dice "no hay servidor de IA":** no está desplegada la función `chat` ni arrancado `server.py`, o falta `ANTHROPIC_API_KEY` (ver 4.2 y 4.3).
- **El catálogo no aparece o da "permission denied":** falta ejecutar `sql/becas_ayudas.sql` o volver a pasar `sql/seguridad.sql`.
- **No entra con el email recién creado:** si *Confirm email* está activado, confirma primero el correo.
- **Pantalla en blanco al abrir `index.html`:** sírvelo con `python -m http.server 8000` y recarga con Ctrl+F5.
- **Vercel falla con `vite: Permission denied`:** la carpeta `node_modules` no debe estar en el repositorio (está en `.gitignore`).
- **No aparece el botón 🔊 Escuchar:** la voz necesita la sesión iniciada.
- **Se oye la voz del navegador (aviso «Voz del navegador»):** la voz de IA no está disponible. Falta publicar la función `tts` o poner los secretos `ELEVENLABS_*` (ver 4.4), la cuenta de ElevenLabs no tiene créditos (en los logs de la función aparece `quota_exceeded`), se ha pasado el límite de 20 audios cada 10 minutos o ElevenLabs ha tardado más de 15 s.
- **En los logs sale `missing_permissions` (falta el permiso `text_to_speech`):** la clave de ElevenLabs está limitada y no tiene permiso de texto a voz. Edítala en <https://elevenlabs.io/app/settings/api-keys> y activa *Text to Speech*, o crea otra con ese permiso. Si cambias de clave, actualiza el secreto o reinicia `server.py`.
- **En los logs sale `api_key_id_used_as_api_key`:** has pegado el *ID* de la clave, no la clave. Las claves empiezan por `sk_` y ElevenLabs solo las enseña al crearlas o regenerarlas: crea otra (con permiso de texto a voz) y cópiala en ese momento.
- **«Este navegador no tiene ninguna voz en español»:** instala una voz en español en el sistema (Windows: *Configuración → Hora e idioma → Voz*; macOS: *Accesibilidad → Contenido leído*) o usa otro navegador.
- **En el móvil sale «Toca para escuchar»:** Safari (iOS) bloquea el audio que no sale de un toque. Pulsa el botón y sonará.

### 6.5 Medición del impacto de la voz
Con la sesión iniciada, `window.__voz()` en la consola del navegador devuelve contadores sin datos personales: reproducciones, tiempo desde el clic hasta el primer audio (mediana y p90), % de veces que se usó la voz del navegador y uso de la caché. `window.__voz.reset()` los pone a cero. El protocolo del mini-test de usabilidad (5 personas, 3 tareas con y sin voz) y las tablas para apuntar los resultados están en [`docs/medicion-voz.md`](docs/medicion-voz.md).

---

## 7. Seguridad

- **Aislamiento por usuario (RLS):** cada persona solo ve sus filas y las de los grupos o retos a los que pertenece.
- **Mínimo privilegio:** el rol `authenticated` solo tiene SELECT/INSERT/UPDATE/DELETE donde la app lo necesita (sin TRUNCATE) y `anon` (sin sesión) no tiene acceso a ninguna tabla ni función.
- **Entrada a grupos y retos solo con código** de 10 caracteres aleatorios. Un miembro no puede añadir a otros usuarios con cuenta ni expulsarlos.
- **Integridad:** el pagador de un gasto y su reparto deben ser del mismo grupo; hay límites de longitud para evitar basura.
- **Catálogo de becas:** solo lectura y solo con sesión; nadie puede modificarlo desde la app o la API.
- **Secretos:** la clave de Claude vive solo como secreto de la Edge Function (o en `.env`, ignorado por Git). No subas nunca un `.env` real.
- **Voz (ElevenLabs):** la clave y los IDs de las voces solo viven en el servidor (secretos de la función `tts` o `.env`); el navegador solo envía «hombre» o «mujer». La función exige sesión, solo admite `{ text, voz }` con un texto de hasta 700 caracteres y limita a 20 audios cada 10 minutos por usuario. Solo se envía el texto de la respuesta del asistente, nunca tu perfil ni tus mensajes, y la app lo avisa junto al control.
- **Regla de oro:** toda tabla nueva necesita RLS y una política (`enable row level security` + `create policy`) antes de usarse.

---

## 8. Estructura del repositorio

```
index.html                  La aplicación completa (HTML + CSS + JS, sin compilar)
server.py                   Servidor local opcional para el chat con Claude
ordenador/requirements.txt  Dependencias de server.py
supabase/functions/chat/    Edge Function del asistente (la clave de Claude vive solo aquí)
supabase/functions/tts/     Edge Function de la voz (la clave de ElevenLabs vive solo aquí)
sql/                        Esquema, retos, amigos, catálogo de becas y seguridad (+ verificador)
datos/becas_y_ayudas.csv    Fuente de datos del catálogo de becas
scripts/csv_a_sql.py        Convierte el CSV en SQL para Supabase
scripts/test_voz.html       Pruebas del texto que se lee en voz alta (textoParaVoz)
scripts/test_tts_server.py  Pruebas de la ruta /tts de server.py (sin red ni claves)
docs/medicion-voz.md        Protocolo y tablas para medir el impacto de la voz
.github/workflows/          Publicación automática de la web y de la función
.env.example                Plantilla de variables de entorno (sin secretos)
package.json                Vite (opcional): servidor de desarrollo y build
main.js, supabaseClient.js  Restos de una versión anterior; index.html no los usa
```

## Estado
Prototipo de hackathon. Ayudas, cuantías y plazos son orientativos: verifícalos antes de presentarlos como datos oficiales.
