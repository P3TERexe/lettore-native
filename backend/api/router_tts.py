from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import Response

from ..audio_utils import concat_wav_bytes
from ..chunking import smart_chunk_text
from ..models import AppConfig, ExportRequest, TTSRequest
from ..textnorm import TextNormalizer

if TYPE_CHECKING:
    from ..tts_manager import TTSManager

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1", tags=["tts"])


def _tts(request: Request) -> TTSManager:
    return request.app.state.tts


PREVIEW_TEXT = "Ciao! Questa è un'anteprima vocale di Lettore."


@router.get("/tts/preview", response_class=Response)
def preview_voice(
    request: Request,
    voice: str = "M1",
    lang: str = "it",
):
    manager = _tts(request)
    try:
        wav_bytes, duration_ms = manager.synthesize(
            text=PREVIEW_TEXT, lang=lang, voice=voice, steps=5, speed=1.05
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


@router.post("/tts", response_class=Response)
def synthesize(req: TTSRequest, request: Request):
    manager = _tts(request)
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

    try:
        wav_bytes, duration_ms = manager.synthesize(
            text=clean_text, lang=req.lang, voice=req.voice, steps=req.steps, speed=req.speed
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
    runtime_cfg: AppConfig | None = getattr(request.app.state, "runtime_config", None)
    clean_text = TextNormalizer.normalize(
        text=req.text,
        lang=req.lang,
        enabled=True,
        exclusions=runtime_cfg.text_exclusions if runtime_cfg else [],
    )
    chunks = [c for c in smart_chunk_text(clean_text, lang=req.lang) if c]
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
