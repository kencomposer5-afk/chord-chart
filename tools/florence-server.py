#!/usr/bin/env python3
"""Florence-2 (Microsoft, MIT licence) chord reader for the chord-chart app.

Runs on your own computer and answers the app on http://localhost:8765 :
    GET  /ping            -> {"ok": true, "model": ..., "device": ...}
    POST /ocr  {"image": "data:image/png;base64,..."}  -> {"text": "Cm G7"}
The app sends one bar at a time. Nothing leaves your computer
(the model itself is downloaded once from Hugging Face, ~0.5 GB).

Setup / start (macOS):  bash florence-setup.sh   then   bash florence-start.sh
"""
import base64, io, json, os, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
import torch
from PIL import Image
from transformers import AutoProcessor, Florence2ForConditionalGeneration

MODEL = os.environ.get("FLORENCE_MODEL", "florence-community/Florence-2-base")
PORT = int(os.environ.get("FLORENCE_PORT", "8765"))
DEVICE = "mps" if torch.backends.mps.is_available() else ("cuda" if torch.cuda.is_available() else "cpu")

print(f"loading {MODEL} on {DEVICE} ...", flush=True)
processor = AutoProcessor.from_pretrained(MODEL)
model = Florence2ForConditionalGeneration.from_pretrained(MODEL, dtype=torch.float32).to(DEVICE).eval()
lock = threading.Lock()          # one generation at a time


def read(image: Image.Image) -> str:
    inputs = processor(text="<OCR>", images=image.convert("RGB"), return_tensors="pt")
    with lock, torch.no_grad():
        ids = model.generate(
            input_ids=inputs["input_ids"].to(DEVICE),
            pixel_values=inputs["pixel_values"].to(DEVICE),
            max_new_tokens=32,
            num_beams=3,
        )
    return processor.batch_decode(ids, skip_special_tokens=True)[0].strip()


class Handler(BaseHTTPRequestHandler):
    def _headers(self, code=200, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Private-Network", "true")   # lets the https page reach localhost
        self.end_headers()

    def do_OPTIONS(self):
        self._headers(204)

    def do_GET(self):
        if self.path.startswith("/ping"):
            self._headers()
            self.wfile.write(json.dumps({"ok": True, "model": MODEL, "device": DEVICE}).encode())
        else:
            self._headers(404)

    def do_POST(self):
        if not self.path.startswith("/ocr"):
            self._headers(404)
            return
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
            data = body["image"].split(",", 1)[-1]
            text = read(Image.open(io.BytesIO(base64.b64decode(data))))
            self._headers()
            self.wfile.write(json.dumps({"text": text}).encode())
        except Exception as e:  # report instead of crashing
            self._headers(500)
            self.wfile.write(json.dumps({"error": str(e)}).encode())

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    print(f"ready: http://localhost:{PORT}  (leave this window open while you use the app)", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
