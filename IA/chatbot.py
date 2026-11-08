import json
from anthropic import Anthropic
from dotenv import load_dotenv

load_dotenv()
client = Anthropic()
system = open("prompts/system.md", encoding="utf-8").read()
ctx = json.load(open("mock/contexto.json", encoding="utf-8"))

def responder(pregunta, tono="cercano"):
    msg = client.messages.create(
        model="claude-sonnet-5-5",
        max_tokens=500,
        system=f"{system}\n\nTono: {tono}\n\nContexto del usuario (JSON):\n{json.dumps(ctx, ensure_ascii=False)}",
        messages=[{"role": "user", "content": pregunta}],
    )
    return msg.content[0].text

if __name__ == "__main__":
    print(responder(input("Pregunta: ")))