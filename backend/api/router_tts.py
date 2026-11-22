from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import Response
from supertonic.utils import chunk_text

from ..models import (
    NORMALIZED_TEXT_MAX_CHARS,
    REQUEST_TEXT_MAX_CHARS,
    AppConfig,
    TTSRequest,
    normalize_guard_lang,
    sentence_max_chars,
)
from ..textnorm import TextNormalizer

if TYPE_CHECKING:
    from ..tts_manager import TTSManager

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1", tags=["tts"])


def _tts(request: Request) -> TTSManager:
    return request.app.state.tts


PREVIEW_TEXT = "Ciao! Questa è un'anteprima vocale di Lettore."

UNAVAILABLE_DETAIL = "motore TTS non disponibile: riprova tra qualche istante"

# Valori che non indicano una lingua: `na` è il codice Auto pubblicato dal
# catalogo, `auto` il default della configurazione. Il guard li risolve con
# l'euristica del motore.
UNRESOLVED_GUARD_LANGS = frozenset({"", "auto", "na"})


def _guard_lang(manager: TTSManager, text: str, lang: str | None) -> str:
    """Lingua effettiva normalizzata per il guard.

    `lang` invariato viene solo normalizzato (trim, minuscole, `ko-KR` -> `ko`).
    `"auto"`, `"na"` e `None` non sono lingue: il guard riusa `resolve_lang`,
    la stessa euristica del motore, sul testo normalizzato. Il `lang` inviato
    a `synthesize` resta quello del client, quindi il manager rileva di nuovo:
    il secondo rilevamento è accettato per non cambiare l'API del manager.
    """
    code = normalize_guard_lang(lang)
    if code not in UNRESOLVED_GUARD_LANGS:
        return code
    return normalize_guard_lang(manager.resolve_lang(text, "auto"))


def _longest_chunk(text: str, max_len: int) -> int:
    """Lunghezza della frase più lunga che il guard deve valutare.

    Usa la stessa `chunk_text` del motore (stesse esclusioni per abbreviazioni
    e iniziali) con il `max_len` della lingua effettiva. Non replica il
    chunking reale del motore (300 per le lingue latine, 120 per il coreano):
    `chunk_text` non spezza una frase più lunga del limite, quindi il valore
    misurato è la frase più lunga del testo.
    """
    chunks = chunk_text(text, max_len=max_len)
    return max((len(chunk) for chunk in chunks), default=0)


def _normalized_text_error(text: str, lang: str) -> str | None:
    """Motivo del 422 se il testo normalizzato non è sicuro da sintetizzare.

    `lang` è la lingua effettiva già risolta e normalizzata (non `"auto"` né
    `"na"`, alias regione risolti). Non cita il testo dell'utente: il messaggio
    resta sintetico.
    """
    if len(text) > NORMALIZED_TEXT_MAX_CHARS:
        return (
            f"testo normalizzato troppo lungo ({len(text)} caratteri, "
            f"limite {NORMALIZED_TEXT_MAX_CHARS}): riduci o spezza il testo"
        )

    limit = sentence_max_chars(lang)
    longest = _longest_chunk(text, limit)
    if longest > limit:
        return (
            f"frase troppo lunga dopo la normalizzazione ({longest} caratteri, "
            f"limite {limit} per la lingua '{lang}'): "
            "aggiungi punteggiatura o spezza il testo"
        )
    return None


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
        logger.exception("Anteprima TTS non disponibile")
        raise HTTPException(status_code=503, detail=UNAVAILABLE_DETAIL) from exc
    return Response(
        content=wav_bytes,
        media_type="audio/wav",
        headers={"X-Duration-Ms": str(duration_ms), "Cache-Control": "no-store"},
    )


@router.post("/tts", response_class=Response)
def synthesize(req: TTSRequest, request: Request):
    manager = _tts(request)
    runtime_cfg: AppConfig = request.app.state.runtime_config

    # I campi omessi ereditano la configurazione runtime; i default del model
    # restano `None` proprio per distinguere "non inviato" da "inviato uguale
    # al default". Prima voice/speed/steps/normalize_text ignoravano il PUT.
    voice = req.voice if req.voice is not None else runtime_cfg.voice
    lang = req.lang if req.lang is not None else runtime_cfg.lang
    steps = req.steps if req.steps is not None else runtime_cfg.steps
    speed = req.speed if req.speed is not None else runtime_cfg.speed
    exclusions = req.text_exclusions or runtime_cfg.text_exclusions
    normalize_enabled = (
        req.normalize_text if req.normalize_text is not None else runtime_cfg.normalize_text
    )

    # Il cap d'ingresso è validato qui, non da Pydantic, per rispondere con lo
    # stesso formato stringa degli altri 422 invece dell'array di validazione.
    if len(req.text) > REQUEST_TEXT_MAX_CHARS:
        raise HTTPException(
            status_code=422,
            detail=(
                f"testo troppo lungo ({len(req.text)} caratteri, "
                f"limite {REQUEST_TEXT_MAX_CHARS}): riduci o spezza il testo"
            ),
        )

    clean_text = TextNormalizer.normalize(
        text=req.text,
        lang=lang,
        enabled=normalize_enabled,
        exclusions=exclusions,
    )
    if not clean_text:
        raise HTTPException(status_code=422, detail="testo vuoto dopo il parsing o le esclusioni")

    # La lingua effettiva serve prima del guard: `chunk_text` accorpa le frasi
    # entro il `max_len` scelto e il coreano regge meno caratteri (vedi
    # `SENTENCE_MAX_CHARS_KO`). `_guard_lang` risolve anche `"auto"`, `"na"` e
    # `None` con la stessa euristica del motore; se non rileva nulla resta
    # `"na"` e vale il default 900.
    text_error = _normalized_text_error(clean_text, _guard_lang(manager, clean_text, lang))
    if text_error is not None:
        raise HTTPException(status_code=422, detail=text_error)

    try:
        wav_bytes, duration_ms = manager.synthesize(
            text=clean_text, lang=lang, voice=voice, steps=steps, speed=speed
        )
    except ValueError as exc:
        logger.error(
            "TTS ValueError: %s (text=%r, lang=%r, voice=%r, steps=%r, speed=%r)",
            exc,
            clean_text,
            lang,
            voice,
            steps,
            speed,
        )
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except RuntimeError as exc:
        # Include gli errori di inferenza (ONNX/CoreML) racchiusi dal manager in
        # TTSEngineError: il dettaglio resta sintetico, lo stack va nei log.
        logger.error("TTS non disponibile: %s", exc)
        raise HTTPException(status_code=503, detail=UNAVAILABLE_DETAIL) from exc
    return Response(
        content=wav_bytes,
        media_type="audio/wav",
        headers={"X-Duration-Ms": str(duration_ms), "Cache-Control": "no-store"},
    )
