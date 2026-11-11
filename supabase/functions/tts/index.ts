// Edge Function "tts": convierte en voz (ElevenLabs) el texto de una respuesta del asistente.
// ELEVENLABS_API_KEY y ELEVENLABS_VOICE_ID viven solo aquí, como secretos de Supabase: nunca llegan al navegador.
// Solo recibe el texto de la respuesta ({ text }); nunca el perfil ni los mensajes del usuario.
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...CORS, "Content-Type": "application/json" } });

const MAX_CHARS = 700;          // tope duro del servidor (el navegador ya recorta a ~600)
const AUDIOS = 20;              // audios por usuario cada 10 minutos
const NO_DISPONIBLE = "La voz de IA no está disponible ahora.";

// Ajustes de voz entre 0 y 1. Por defecto, los de la documentación de ElevenLabs: stability 0.5, similarity_boost 0.75
function ajuste(nombre: string, defecto: number) {
  const v = Deno.env.get(nombre), n = Number(v);
  return v && n >= 0 && n <= 1 ? n : defecto;
}

const hits = new Map<string, number[]>();
function limited(id: string) {
  const now = Date.now(), win = (hits.get(id) ?? []).filter((t) => now - t < 600_000);
  win.push(now); hits.set(id, win);
  return win.length > AUDIOS;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Usa POST" }, 405);
  try {
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: { user } } = await sb.auth.getUser();
    if (!user) return json({ error: "Inicia sesión para escuchar las respuestas." }, 401);

    // El cuerpo tiene que ser exactamente { text: string }
    const body = await req.json().catch(() => null);
    const ok = body && typeof body === "object" && !Array.isArray(body) && Object.keys(body).length === 1 && typeof body.text === "string";
    if (!ok) return json({ error: "Petición no válida: se espera { text }." }, 400);
    const text = body.text.trim();
    if (!text) return json({ error: "No hay texto que leer." }, 400);
    if (text.length > MAX_CHARS) return json({ error: `El texto es demasiado largo (máximo ${MAX_CHARS} caracteres).` }, 400);
    if (limited(user.id)) return json({ error: "Has pedido muchos audios seguidos. Prueba en unos minutos." }, 429);

    const key = Deno.env.get("ELEVENLABS_API_KEY"), voice = Deno.env.get("ELEVENLABS_VOICE_ID");
    if (!key || !voice) { console.error("tts: faltan los secretos ELEVENLABS_API_KEY o ELEVENLABS_VOICE_ID"); return json({ error: NO_DISPONIBLE }, 502); }
    const model = Deno.env.get("ELEVENLABS_MODEL") || "eleven_flash_v2_5";

    let r: Response;
    try {
      r = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(voice)}?output_format=mp3_44100_128`, {
        method: "POST",
        headers: { "xi-api-key": key, "Content-Type": "application/json", Accept: "audio/mpeg" },
        body: JSON.stringify({
          text,
          model_id: model,
          // Fuerza el español; según la documentación, los modelos multilingual_v2 no admiten este parámetro
          ...(model.includes("multilingual_v2") ? {} : { language_code: "es" }),
          voice_settings: { stability: ajuste("ELEVENLABS_STABILITY", 0.5), similarity_boost: ajuste("ELEVENLABS_SIMILARITY_BOOST", 0.75) },
        }),
        signal: AbortSignal.timeout(12_000),   // el navegador se rinde a los 15 s y usa su propia voz
      });
    } catch (e) {
      console.error("ElevenLabs sin respuesta:", e instanceof Error ? e.name : "error");
      return json({ error: NO_DISPONIBLE }, 502);
    }
    if (!r.ok || !r.body) {
      // 401: clave inválida o sin créditos (quota_exceeded) · 429: límite de ElevenLabs · 422: petición rechazada.
      // El detalle solo va a los logs de Supabase (sin el ID de la voz); al navegador, un error genérico.
      const detalle = (await r.text().catch(() => "")).slice(0, 300).split(voice).join("[voice_id]");
      console.error("ElevenLabs:", r.status, detalle);
      return json({ error: NO_DISPONIBLE }, 502);
    }
    // El audio pasa al navegador según llega, sin esperar al archivo entero
    return new Response(r.body, { headers: { ...CORS, "Content-Type": "audio/mpeg", "Cache-Control": "no-store" } });
  } catch (e) {
    console.error("tts:", e);                       // el detalle queda en los logs de Supabase, no en la respuesta
    return json({ error: "Error interno de la voz." }, 500);
  }
});
