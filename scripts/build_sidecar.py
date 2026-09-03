#!/usr/bin/env python3
"""Compila il backend Python FastAPI in un eseguibile standalone (sidecar) per Tauri 2."""

import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BACKEND_DIR = ROOT / "backend"
TAURI_BIN_DIR = ROOT / "src-tauri" / "binaries"


def get_target_triple() -> str:
    machine = platform.machine().lower()
    if machine in ("arm64", "aarch64"):
        arch = "aarch64"
    elif machine in ("x86_64", "amd64"):
        arch = "x86_64"
    else:
        arch = machine

    system = platform.system().lower()
    if system == "darwin":
        return f"{arch}-apple-darwin"
    elif system == "windows":
        return f"{arch}-pc-windows-msvc"
    elif system == "linux":
        return f"{arch}-unknown-linux-gnu"
    else:
        return f"{arch}-unknown-{system}"


def build():
    triple = get_target_triple()
    out_name = f"lettore-backend-{triple}"
    TAURI_BIN_DIR.mkdir(parents=True, exist_ok=True)
    target_path = TAURI_BIN_DIR / out_name

    print(f"==> Compilazione sidecar per target: {triple}")

    # Verifica se PyInstaller è disponibile
    import importlib.util

    if importlib.util.find_spec("PyInstaller") is None:
        print("[!] PyInstaller non trovato nell'ambiente corrente. Installazione...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "pyinstaller"])

    cmd = [
        sys.executable,
        "-m",
        "PyInstaller",
        "--name",
        out_name,
        # onefile: l'eseguibile deve essere autonomo perché Tauri lo bundla
        # come externalBin singolo (onedir richiederebbe _internal/ accanto).
        "--onefile",
        "--noconfirm",
        "--clean",
        "--collect-all",
        "supertonic",
        # NOTA: niente --collect-all su onnxruntime — l'hook nativo di
        # PyInstaller basta e collect-all duplica il pacchetto, spezzando
        # l'identità della classe ort.InferenceSession (isinstance() fallisce).
        # Il pacchetto backend deve essere importabile nel bundle (import
        # risolti in fase di analisi), non copiato come dati.
        "--paths",
        str(ROOT),
        str(ROOT / "scripts" / "sidecar_entry.py"),
    ]

    print("==> Esecuzione PyInstaller:", " ".join(cmd))
    subprocess.check_call(cmd, cwd=ROOT)

    dist_bin = ROOT / "dist" / out_name
    if not dist_bin.exists() and sys.platform == "win32":
        dist_bin = ROOT / "dist" / f"{out_name}.exe"

    if dist_bin.exists():
        shutil.copy2(dist_bin, target_path)
        os.chmod(target_path, 0o755)
        print(f"[✓] Sidecar compilato con successo in: {target_path}")
        # Output transitorio di PyInstaller alla root del progetto.
        for tmp in (ROOT / "dist", ROOT / "build"):
            shutil.rmtree(tmp, ignore_errors=True)
    else:
        print(f"[!] File binario dist non trovato in {dist_bin}")


if __name__ == "__main__":
    build()
