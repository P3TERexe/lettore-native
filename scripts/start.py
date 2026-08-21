#!/usr/bin/env python3
"""Avvio dev: backend uvicorn + UI Electron, con gestione segnali.

Il backend viene spawnato se la porta non risponde già a /v1/status.
"""

import os
import shutil
import signal
import subprocess
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BACKEND_DIR = os.path.join(ROOT, "backend")
UI_DIR = os.path.join(ROOT, "ui")
PORT = int(os.getenv("LETTORE_PORT", "7788"))
BASE = f"http://127.0.0.1:{PORT}"

PYTHON_CANDIDATES = [
    os.getenv("LETTORE_PYTHON", ""),
    shutil.which("python3.11"),
    shutil.which("python3.12"),
    shutil.which("python3.10"),
    shutil.which("python3"),
    shutil.which("python"),
]


def find_python() -> str | None:
    for cand in PYTHON_CANDIDATES:
        if cand and os.path.exists(cand):
            return cand
    return None


def backend_alive() -> bool:
    try:
        with urllib.request.urlopen(f"{BASE}/v1/status", timeout=2) as resp:
            return resp.status == 200
    except Exception:  # noqa: BLE001
        return False


def main() -> int:
    procs: list[subprocess.Popen] = []

    def shutdown(*_args) -> None:
        print("Arresto in corso...")
        for p in procs:
            p.terminate()
        for p in procs:
            try:
                p.wait(timeout=8)
            except Exception:  # noqa: BLE001
                p.kill()
        sys.exit(0)

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    if not backend_alive():
        python = find_python()
        if python is None:
            print("Errore: nessun Python trovato. Imposta LETTORE_PYTHON.")
            return 1
        env = dict(os.environ, LETTORE_PORT=str(PORT))
        backend = subprocess.Popen(
            [python, "-m", "uvicorn", "backend.main:app", "--host", "127.0.0.1", "--port", str(PORT)],
            cwd=ROOT,
            env=env,
        )
        procs.append(backend)
        print(f"Backend avviato (pid {backend.pid}) su {BASE}...")
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            if backend_alive():
                break
            if backend.poll() is not None:
                print("Errore: il backend è uscito. Controlla l'installazione "
                      "(pip install -r backend/requirements.txt).")
                return 1
            time.sleep(0.5)
        if not backend_alive():
            print("Errore: timeout avvio backend.")
            return 1
        print("Backend pronto.")
    else:
        print(f"Backend già attivo su {BASE}, lo riuso.")

    if not os.path.isdir(os.path.join(UI_DIR, "node_modules")):
        print("node_modules mancante: esegui prima: cd ui && npm install")
        return 1

    ui = subprocess.Popen(["npm", "start"], cwd=UI_DIR)
    procs.append(ui)
    print("UI Electron avviata. Ctrl+C per uscire.")
    try:
        ui.wait()
    except KeyboardInterrupt:
        shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
