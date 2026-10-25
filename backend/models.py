"""Schemi Pydantic del backend."""

from typing import Literal

from pydantic import BaseModel, Field

# Limite dei chunk prodotti dal client nativo (`SentenceChunker` in LettoreCore).
# Un testo entro questo limite è già segmentato: il backend non deve richunkarlo.
CLIENT_CHUNK_MAX_CHARS = 240


class TTSRequest(BaseModel):
    """Richiesta di sintesi per un singolo chunk.

    Contratto con il client nativo: il testo arriva già filtrato, segmentato e
    normalizzato una sola volta in ``LettoreCore``, con lunghezza massima
    ``CLIENT_CHUNK_MAX_CHARS``. Il backend sintetizza il testo ricevuto così
    com'è e non applica alcun richunking.

    ``normalize_text`` resta ``True`` di default per i client esterni (il sito),
    che non hanno una pipeline di preparazione propria.
    """

    text: str = Field(min_length=1, max_length=20000)
    lang: str = "auto"
    voice: str = "M1"
    steps: int = Field(default=8, ge=5, le=12)
    speed: float = Field(default=1.05, ge=0.1, le=4.0)
    normalize_text: bool = True
    text_exclusions: list[str] = Field(default_factory=list)


class VoiceEntry(BaseModel):
    id: str
    name: str
    langs: list[str]
    group: Literal["builtin", "custom"]


class VoiceList(BaseModel):
    builtin: list[VoiceEntry]
    custom: list[VoiceEntry]


class VoiceUpdate(BaseModel):
    name: str | None = None
    langs: list[str] | None = None


class LanguageEntry(BaseModel):
    code: str
    label: str


class StatusResponse(BaseModel):
    ready: bool
    model_loading: bool
    model: str
    sample_rate: int | None = None


class AppConfig(BaseModel):
    voice: str = "M1"
    lang: str = "auto"
    speed: float = Field(default=1.05, ge=0.7, le=2.0)
    steps: int = Field(default=8, ge=5, le=12)
    normalize_text: bool = True
    text_exclusions: list[str] = Field(default_factory=list)
