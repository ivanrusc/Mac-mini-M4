#!/bin/zsh
# =============================================================================
# install.sh — Instal·lació automàtica de Piper TTS per OpenClaw
# Mac mini M4 · macOS · ARM64
# =============================================================================
# Ús:
#   chmod +x install.sh
#   ./install.sh
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

echo ""
echo "=================================================="
echo "  Piper TTS Local per OpenClaw — Mac mini M4"
echo "=================================================="
echo ""

# -----------------------------------------------------------------------------
# 1. Dependències
# -----------------------------------------------------------------------------
log "Comprovant Homebrew..."
command -v brew >/dev/null 2>&1 || err "Homebrew no trobat. Instal·la'l a https://brew.sh"

log "Instal·lant dependències (python, ffmpeg, jq)..."
brew install python ffmpeg jq 2>/dev/null || true

# -----------------------------------------------------------------------------
# 2. Estructura de carpetes
# -----------------------------------------------------------------------------
log "Creant estructura de carpetes..."
mkdir -p ~/.openclaw/tools/piper/voices
mkdir -p ~/.openclaw/bin
mkdir -p ~/.openclaw/logs
mkdir -p ~/.openclaw/venvs

# -----------------------------------------------------------------------------
# 3. Entorn Python
# -----------------------------------------------------------------------------
log "Creant entorn virtual Python per Piper..."
python3 -m venv ~/.openclaw/venvs/piper
source ~/.openclaw/venvs/piper/bin/activate

pip install --upgrade pip wheel -q
pip install piper-tts fastapi uvicorn pydantic -q

log "Piper instal·lat correctament."

# -----------------------------------------------------------------------------
# 4. Descarregar veus catalanes
# -----------------------------------------------------------------------------
log "Descarregant veus catalanes de Hugging Face..."
cd ~/.openclaw/tools/piper/voices

BASE="https://huggingface.co/rhasspy/piper-voices/resolve/main"

# Veu ONA — femenina, millor qualitat (RECOMANADA)
if [ ! -f "ca_ES-upc_ona-medium.onnx" ]; then
    log "Descarregant ca_ES-upc_ona-medium..."
    curl -L -# -o ca_ES-upc_ona-medium.onnx \
        "$BASE/ca/ca_ES/upc_ona/medium/ca_ES-upc_ona-medium.onnx"
    curl -L -# -o ca_ES-upc_ona-medium.onnx.json \
        "$BASE/ca/ca_ES/upc_ona/medium/ca_ES-upc_ona-medium.onnx.json"
else
    warn "ca_ES-upc_ona-medium ja existeix, saltant..."
fi

# Veu PAU — masculina, lleugera
if [ ! -f "ca_ES-upc_pau-x_low.onnx" ]; then
    log "Descarregant ca_ES-upc_pau-x_low..."
    curl -L -# -o ca_ES-upc_pau-x_low.onnx \
        "$BASE/ca/ca_ES/upc_pau/x_low/ca_ES-upc_pau-x_low.onnx"
    curl -L -# -o ca_ES-upc_pau-x_low.onnx.json \
        "$BASE/ca/ca_ES/upc_pau/x_low/ca_ES-upc_pau-x_low.onnx.json"
else
    warn "ca_ES-upc_pau-x_low ja existeix, saltant..."
fi

# -----------------------------------------------------------------------------
# 5. Còpia del servidor API
# -----------------------------------------------------------------------------
log "Instal·lant servidor Piper TTS API..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/scripts/piper_openai_tts_api.py" ~/.openclaw/bin/

# -----------------------------------------------------------------------------
# 6. Prova ràpida de Piper
# -----------------------------------------------------------------------------
log "Provant Piper..."
~/.openclaw/venvs/piper/bin/python -m piper \
    --data-dir "$HOME/.openclaw/tools/piper/voices" \
    -m ca_ES-upc_ona-medium \
    -f /tmp/piper-install-test.wav \
    -- "Instal·lació completada. Piper funciona correctament en català." \
    && afplay /tmp/piper-install-test.wav \
    && log "Piper genera àudio correctament." \
    || warn "Piper no ha pogut generar àudio. Comprova els logs."

# -----------------------------------------------------------------------------
# 7. LaunchAgent
# -----------------------------------------------------------------------------
log "Instal·lant LaunchAgent..."

# Substituïm /Users/ivan pel home real de l'usuari
sed "s|/Users/ivan|$HOME|g" \
    "$SCRIPT_DIR/launchd/com.openclaw.piper-tts-api.plist" \
    > "$HOME/Library/LaunchAgents/com.openclaw.piper-tts-api.plist"

launchctl bootout gui/$(id -u) \
    "$HOME/Library/LaunchAgents/com.openclaw.piper-tts-api.plist" 2>/dev/null || true

launchctl bootstrap gui/$(id -u) \
    "$HOME/Library/LaunchAgents/com.openclaw.piper-tts-api.plist"

launchctl enable gui/$(id -u)/com.openclaw.piper-tts-api
launchctl kickstart -k gui/$(id -u)/com.openclaw.piper-tts-api

sleep 3

# -----------------------------------------------------------------------------
# 8. Prova de l'API
# -----------------------------------------------------------------------------
log "Provant API..."
HEALTH=$(curl -s http://127.0.0.1:8765/health 2>/dev/null || echo "")

if echo "$HEALTH" | grep -q '"ok":true'; then
    log "API funcionant correctament a http://127.0.0.1:8765"
else
    warn "L'API no respon encara. Comprova els logs:"
    warn "  tail -f ~/.openclaw/logs/piper-tts-api.err.log"
fi

# -----------------------------------------------------------------------------
# 9. Configurar OpenClaw
# -----------------------------------------------------------------------------
log "Configurant OpenClaw..."

OPENCLAW_JSON="$HOME/.openclaw/openclaw.json"

if [ ! -f "$OPENCLAW_JSON" ]; then
    warn "No s'ha trobat ~/.openclaw/openclaw.json — configura OpenClaw manualment (veure README)."
else
    cp "$OPENCLAW_JSON" "${OPENCLAW_JSON}.bak.$(date +%F_%H-%M)"

    python3 - <<'PY'
import json
from pathlib import Path

p = Path.home() / ".openclaw/openclaw.json"
cfg = json.loads(p.read_text())

messages = cfg.setdefault("messages", {})
tts = messages.setdefault("tts", {})

tts["auto"]          = "inbound"
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

# Desactivar Bonjour si causa problemes
plugins = cfg.setdefault("plugins", {})
entries = plugins.setdefault("entries", {})
# No el desactivem per defecte — només si hi ha problemes

p.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")
print("openclaw.json actualitzat.")
PY

    log "Reiniciant OpenClaw gateway..."
    openclaw gateway restart 2>/dev/null || warn "No s'ha pogut reiniciar OpenClaw automàticament. Fes-ho manualment."
fi

# -----------------------------------------------------------------------------
# Resum
# -----------------------------------------------------------------------------
echo ""
echo "=================================================="
echo "  Instal·lació completada!"
echo "=================================================="
echo ""
echo "  API Piper TTS:  http://127.0.0.1:8765"
echo "  Veu per defecte: ca_ES-upc_ona-medium (Ona, femenina)"
echo "  Logs:           ~/.openclaw/logs/piper-tts-api.err.log"
echo ""
echo "  Prova des de Telegram: envia una nota de veu al bot"
echo ""
echo "  Per canviar a veu masculina (Pau):"
echo "    openclaw config set messages.tts.providers.openai.voice pau"
echo ""
