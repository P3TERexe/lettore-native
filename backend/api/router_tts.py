from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import Response

from ..audio_utils import concat_wav_bytes
from ..chunking import smart_chunk_text
from ..models import ExportRequest, TTSRequest

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


@router.post("/tts/export", response_class=Response)
def synthesize_export(req: ExportRequest, request: Request):
    manager = _tts(request)
    chunks = [c for c in smart_chunk_text(req.text, lang=req.lang) if c]
    if not chunks:
        raise HTTPException(status_code=422, detail="testo vuoto dopo il parsing")
    try:
        parts = [
            manager.synthesize(
                text=c, lang=req.lang, voice=req.voice, steps=req.steps, speed=req.speed
            )[0]
            for c in chunks
        ]
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return Response(
        content=concat_wav_bytes(parts, manager.sample_rate),
        media_type="audio/wav",
        headers={
            "Content-Disposition": 'attachment; filename="lettore.wav"',
            "Cache-Control": "no-store",
        },
    )
