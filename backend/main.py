"""Entrypoint backend Lettore (FastAPI + uvicorn).

Avvio:  uvicorn main:app --host 127.0.0.1 --port 7788
        (oppure python -m main)
"""

import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .api import router_blocks, router_config, router_meta, router_queue, router_tts
from .config import BackendConfig
from .models import AppConfig
from .queue_manager import QueueManager
from .tts_manager import TTSManager
from .voices import VoiceRegistry

logging.basicConfig(
    level=os.getenv("LETTORE_LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


def create_app(config: BackendConfig | None = None) -> FastAPI:
    config = config or BackendConfig.from_env()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.tts.start()
        yield

    app = FastAPI(title="Lettore backend", version="0.1.0", lifespan=lifespan)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.state.config = config
    app.state.tts = TTSManager(
        model=config.model,
        auto_download=config.auto_download,
        engine=config.engine,
    )
    app.state.queue = QueueManager()
    app.state.voices = VoiceRegistry(config.config_dir)
    app.state.runtime_config = AppConfig()

    app.include_router(router_tts)
    app.include_router(router_queue)
    app.include_router(router_meta)
    app.include_router(router_config)
    app.include_router(router_blocks)
    return app


app = create_app()


if __name__ == "__main__":
    import uvicorn

    cfg = app.state.config
    uvicorn.run(app, host=cfg.host, port=cfg.port, log_level="info")
