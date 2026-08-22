#!/usr/bin/env bash
# Setup dev: venv Python + dipendenze backend + dipendenze UI.
# Uso: bash scripts/setup.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PYTHON="${LETTORE_PYTHON:-}"
if [[ -z "$PYTHON" ]]; then
  for c in python3.11 python3.12 python3.10 python3; do
    if command -v "$c" >/dev/null 2>&1; then PYTHON="$c"; break; fi
  done
fi
[[ -n "$PYTHON" ]] || { echo "Nessun Python trovato"; exit 1; }

echo "Python: $PYTHON"
VENV="$ROOT/.venv"
[[ -d "$VENV" ]] || "$PYTHON" -m venv "$VENV"

source "$VENV/bin/activate"
pip install --upgrade pip >/dev/null
pip install -r "$ROOT/backend/requirements.txt"

case "$(uname -s)" in
  Darwin) pip install -r "$ROOT/backend/requirements-macos.txt" ;;
  Linux)  pip install -r "$ROOT/backend/requirements-linux.txt" ;;
  MINGW*|MSYS*|CYGWIN*) pip install -r "$ROOT/backend/requirements-windows.txt" ;;
esac

echo "Backend: dipendenze installate."

if [[ -d "$ROOT/ui" ]]; then
  (cd "$ROOT/ui" && npm install)
  echo "UI: dipendenze installate."
fi

echo "Setup completato. Avvia con: npm run dev"
