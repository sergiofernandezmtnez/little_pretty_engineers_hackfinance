# Medición del impacto de la voz del asistente

Este documento explica cómo medir si la voz del asistente mejora la usabilidad y la accesibilidad de STUD€NTIA, con datos reales que se puedan citar en el PDF y en la presentación.

> **Regla:** aquí solo van datos medidos. Mientras las tablas estén vacías, no hay resultados que citar.

## 1. Qué mide la app por sí sola

La app guarda unos contadores de uso de la voz en el estado del usuario (`S.voz.m`). **No guarda textos, audios ni datos personales**: solo números y tiempos. Se consultan desde la consola del navegador (F12) con la sesión iniciada:

```js
window.__voz()        // resumen de la medición
window.__voz.reset()  // pone los contadores a cero (antes de cada sesión de prueba)
```

| Campo | Qué significa |
|---|---|
| `intentos` | Veces que se ha pedido escuchar una respuesta (con el botón o con la lectura automática) |
| `reproducciones` | Veces que ha llegado a sonar algo (`voz_ia` + `voz_ia_desde_cache` + `voz_navegador`) |
| `voz_ia` | Audios generados por ElevenLabs |
| `voz_ia_desde_cache` | Audios de ElevenLabs repetidos desde la caché (sin red ni créditos) |
| `voz_navegador` | Veces que se usó la voz del navegador porque la voz de IA falló |
| `pct_voz_navegador` | % de reproducciones que fueron con la voz del navegador (fallback) |
| `pct_cache` | % de audios de IA servidos desde la caché |
| `sin_audio` | Intentos en los que no sonó nada (por ejemplo, no hay voz en español) |
| `bloqueos_autoplay` | Veces que el navegador bloqueó el audio y hubo que pulsar «Toca para escuchar» |
| `detenidas` / `completas` | Lecturas paradas a mano / escuchadas hasta el final |
| `automaticas` | Lecturas lanzadas por «Leer en voz alta las respuestas nuevas» |
| `latencia_ms` | Tiempo desde el clic (o desde que llega la respuesta, en lectura automática) hasta que empieza a sonar: número de muestras, mediana, percentil 90, mínimo y máximo (últimas 50 de cada tipo) |

Notas:
- El estado se sincroniza con el perfil del usuario en Supabase, así que los contadores son por cuenta.
- La latencia de `voz_navegador` incluye el tiempo perdido intentando la voz de IA (hasta 15 s si se agota el tiempo).

## 2. Mini-test de usabilidad (5 personas, unos 15 minutos cada una)

**Objetivo:** comparar el asistente **sin voz** (leer en pantalla) y **con voz** (lectura automática activada) en las mismas tareas.

**Preparación**
1. Una cuenta de prueba con el perfil de ejemplo y la sesión iniciada, en un móvil o portátil con altavoz o auriculares.
2. Consentimiento verbal de cada participante. No se graba la voz ni la cara y no se apuntan nombres: solo P1, P2…
3. `window.__voz.reset()` al empezar cada sesión. Al acabar, copia el resultado de `window.__voz()` en la tabla 3.4.
4. Para evitar el efecto aprendizaje, alterna el orden: P1, P3 y P5 empiezan **sin voz** (A→B) y P2 y P4 **con voz** (B→A). En cada condición, usa preguntas equivalentes con importes distintos.

**Tareas** (el participante pregunta al asistente y dice la respuesta en voz alta)
- **T1.** Averigua cuánto puedes gastar hoy.
- **T2.** Pregunta si puedes permitirte unas zapatillas de 35 € (con voz: 45 €) y di qué te recomienda.
- **T3.** Pregunta qué ayudas te corresponden y di el nombre de una.

**Qué se mide en cada tarea**
- **Tiempo (s):** desde que lee la tarjeta de la tarea hasta que dice la respuesta.
- **Errores:** respuesta incorrecta, ayuda del moderador o tarea abandonada.
- Al terminar cada condición, dos preguntas de 1 a 5:
  - **Satisfacción:** «¿Te ha resultado cómodo usar el asistente así?» (1 = nada, 5 = mucho)
  - **Accesibilidad:** «¿Te sería útil así si no pudieras mirar la pantalla (en el bus, andando, con la vista cansada o con baja visión)?» (1 = nada, 5 = mucho)
- Una pregunta abierta al final: «¿Qué cambiarías de la voz?»

## 3. Resultados (rellenar con datos reales)

### 3.1 Registro por tarea

| Participante | Orden | Condición | Tarea | Tiempo (s) | Errores | Notas |
|---|---|---|---|---|---|---|
| P1 | A→B | Sin voz | T1 | | | |
| P1 | A→B | Sin voz | T2 | | | |
| P1 | A→B | Sin voz | T3 | | | |
| P1 | A→B | Con voz | T1 | | | |
| P1 | A→B | Con voz | T2 | | | |
| P1 | A→B | Con voz | T3 | | | |
| P2 | B→A | Con voz | T1 | | | |
| P2 | B→A | Con voz | T2 | | | |
| P2 | B→A | Con voz | T3 | | | |
| P2 | B→A | Sin voz | T1 | | | |
| P2 | B→A | Sin voz | T2 | | | |
| P2 | B→A | Sin voz | T3 | | | |
| P3 | A→B | … | … | | | |
| P4 | B→A | … | … | | | |
| P5 | A→B | … | … | | | |

### 3.2 Valoraciones por participante

| Participante | Satisfacción sin voz (1-5) | Satisfacción con voz (1-5) | Accesibilidad sin voz (1-5) | Accesibilidad con voz (1-5) | Comentario |
|---|---|---|---|---|---|
| P1 | | | | | |
| P2 | | | | | |
| P3 | | | | | |
| P4 | | | | | |
| P5 | | | | | |

### 3.3 Resumen

| Métrica | Sin voz | Con voz | Diferencia |
|---|---|---|---|
| Tiempo medio por tarea (s) | | | |
| Errores totales | | | |
| Satisfacción media (1-5) | | | |
| Accesibilidad media (1-5) | | | |

### 3.4 Datos técnicos de `window.__voz()`

| Métrica | Valor |
|---|---|
| Reproducciones | |
| Latencia mediana de la voz de IA (ms) | |
| Latencia p90 de la voz de IA (ms) | |
| % con la voz del navegador (fallback) | |
| % servido desde la caché | |
| Bloqueos de autoplay | |

## 4. Cómo citarlo

Con 5 personas el resultado es **orientativo**, no estadísticamente significativo. Cítalo así: «En un test con 5 estudiantes, con la voz activada el tiempo medio por tarea pasó de X s a Y s y la valoración de accesibilidad de A a B (sobre 5)». Incluye la mediana de latencia de `window.__voz()` para respaldar los «tiempos de respuesta razonables».
