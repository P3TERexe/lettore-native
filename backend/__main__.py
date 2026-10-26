"""Entry point per `python -m backend`."""

from __future__ import annotations

import uvicorn

from .main import app

if __name__ == "__main__":
    cfg = app.state.config
    uvicorn.run(app, host=cfg.host, port=cfg.port, log_level="info")
