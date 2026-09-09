from __future__ import annotations

import base64

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from backend.blocks.layout_analyzer import analyze_layout
from backend.blocks.models import DocumentModel, RawElement
from backend.blocks.vision_ocr import is_vision_available, perform_vision_ocr

router = APIRouter(prefix="/v1/blocks", tags=["blocks"])


class AnalyzeRequest(BaseModel):
    text: str | None = Field(default=None, description="Testo grezzo da segmentare in blocchi")
    raw_elements: list[RawElement] | None = Field(
        default=None, description="Elementi strutturati AX o OCR"
    )
    app_name: str | None = Field(default=None, description="Nome dell'applicazione sorgente")
    source: str = Field(
        default="manual", description="Sorgente (accessibility, clipboard, ocr, manual)"
    )
    exclusions: list[str] | None = Field(
        default=None, description="Stringhe da escludere dalla sintesi TTS"
    )


class OcrRequest(BaseModel):
    image_path: str | None = Field(
        default=None, description="Percorso del file immagine sul filesystem locale"
    )
    image_base64: str | None = Field(default=None, description="Immagine codificata in Base64")
    app_name: str | None = Field(
        default=None, description="Nome dell'applicazione sorgente catturata"
    )
    languages: list[str] | None = Field(
        default=None, description="Lingue OCR (default: ['it-IT', 'en-US'])"
    )
    exclusions: list[str] | None = Field(
        default=None, description="Stringhe da escludere dalla sintesi TTS"
    )


@router.get("/status")
def get_blocks_status() -> dict[str, object]:
    """Restituisce lo stato dei motori di estrazione blocchi e disponibilità OCR."""
    return {
        "ok": True,
        "ocr_available": is_vision_available(),
        "ocr_engine": "apple_vision" if is_vision_available() else "none",
        "layout_engine": "deterministic_v1",
    }


@router.post("/analyze", response_model=DocumentModel)
def analyze_blocks(payload: AnalyzeRequest) -> DocumentModel:
    """Segmenta ed analizza testo o frammenti AX restituendo un DocumentModel semantico."""
    if not payload.text and not payload.raw_elements:
        return DocumentModel(
            source=payload.source,
            app_name=payload.app_name,
            total_blocks=0,
            blocks=[],
        )

    try:
        return analyze_layout(
            text=payload.text,
            raw_elements=payload.raw_elements,
            app_name=payload.app_name,
            source=payload.source,
            exclusions=payload.exclusions,
        )
    except Exception as exc:
        raise HTTPException(
            status_code=500, detail=f"Errore durante l'analisi del layout: {exc}"
        ) from exc


@router.post("/ocr", response_model=DocumentModel)
def ocr_and_analyze_blocks(payload: OcrRequest) -> DocumentModel:
    """Esegue OCR offline con Apple Vision e restituisce i blocchi strutturati."""
    if not is_vision_available():
        raise HTTPException(
            status_code=501, detail="Vision OCR non supportato su questo sistema operativo."
        )

    image_bytes = None
    if payload.image_base64:
        try:
            image_bytes = base64.b64decode(payload.image_base64)
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Base64 non valido: {e}") from e
    elif not payload.image_path:
        raise HTTPException(status_code=400, detail="Fornire 'image_path' o 'image_base64'.")

    elements = perform_vision_ocr(
        image_bytes=image_bytes,
        image_path=payload.image_path,
        languages=payload.languages,
    )

    return analyze_layout(
        raw_elements=elements,
        app_name=payload.app_name,
        source="ocr",
        exclusions=payload.exclusions,
    )
