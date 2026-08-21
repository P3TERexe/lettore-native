#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Avvio Lettore Native in modalità sviluppo..."
npx @tauri-apps/cli dev --config src-tauri/tauri.conf.json
