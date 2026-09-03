"""Endpoint informativi: voci, lingue, stato."""

from fastapi import APIRouter, HTTPException, Request

from ..models import StatusResponse, VoiceList, VoiceUpdate

router = APIRouter(prefix="/v1", tags=["meta"])


@router.get("/voices", response_model=VoiceList)
def voices(request: Request):
    builtin_ids, custom_ids = request.app.state.tts.voices()
    builtin, custom = request.app.state.voices.catalog(builtin_ids, custom_ids)
    return VoiceList(builtin=builtin, custom=custom)


@router.put("/voices/{voice_id}")
def update_voice(voice_id: str, payload: VoiceUpdate, request: Request):
    entry = request.app.state.voices.update(voice_id, name=payload.name, langs=payload.langs)
    if entry is None:
        raise HTTPException(status_code=404, detail="voce non trovata")
    return entry


@router.get("/languages")
def languages(request: Request):
    return request.app.state.tts.languages()


@router.get("/status", response_model=StatusResponse)
def status(request: Request):
    tts = request.app.state.tts
    return StatusResponse(
        ready=tts.ready,
        model_loading=tts.loading,
        model=tts.model,
        sample_rate=tts.sample_rate,
        queue=request.app.state.queue.snapshot(),
    )
