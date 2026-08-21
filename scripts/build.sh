#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=========================================="
echo " 🔨 Build Pipeline: Lettore Native (Tauri 2)"
echo "=========================================="

echo "==> 1/3 Compilazione Frontend (Vite)..."
cd "$ROOT_DIR/ui"
npm run build
cd "$ROOT_DIR"

echo "==> 2/3 Verifica Sidecar Binaries..."
# Se Python ha PyInstaller e le dipendenze, compila il sidecar
if command -v python3 &>/dev/null; then
    python3 "$ROOT_DIR/scripts/build_sidecar.py" || echo "[i] Skip build sidecar avanzato (verrà usato sidecar dev)"
fi

echo "==> 3/3 Compilazione Release Tauri Desktop..."
cd "$ROOT_DIR/src-tauri"
cargo build --release
cd "$ROOT_DIR"

echo "=========================================="
echo " [✓] Build completata con successo!"
echo " Eseguibile: src-tauri/target/release/lettore"
echo "=========================================="
