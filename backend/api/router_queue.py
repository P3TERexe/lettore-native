from __future__ import annotations

from typing import TYPE_CHECKING

from fastapi import APIRouter, HTTPException, Request

from ..models import AppConfig, QueueAddRequest, QueueAddResponse, QueueState
from ..textnorm import TextNormalizer

if TYPE_CHECKING:
    from ..queue_manager import QueueManager

router = APIRouter(prefix="/v1/queue", tags=["queue"])


def _queue(request: Request) -> QueueManager:
    return request.app.state.queue


@router.post("", response_model=QueueAddResponse)
def enqueue(req: QueueAddRequest, request: Request):
    runtime_cfg: AppConfig | None = getattr(request.app.state, "runtime_config", None)
    exclusions = (
        req.text_exclusions
        if req.text_exclusions
        else (runtime_cfg.text_exclusions if runtime_cfg else [])
    )
    normalize_enabled = (
        req.normalize_text
        if req.normalize_text is not None
        else (runtime_cfg.normalize_text if runtime_cfg else True)
    )

    clean_text = TextNormalizer.normalize(
        text=req.text,
        lang=req.lang,
        enabled=normalize_enabled,
        exclusions=exclusions,
    )
    if not clean_text:
        raise HTTPException(status_code=422, detail="testo vuoto dopo il parsing o le esclusioni")

    ids = _queue(request).add(
        text=clean_text,
        lang=req.lang,
        voice=req.voice,
        steps=req.steps,
        speed=req.speed,
        split_paragraphs=req.split_paragraphs,
    )
    if not ids:
        raise HTTPException(status_code=422, detail="testo vuoto dopo il parsing")
    return QueueAddResponse(job_ids=ids, split_into=len(ids))


@router.get("", response_model=QueueState)
def get_queue(request: Request):
    return _queue(request).snapshot()


@router.delete("", response_model=QueueState)
def clear_queue(request: Request):
    queue = _queue(request)
    queue.clear()
    return queue.snapshot()


@router.post("/play", response_model=QueueState)
def play(request: Request):
    queue = _queue(request)
    queue.play()
    return queue.snapshot()


@router.post("/pause", response_model=QueueState)
def pause(request: Request):
    queue = _queue(request)
    queue.pause()
    return queue.snapshot()


@router.post("/stop", response_model=QueueState)
def stop(request: Request):
    queue = _queue(request)
    queue.stop()
    return queue.snapshot()


@router.post("/current/done", response_model=QueueState)
def current_done(request: Request):
    queue = _queue(request)
    queue.done()
    return queue.snapshot()


@router.delete("/{job_id}", response_model=QueueState)
def remove_job(job_id: str, request: Request):
    queue = _queue(request)
    if not queue.remove(job_id):
        raise HTTPException(status_code=404, detail="job non trovato")
    return queue.snapshot()
