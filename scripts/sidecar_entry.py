"""Entrypoint del sidecar PyInstaller.

main.py usa import relativi, quindi non può essere l'entry diretto di
PyInstaller (verrebbe eseguito come modulo top-level senza package).
Questo wrapper importa backend.main come pacchetto e avvia uvicorn con
host/port da BackendConfig (env LETTORE_HOST / LETTORE_PORT).
"""

import uvicorn

from backend.main import app

if __name__ == "__main__":
    cfg = app.state.config
    uvicorn.run(app, host=cfg.host, port=cfg.port, log_level="info")
