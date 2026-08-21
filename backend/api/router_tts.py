from __future__ import annotations

import base64
import logging
from typing import TYPE_CHECKING

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import Response

from ..models import BatchRequest, BatchResponse, BatchResult, TTSRequest

if TYPE_CHECKING:
    from ..tts_manager import TTSManager

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1", tags=["tts"])


def _tts(request: Request) -> TTSManager:
    return request.app.state.tts


@router.post("/tts", response_class=Response)
def synthesize(req: TTSRequest, request: Request):
    manager = _tts(request)
    try:
        wav_bytes, duration_ms = manager.synthesize(
            text=req.text, lang=req.lang, voice=req.voice, steps=req.steps, speed=req.speed
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return Response(
        content=wav_bytes,
        media_type="audio/wav",
        headers={"X-Duration-Ms": str(duration_ms), "Cache-Control": "no-store"},
    )


@router.post("/tts/batch", response_model=BatchResponse)
def synthesize_batch(req: BatchRequest, request: Request):
    manager = _tts(request)
    defaults = req.defaults or {}
    results: list[BatchResult] = []
    try:
        for item in req.items:
            steps = int(defaults.get("steps", 8))
            wav_bytes, duration_ms = manager.synthesize(
                text=item.text,
                lang=item.lang,
                voice=item.voice,
                steps=steps,
                speed=item.speed,
            )
            results.append(
                BatchResult(
                    wav_base64=base64.b64encode(wav_bytes).decode("ascii"), duration_ms=duration_ms
                )
            )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return BatchResponse(results=results)
