from __future__ import annotations

from enum import Enum

from pydantic import BaseModel, Field


class BlockType(str, Enum):
    HEADING = "heading"
    PARAGRAPH = "paragraph"
    LIST_ITEM = "list_item"
    QUOTE = "quote"
    CODE = "code"


class BoundingBox(BaseModel):
    x: float = Field(default=0.0, description="Coordinata X orizzontale")
    y: float = Field(default=0.0, description="Coordinata Y verticale")
    width: float = Field(default=0.0, description="Larghezza del riquadro")
    height: float = Field(default=0.0, description="Altezza del riquadro")


class RawElement(BaseModel):
    role: str = Field(default="AXStaticText", description="Ruolo AX o tipo di elemento OCR")
    text: str = Field(..., description="Testo dell'elemento")
    bbox: BoundingBox | None = Field(default=None, description="Bounding box dell'elemento")
    confidence: float = Field(default=1.0, description="Confidenza del riconoscimento")


class TextBlock(BaseModel):
    id: str = Field(..., description="Identificativo univoco del blocco (es. block-1)")
    type: BlockType = Field(default=BlockType.PARAGRAPH, description="Tipo semantico del blocco")
    text: str = Field(..., description="Testo originale estratto")
    clean_text: str = Field(..., description="Testo normalizzato foneticamente per il TTS")
    level: int | None = Field(
        default=None, description="Livello gerarchico (es. 1, 2, 3 per heading)"
    )
    bbox: BoundingBox | None = Field(default=None, description="Riquadro a schermo del blocco")
    word_count: int = Field(default=0, description="Numero di parole")
    confidence: float = Field(default=1.0, description="Grado di confidenza nell'estrazione")
    source: str = Field(
        default="accessibility",
        description="Sorgente di cattura (accessibility, ocr, clipboard, manual)",
    )


class DocumentModel(BaseModel):
    source: str = Field(default="accessibility", description="Canale primario di acquisizione")
    app_name: str | None = Field(default=None, description="Nome dell'applicazione sorgente")
    total_blocks: int = Field(default=0, description="Totale blocchi identificati")
    blocks: list[TextBlock] = Field(
        default_factory=list, description="Lista ordinata dei blocchi semantici"
    )
