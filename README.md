# Piper TTS Local per OpenClaw — Mac mini M4

TTS (Text-to-Speech) **100% local** en **català** per a OpenClaw + Ollama + Telegram.  
Sense núvol. Sense cost per crida. Tot corre al Mac mini M4.

---

## Flux complet

```
Telegram (nota de veu)
    ↓
OpenClaw rep l'àudio
    ↓
Whisper (STT) → transcripció en català
    ↓
Ollama (LLM) → genera resposta en text
    ↓
API local 127.0.0.1:8765  ←── aquest repositori
    ↓
Piper (TTS) → àudio en català
    ↓
Telegram rep la resposta en àudio
```

**Per què una API local?** OpenClaw no suporta Piper directament. Els proveïdors oficials són OpenAI, ElevenLabs, Microsoft i MiniMax. La solució és crear una API local compatible amb el format OpenAI TTS i apuntar OpenClaw cap a ella.

---

## Requisits previs

| Requisit | Versió |
|---|---|
| macOS | ARM64 (M1/M2/M3/M4) |
| Homebrew | qualsevol |
| Python | 3.9+ |
| OpenClaw | instal·lat i funcionant |
| Ollama | instal·lat i funcionant |
| ffmpeg | instal·lat via Homebrew |

---

## Instal·lació ràpida

```bash
git clone https://github.com/EL-TEU-USUARI/piper-tts-openclaw.git
cd piper-tts-openclaw
chmod +x install.sh
./install.sh
```

El script fa tot automàticament:
- Instal·la dependències (Python venv, piper-tts, fastapi, uvicorn)
- Descarrega les veus catalanes de Hugging Face
- Instal·la i arrenca el servei com a LaunchAgent (s'inicia sol en cada reinici)
- Configura OpenClaw per usar Piper com a TTS

---

## Instal·lació manual pas a pas

### Pas 1 — Dependències

```bash
brew install python ffmpeg jq
```

Crea les carpetes:

```bash
mkdir -p ~/.openclaw/tools/piper/voices
mkdir -p ~/.openclaw/bin
mkdir -p ~/.openclaw/logs
mkdir -p ~/.openclaw/venvs
```

Entorn Python:

```bash
python3 -m venv ~/.openclaw/venvs/piper
source ~/.openclaw/venvs/piper/bin/activate
pip install --upgrade pip wheel
pip install piper-tts fastapi uvicorn pydantic
```

Comprova:

```bash
~/.openclaw/venvs/piper/bin/python -m piper --help
```

---

### Pas 2 — Veus catalanes

Hi ha tres veus disponibles:

| Nom | Gènere | Qualitat | Mida |
|---|---|---|---|
| `ca_ES-upc_ona-medium` | Femenina | ⭐⭐⭐ **Recomanada** | ~60 MB |
| `ca_ES-upc_ona-x_low` | Femenina | ⭐⭐ | ~10 MB |
| `ca_ES-upc_pau-x_low` | Masculina | ⭐⭐ | ~10 MB |

Font: [rhasspy/piper-voices a Hugging Face](https://huggingface.co/rhasspy/piper-voices/tree/main/ca/ca_ES)

```bash
cd ~/.openclaw/tools/piper/voices

BASE="https://huggingface.co/rhasspy/piper-voices/resolve/main"

# Veu ONA — femenina, millor qualitat (RECOMANADA)
curl -L -o ca_ES-upc_ona-medium.onnx \
  "$BASE/ca/ca_ES/upc_ona/medium/ca_ES-upc_ona-medium.onnx"

curl -L -o ca_ES-upc_ona-medium.onnx.json \
  "$BASE/ca/ca_ES/upc_ona/medium/ca_ES-upc_ona-medium.onnx.json"

# Veu PAU — masculina, lleugera (opcional)
curl -L -o ca_ES-upc_pau-x_low.onnx \
  "$BASE/ca/ca_ES/upc_pau/x_low/ca_ES-upc_pau-x_low.onnx"

curl -L -o ca_ES-upc_pau-x_low.onnx.json \
  "$BASE/ca/ca_ES/upc_pau/x_low/ca_ES-upc_pau-x_low.onnx.json"
```

Comprova:

```bash
ls -lh ~/.openclaw/tools/piper/voices
```

---

### Pas 3 — Prova Piper manualment

```bash
~/.openclaw/venvs/piper/bin/python -m piper \
  --data-dir "$HOME/.openclaw/tools/piper/voices" \
  -m ca_ES-upc_ona-medium \
  -f /tmp/prova-piper-ca.wav \
  -- "Bon dia. Aquesta és una prova de veu catalana amb Piper al Mac mini M4."

afplay /tmp/prova-piper-ca.wav
```

Si sents la veu en català → Piper funciona ✅

---

### Pas 4 — Instal·lar el servidor API

```bash
cp scripts/piper_openai_tts_api.py ~/.openclaw/bin/
```

Prova manual (en un terminal):

```bash
~/.openclaw/venvs/piper/bin/python -m uvicorn \
  piper_openai_tts_api:app \
  --app-dir "$HOME/.openclaw/bin" \
  --host 127.0.0.1 \
  --port 8765
```

En un altre terminal:

```bash
# Comprova que respon
curl -s http://127.0.0.1:8765/health | jq

# Genera un MP3 de prova
curl -s -X POST "http://127.0.0.1:8765/v1/audio/speech" \
  -H "Content-Type: application/json" \
  -d '{"input":"Bon dia. Piper local funciona correctament.","voice":"ona","response_format":"mp3"}' \
  -o /tmp/test.mp3 && afplay /tmp/test.mp3
```

Atura el servidor manual amb `CTRL+C`.

---

### Pas 5 — Servei automàtic (LaunchAgent)

El servei s'arrancarà sol cada cop que engeguis el Mac.

Copia el plist i substitueix `/Users/ivan` pel teu home:

```bash
sed "s|/Users/ivan|$HOME|g" \
  launchd/com.openclaw.piper-tts-api.plist \
  > "$HOME/Library/LaunchAgents/com.openclaw.piper-tts-api.plist"
```

Carrega i arrenca:

```bash
launchctl bootout gui/$(id -u) \
  "$HOME/Library/LaunchAgents/com.openclaw.piper-tts-api.plist" 2>/dev/null || true

launchctl bootstrap gui/$(id -u) \
  "$HOME/Library/LaunchAgents/com.openclaw.piper-tts-api.plist"

launchctl enable gui/$(id -u)/com.openclaw.piper-tts-api
launchctl kickstart -k gui/$(id -u)/com.openclaw.piper-tts-api

sleep 3
curl -s http://127.0.0.1:8765/health | jq
```

---

### Pas 6 — ⚠️ Comprovar `settings/tts.json`

OpenClaw pot tenir preferències locals que sobreescriuen `openclaw.json`:

```bash
ls -l ~/.openclaw/settings/tts.json
```

Si existeix i causa problemes:

```bash
mv ~/.openclaw/settings/tts.json ~/.openclaw/settings/tts.json.bak.$(date +%F_%H-%M)
```

---

### Pas 7 — Configurar OpenClaw

Còpia de seguretat primer:

```bash
cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak.$(date +%F_%H-%M)
```

Aplica la configuració TTS:

```bash
python3 - <<'PY'
import json
from pathlib import Path

p = Path.home() / ".openclaw/openclaw.json"
cfg = json.loads(p.read_text())

messages = cfg.setdefault("messages", {})
tts = messages.setdefault("tts", {})

tts["auto"]          = "inbound"   # àudio només si tu has enviat àudio
tts["provider"]      = "openai"
tts["timeoutMs"]     = 60000
tts["maxTextLength"] = 2000

providers = tts.setdefault("providers", {})
providers["openai"] = {
    "apiKey":  "local-piper",
    "baseUrl": "http://127.0.0.1:8765/v1",
    "model":   "tts-1",
    "voice":   "ona"
}
providers["microsoft"] = {"enabled": False}

p.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")
print("Configuració aplicada.")
PY
```

Comprova:

```bash
jq '.messages.tts' ~/.openclaw/openclaw.json
```

### Opcions del mode `auto`

| Valor | Comportament |
|---|---|
| `"inbound"` | Respon amb àudio **només** si tu has enviat un àudio ✅ Recomanat |
| `"always"` | Sempre respon amb àudio |
| `"tagged"` | Només quan ho demanis explícitament |
| `"off"` | TTS desactivat |

---

### Pas 8 — Reiniciar OpenClaw

```bash
openclaw gateway restart
sleep 5
openclaw status
```

---

### Pas 9 — Prova final

Des de Telegram, envia una nota de veu al bot en català. El flux esperat:

1. Tu envies àudio
2. Whisper transcriu a text
3. Ollama genera la resposta
4. OpenClaw envia el text a `http://127.0.0.1:8765/v1/audio/speech`
5. Piper genera l'àudio localment
6. Telegram rep l'àudio en català ✅

---

## Canviar la veu

**Veu femenina Ona** (per defecte, millor qualitat):

```bash
python3 -c "
import json; from pathlib import Path
p = Path.home() / '.openclaw/openclaw.json'
cfg = json.loads(p.read_text())
cfg['messages']['tts']['providers']['openai']['voice'] = 'ona'
p.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + '\n')
"
openclaw gateway restart
```

**Veu masculina Pau**:

```bash
python3 -c "
import json; from pathlib import Path
p = Path.home() / '.openclaw/openclaw.json'
cfg = json.loads(p.read_text())
cfg['messages']['tts']['providers']['openai']['voice'] = 'pau'
p.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + '\n')
"
openclaw gateway restart
```

---

## Gestió del servei Piper

```bash
# Estat
launchctl print gui/$(id -u)/com.openclaw.piper-tts-api

# Reiniciar
launchctl kickstart -k gui/$(id -u)/com.openclaw.piper-tts-api

# Aturar
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.openclaw.piper-tts-api.plist

# Tornar a activar
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.openclaw.piper-tts-api.plist
launchctl kickstart -k gui/$(id -u)/com.openclaw.piper-tts-api

# Logs
tail -f ~/.openclaw/logs/piper-tts-api.out.log
tail -f ~/.openclaw/logs/piper-tts-api.err.log
```

---

## Diagnòstic

### L'API no respon

```bash
curl -v http://127.0.0.1:8765/health
launchctl kickstart -k gui/$(id -u)/com.openclaw.piper-tts-api
tail -50 ~/.openclaw/logs/piper-tts-api.err.log
```

### Error `ffmpeg not found`

El servei launchd no troba ffmpeg. El plist ja inclou el PATH correcte (`/opt/homebrew/bin`).  
Si ffmpeg és en un altre lloc: `which ffmpeg` i actualitza el plist.

### Error `Piper error` o àudio buit

```bash
# Prova Piper directament
~/.openclaw/venvs/piper/bin/python -m piper \
  --data-dir "$HOME/.openclaw/tools/piper/voices" \
  -m ca_ES-upc_ona-medium \
  -f /tmp/test.wav \
  -- "prova" && afplay /tmp/test.wav
```

### Prova l'endpoint directament

```bash
curl -s -X POST "http://127.0.0.1:8765/v1/audio/speech" \
  -H "Content-Type: application/json" \
  -d '{"input":"Prova ràpida.","voice":"ona","response_format":"mp3"}' \
  -o /tmp/test.mp3 && afplay /tmp/test.mp3
```

### OpenClaw continua usant altra veu

```bash
# Comprova si hi ha preferències locals
cat ~/.openclaw/settings/tts.json 2>/dev/null || echo "no existeix"

# Si cal, elimina-les
mv ~/.openclaw/settings/tts.json ~/.openclaw/settings/tts.json.bak
openclaw gateway restart
```

### Bonjour causa crashes del gateway

Si veus `CIAO PROBING CANCELLED` als logs del gateway:

```bash
# Neteja cache mDNS
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder

# Desactiva Bonjour (si el problema persisteix)
python3 - <<'PY'
import json; from pathlib import Path
p = Path.home() / ".openclaw/openclaw.json"
cfg = json.loads(p.read_text())
cfg.setdefault("plugins", {}).setdefault("entries", {})["bonjour"] = {"enabled": False}
p.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")
PY

openclaw gateway restart
```

---

## Estructura del repositori

```
piper-tts-openclaw/
├── README.md                          ← aquest fitxer
├── install.sh                         ← instal·lació automàtica
├── scripts/
│   └── piper_openai_tts_api.py        ← servidor FastAPI (copia a ~/.openclaw/bin/)
├── launchd/
│   └── com.openclaw.piper-tts-api.plist  ← LaunchAgent macOS
└── docs/
    └── openclaw-tts-config.json       ← fragment de config openclaw.json
```

---

## Resum de la configuració final

```
STT entrada:   Whisper local (configurat per separat)
LLM:           Ollama local (qwen3.5 o similar)
TTS sortida:   Piper local — ca_ES-upc_ona-medium
API local:     http://127.0.0.1:8765/v1/audio/speech
OpenClaw TTS:  provider=openai, baseUrl=http://127.0.0.1:8765/v1, voice=ona
Mode:          inbound (àudio → àudio, text → text)
```

**Tot 100% local al Mac mini M4. Zero núvol. Zero cost per crida.**

---

## Fonts i referències

- [Piper TTS — GitHub](https://github.com/rhasspy/piper)
- [Piper TTS — PyPI](https://pypi.org/project/piper-tts/)
- [Veus catalanes Piper — Hugging Face](https://huggingface.co/rhasspy/piper-voices/tree/main/ca/ca_ES)
- [OpenClaw — Documentació TTS](https://docs.openclaw.ai/tools/tts)
- [OpenClaw — Documentació àudio](https://docs.openclaw.ai/nodes/audio)

---

## Llicència

MIT — fes-ne el que vulguis.
