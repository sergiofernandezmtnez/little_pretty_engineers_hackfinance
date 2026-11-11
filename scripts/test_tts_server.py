"""Pruebas de la ruta /tts de server.py, sin red ni claves reales (Supabase Auth y ElevenLabs simulados).

Uso (con las dependencias de ordenador/requirements.txt instaladas):
    python scripts/test_tts_server.py
"""
import io
import json
import os
import sys
import unittest
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import dotenv  # noqa: E402

dotenv.load_dotenv = lambda *a, **k: False  # no leer el .env real: estas pruebas no usan claves de verdad
os.environ["ANTHROPIC_API_KEY"] = "clave-falsa-de-prueba"  # server.py crea el cliente de Claude al importarse
VARIABLES = ("ELEVENLABS_API_KEY", "ELEVENLABS_VOICE_ID", "ELEVENLABS_MODEL", "ELEVENLABS_STABILITY", "ELEVENLABS_SIMILARITY_BOOST")
for _v in VARIABLES:
    os.environ.pop(_v, None)

import server  # noqa: E402

MP3 = b"ID3\x03\x00\x00\x00\x00\x00\x00" + b"\xff\xfb\x90\x00" * 400  # basta con que parezca un mp3
VOZ = "voz-de-prueba-123"


class UrlopenFalso:
    """Sustituye a urllib.request.urlopen: simula Supabase Auth y ElevenLabs y guarda lo que se le pide a ElevenLabs."""

    def __init__(self):
        self.modo = "ok"
        self.peticiones = []

    def __call__(self, req, timeout=None):
        url = req.full_url
        if "/auth/v1/user" in url:
            if req.get_header("Authorization") == "Bearer bueno":
                return io.BytesIO(json.dumps({"id": "usuario-1"}).encode())
            raise urllib.error.HTTPError(url, 401, "Unauthorized", {}, io.BytesIO(b"{}"))
        self.peticiones.append(req)
        if self.modo == "sin_creditos":
            detalle = {"detail": {"status": "quota_exceeded", "message": f"Quota exceeded (voice {VOZ})"}}
            raise urllib.error.HTTPError(url, 401, "Unauthorized", {}, io.BytesIO(json.dumps(detalle).encode()))
        if self.modo == "caido":
            raise urllib.error.URLError("timed out")
        return io.BytesIO(MP3)


class PruebasTTS(unittest.TestCase):
    def setUp(self):
        self.falso = UrlopenFalso()
        self.original = urllib.request.urlopen
        urllib.request.urlopen = self.falso
        server._hits_tts.clear()
        os.environ["ELEVENLABS_API_KEY"] = "clave-falsa"
        os.environ["ELEVENLABS_VOICE_ID"] = VOZ
        self.cliente = server.app.test_client()

    def tearDown(self):
        urllib.request.urlopen = self.original
        for v in VARIABLES:
            os.environ.pop(v, None)

    def pedir(self, cuerpo=None, token="bueno", crudo=None):
        cab = {"Authorization": f"Bearer {token}"} if token else {}
        if crudo is not None:
            return self.cliente.post("/tts", data=crudo, headers=cab, content_type="application/json")
        return self.cliente.post("/tts", json=cuerpo, headers=cab)

    def test_sin_sesion_o_token_malo_401_sin_llamar_a_elevenlabs(self):
        self.assertEqual(self.pedir({"text": "hola"}, token=None).status_code, 401)
        self.assertEqual(self.pedir({"text": "hola"}, token="malo").status_code, 401)
        self.assertEqual(self.falso.peticiones, [])

    def test_cuerpos_no_validos_400(self):
        for crudo in ("no es json", "[]", "{}", '{"text": 5}', '{"text": "hola", "extra": 1}', '{"text": "   "}'):
            with self.subTest(crudo=crudo):
                r = self.pedir(crudo=crudo)
                self.assertEqual(r.status_code, 400)
                self.assertIn("error", r.get_json())
        self.assertEqual(self.falso.peticiones, [])

    def test_tope_de_700_caracteres(self):
        r = self.pedir({"text": "a" * 701})
        self.assertEqual(r.status_code, 400)
        self.assertIn("700", r.get_json()["error"])
        self.assertEqual(self.pedir({"text": "a" * 700}).status_code, 200)

    def test_devuelve_el_audio_y_llama_bien_a_elevenlabs(self):
        r = self.pedir({"text": "  Hoy puedes gastar doce euros.  "})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.mimetype, "audio/mpeg")
        self.assertEqual(r.headers.get("Cache-Control"), "no-store")
        self.assertEqual(r.get_data(), MP3)
        req = self.falso.peticiones[0]
        self.assertEqual(req.get_method(), "POST")
        self.assertEqual(req.full_url, f"https://api.elevenlabs.io/v1/text-to-speech/{VOZ}?output_format=mp3_44100_128")
        self.assertEqual(req.get_header("Xi-api-key"), "clave-falsa")
        cuerpo = json.loads(req.data)
        self.assertEqual(cuerpo["text"], "Hoy puedes gastar doce euros.")
        self.assertEqual(cuerpo["model_id"], "eleven_flash_v2_5")
        self.assertEqual(cuerpo["language_code"], "es")
        self.assertEqual(cuerpo["voice_settings"], {"stability": 0.5, "similarity_boost": 0.75})

    def test_modelo_y_ajustes_configurables(self):
        os.environ.update(ELEVENLABS_MODEL="eleven_multilingual_v2", ELEVENLABS_STABILITY="0.3", ELEVENLABS_SIMILARITY_BOOST="7")
        self.assertEqual(self.pedir({"text": "hola"}).status_code, 200)
        cuerpo = json.loads(self.falso.peticiones[0].data)
        self.assertEqual(cuerpo["model_id"], "eleven_multilingual_v2")
        self.assertNotIn("language_code", cuerpo)  # multilingual_v2 no lo admite
        self.assertEqual(cuerpo["voice_settings"], {"stability": 0.3, "similarity_boost": 0.75})  # 7 está fuera de 0..1

    def test_sin_creditos_502_generico_y_log_sin_id_de_voz(self):
        self.falso.modo = "sin_creditos"
        with self.assertLogs(server.app.logger, level="ERROR") as log:
            r = self.pedir({"text": "hola"})
        self.assertEqual(r.status_code, 502)
        self.assertEqual(r.get_json(), {"error": server.TTS_NO_DISPONIBLE})
        texto_log = "\n".join(log.output)
        self.assertIn("quota_exceeded", texto_log)
        self.assertNotIn(VOZ, texto_log)

    def test_elevenlabs_caido_502(self):
        self.falso.modo = "caido"
        with self.assertLogs(server.app.logger, level="ERROR"):
            r = self.pedir({"text": "hola"})
        self.assertEqual(r.status_code, 502)

    def test_faltan_secretos_502_sin_llamar(self):
        os.environ.pop("ELEVENLABS_VOICE_ID")
        with self.assertLogs(server.app.logger, level="ERROR"):
            r = self.pedir({"text": "hola"})
        self.assertEqual(r.status_code, 502)
        self.assertEqual(self.falso.peticiones, [])

    def test_limite_de_20_audios_por_usuario_429(self):
        for _ in range(3):  # las peticiones no válidas no gastan cupo
            self.pedir({"text": ""})
        for i in range(20):
            self.assertEqual(self.pedir({"text": f"audio {i}"}).status_code, 200)
        r = self.pedir({"text": "uno más"})
        self.assertEqual(r.status_code, 429)
        self.assertEqual(len(self.falso.peticiones), 20)

    def test_el_limite_del_chat_sigue_en_30(self):
        server._hits.pop("prueba-chat", None)
        self.assertFalse(any(server.limitado("prueba-chat") for _ in range(30)))
        self.assertTrue(server.limitado("prueba-chat"))
        server._hits.pop("prueba-chat", None)


if __name__ == "__main__":
    unittest.main(verbosity=2)
