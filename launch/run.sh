#!/usr/bin/env bash
# Sets up Paradox on Mac or Linux the first time, then starts it.
#   launch/run.sh           a conversation in the terminal
#   launch/run.sh --brain   the brain in your browser
# Everything it downloads (a private Python, the libraries, the judging models) stays inside this folder,
# so deleting the folder removes all of it.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

BRAIN=0
if [ "${1:-}" = "--brain" ]; then BRAIN=1; shift; fi

# Which compiled build fits this machine.
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64)              PLAT=macos-arm64 ;;
  Darwin-x86_64)             PLAT=macos-x64 ;;
  Linux-x86_64)              PLAT=linux-x64 ;;
  *) echo "Sorry, there is no Paradox build for $(uname -s) on $(uname -m) yet."; exit 1 ;;
esac
if ! ls "bin/$PLAT"/paradox.* >/dev/null 2>&1; then echo "The build for $PLAT is missing from bin/$PLAT."; exit 1; fi

# macOS marks downloaded files as untrusted and refuses to load the compiled files; clear that for this folder only.
if [ "$(uname -s)" = "Darwin" ]; then xattr -dr com.apple.quarantine "$ROOT" 2>/dev/null || true; fi

# Settings from .env (the same file Paradox itself reads).
if [ -f .env ]; then
  while IFS='=' read -r k v; do
    case "$k" in PARADOX_LLM_URL|PARADOX_LLM_MODEL) [ -z "${!k:-}" ] && export "$k=$(echo "$v" | sed -e 's/^ *//' -e 's/ *$//' -e "s/^[\"']//" -e "s/[\"']$//")" ;; esac
  done < <(grep -E '^\s*PARADOX_LLM_(URL|MODEL)\s*=' .env | sed 's/^ *//; s/ *= */=/')
fi
URL="${PARADOX_LLM_URL:-http://localhost:11434/v1}"
MODEL="${PARADOX_LLM_MODEL:-qwen2.5:7b-instruct}"

case "$URL" in
  *localhost:11434*|*127.0.0.1:11434*)
    if ! command -v ollama >/dev/null 2>&1; then
      echo "Paradox is set to use Ollama (a free local model), but Ollama isn't installed."
      if [ "$(uname -s)" = "Darwin" ]; then echo "Install it from https://ollama.com/download, open it once, then start Paradox again."
      else echo "Install it with:  curl -fsSL https://ollama.com/install.sh | sh   then start Paradox again."; fi
      echo "Or use an API key instead: copy .env.example to .env and fill in one block."
      exit 1
    fi
    if ! curl -s -m 3 http://localhost:11434/api/tags >/dev/null; then (ollama serve >/dev/null 2>&1 &); sleep 5; fi
    ollama pull "$MODEL" ;;
  *) echo "Using $MODEL at $URL (from .env), so no local model is downloaded." ;;
esac

# A private Python 3.12 and its libraries, set up once by uv, all inside .tools and .venv.
export UV_INSTALL_DIR="$ROOT/.tools/uv" UV_PYTHON_INSTALL_DIR="$ROOT/.tools/python" UV_CACHE_DIR="$ROOT/.tools/cache" UV_NO_MODIFY_PATH=1
UV="$UV_INSTALL_DIR/uv"
if [ ! -x "$UV" ]; then
  echo "Getting uv (sets up Python for Paradox)..."
  curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null
fi
if [ -d .venv ] && [ ! -x .venv/bin/python ]; then rm -rf .venv; fi   # a half-made one from a failed run
if [ ! -x .venv/bin/python ]; then
  echo "Setting up Python 3.12 and the libraries (first run only)..."
  "$UV" venv --python 3.12 .venv -q
  if [ "$(uname -s)" = "Darwin" ]; then "$UV" pip install --python .venv/bin/python -q torch
  else "$UV" pip install --python .venv/bin/python -q torch --index-url https://download.pytorch.org/whl/cpu; fi
  "$UV" pip install --python .venv/bin/python -q -r requirements.txt
fi

export PYTHONPATH="$ROOT/bin/$PLAT" PYTHONIOENCODING=utf-8
export HF_HOME="$ROOT/models" PARADOX_HOME="$ROOT/data" PARADOX_UI="$ROOT/ui/dist/index.html"
if [ "$BRAIN" = 1 ]; then
  echo "Starting the brain at http://localhost:8100 (close this window to stop)"
  ( sleep 6; if command -v open >/dev/null; then open http://localhost:8100; elif command -v xdg-open >/dev/null; then xdg-open http://localhost:8100 >/dev/null 2>&1; fi ) &
  exec .venv/bin/python -m uvicorn paradox.api:app --port 8100
else
  exec .venv/bin/python launch/paradox_cli.py --trace "$@"
fi
