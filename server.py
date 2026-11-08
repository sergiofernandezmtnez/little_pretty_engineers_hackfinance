import os
from dotenv import load_dotenv
from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
import anthropic

load_dotenv()  # lee el archivo .env

app = Flask(__name__)
CORS(app)

client = anthropic.Anthropic()  # usa ANTHROPIC_API_KEY automáticamente


@app.route("/")
def home():
    return send_from_directory(".", "index.html")


@app.route("/api/chat", methods=["POST"])
def chat():
    datos = request.get_json()
    mensaje = datos.get("mensaje", "")

    if not mensaje:
        return jsonify({"error": "Mensaje vacío"}), 400

    try:
        respuesta = client.messages.create(
            model="claude-sonnet-5-5",
            max_tokens=1000,
            messages=[{"role": "user", "content": mensaje}],
        )
        return jsonify({"respuesta": respuesta.content[0].text})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(debug=True, port=5000)
