"""Endpoint di configurazione runtime (default usati dall'UI)."""

from fastapi import APIRouter, Request

from ..models import AppConfig

router = APIRouter(prefix="/v1/config", tags=["config"])


@router.get("", response_model=AppConfig)
def get_config(request: Request):
    return request.app.state.runtime_config


@router.put("", response_model=AppConfig)
def set_config(cfg: AppConfig, request: Request):
    request.app.state.runtime_config = cfg
    if cfg.capture_auto:
        request.app.state.capture.start_watcher(request.app.state.capture_callback)
    else:
        request.app.state.capture.stop_watcher()
    return cfg
