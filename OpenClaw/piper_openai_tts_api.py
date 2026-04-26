"""
piper_openai_tts_api.py
=======================
API local compatible amb OpenAI TTS que crida Piper per generar àudio en català.

Usat per OpenClaw com a proveïdor TTS local.
Endpoint: POST /v1/audio/speech

Autor: Ivan (Mac mini M4)
"""

import os
import subprocess
import tempfile
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel


APP_NAME = "OpenClaw Piper Local TTS API"

PIPER_PY = os.environ.get("PIPER_PY", str(Path.home() / ".openclaw/venvs/piper/bin/python"))
VOICE_DIR = os.environ.get("PIPER_VOICE_DIR", str(Path.home() / ".openclaw/tools/piper/voices"))
DEFAULT_VOICE = os.environ.get("PIPER_DEFAULT_VOICE", "ca_ES-upc_ona-medium")

# Àlies de veus: noms curts + noms típics d'OpenAI
VOICE_ALIASES = {
    "ona":     "ca_ES-upc_ona-medium",   # femenina, millor qualitat
    "pau":     "ca_ES-upc_pau-x_low",    # masculina, lleugera
    "ca":      "ca_ES-upc_ona-medium",
    "catala":  "ca_ES-upc_ona-medium",
    "catalan": "ca_ES-upc_ona-medium",
    # Noms OpenAI estàndard → redirigim a veus catalanes
    "alloy":   "ca_ES-upc_ona-medium",
    "verse":   "ca_ES-upc_ona-medium",
    "nova":    "ca_ES-upc_ona-medium",
    "shimmer": "ca_ES-upc_ona-medium",
    "echo":    "ca_ES-upc_pau-x_low",
}


class SpeechRequest(BaseModel):
    model: Optional[str] = "tts-1"
    input: str
    voice: Optional[str] = None
    response_format: Optional[str] = "mp3"
    speed: Optional[float] = 1.0


app = FastAPI(title=APP_NAME)


@app.get("/health")
def health():
    return {
        "ok": True,
        "service": APP_NAME,
        "voice_dir": VOICE_DIR,
        "default_voice": DEFAULT_VOICE,
    }


@app.post("/v1/audio/speech")
def audio_speech(req: SpeechRequest):
    text = (req.input or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="Missing input text")

    if len(text) > 4000:
        raise HTTPException(status_code=413, detail="Input text too long (max 4000 chars)")

    # Resolem la veu: àlies → nom real → fallback a DEFAULT_VOICE
    requested = (req.voice or DEFAULT_VOICE).strip()
    voice = VOICE_ALIASES.get(requested, requested)

    model_file  = Path(VOICE_DIR) / f"{voice}.onnx"
    config_file = Path(VOICE_DIR) / f"{voice}.onnx.json"
    if not model_file.exists() or not config_file.exists():
        voice = DEFAULT_VOICE  # fallback automàtic

    fmt = (req.response_format or "mp3").lower()
    if fmt in ("ogg", "opus"):
        final_ext  = "ogg"
        media_type = "audio/ogg"
    elif fmt == "wav":
        final_ext  = "wav"
        media_type = "audio/wav"
    else:
        final_ext  = "mp3"
        media_type = "audio/mpeg"

    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir_path = Path(tmpdir)
        wav_path    = tmpdir_path / "speech.wav"
        out_path    = tmpdir_path / f"speech.{final_ext}"

        # Cridem Piper
        piper_cmd = [
            PIPER_PY, "-m", "piper",
            "--data-dir", VOICE_DIR,
            "-m", voice,
            "-f", str(wav_path),
            "--", text,
        ]

        try:
            subprocess.run(
                piper_cmd,
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=90,
            )
        except subprocess.CalledProcessError as e:
            raise HTTPException(status_code=500, detail=f"Piper error: {e.stderr}")
        except subprocess.TimeoutExpired:
            raise HTTPException(status_code=504, detail="Piper timeout")

        if final_ext == "wav":
            data = wav_path.read_bytes()
            return Response(content=data, media_type=media_type)

        # Convertim WAV → MP3 o OGG amb ffmpeg
        if final_ext == "ogg":
            ffmpeg_cmd = [
                "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                "-i", str(wav_path),
                "-ac", "1", "-ar", "48000", "-c:a", "libopus", "-b:a", "64k",
                str(out_path),
            ]
        else:
            ffmpeg_cmd = [
                "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                "-i", str(wav_path),
                "-ac", "1", "-ar", "44100", "-codec:a", "libmp3lame", "-b:a", "128k",
                str(out_path),
            ]

        try:
            subprocess.run(
                ffmpeg_cmd,
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=60,
            )
        except subprocess.CalledProcessError as e:
            raise HTTPException(status_code=500, detail=f"ffmpeg error: {e.stderr}")

        data = out_path.read_bytes()
        return Response(content=data, media_type=media_type)
