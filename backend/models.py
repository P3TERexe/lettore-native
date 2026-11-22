"""Schemi Pydantic del backend."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

# Limite dei chunk prodotti dal client nativo (`SentenceChunker` in LettoreCore).
# Un testo entro questo limite è già segmentato: il backend non deve richunkarlo.
CLIENT_CHUNK_MAX_CHARS = 240

# Limite per i client esterni (il sito), che non segmentano il testo. Il cap
# vale sul testo in ingresso, prima della normalizzazione, che può allungarlo
# (misurato 1000 -> 1943 caratteri con le sole email). La normalizzazione può
# solo allungare il testo, quindi il cap post-normalizzazione resta 1000. Il
# router valida entrambi i limiti e risponde 422 prima dell'inferenza. Il
# client nativo invia comunque chunk <= 240.
REQUEST_TEXT_MAX_CHARS = 1000

# Il cap post-normalizzazione resta 1000: mantenere lo stesso contratto in
# ingresso e in uscita è verificabile senza stimare l'espansione. Da solo non
# garantisce chunk interni sicuri, perché una singola frase può essere lunga
# quanto l'intero testo.
NORMALIZED_TEXT_MAX_CHARS = REQUEST_TEXT_MAX_CHARS

# Limite prudente sulla singola frase più lunga per le lingue non coreane.
# `supertonic.utils.chunk_text` accorpa le frasi fino a `max_len` (default 300)
# e non spezza mai una frase più lunga: una frase senza punteggiatura diventa
# un'unica inferenza. Sul motore reale una singola richiesta di 985 caratteri
# riesce e una di 992 fallisce: 900 lascia un margine prudente.
MAX_SENTENCE_CHARS = 900

# Il coreano regge meno caratteri per inferenza. Misure con il motore reale:
# una singola frase da 400 caratteri riesce, una da 500 fallisce (503 dal-
# l'ONNX). Con il vecchio cap fisso a 300 il client esterno riceveva 422; con
# 900 la frase coreana passava il guard e falliva nell'inferenza. 300 è un
# margine prudente rispetto al fallimento misurato a 500, non il `max_len` del
# motore: supertonic usa 120 per il coreano (300 per le altre lingue) e non
# spezza una frase più lunga del limite.
MAX_SENTENCE_CHARS_KO = 300

# Soglie del guard per lingua effettiva (ISO). Le lingue assenti usano
# `MAX_SENTENCE_CHARS`; `"auto"`, `"na"` e `None` vengono risolti dal router
# prima del guard con `TTSManager.resolve_lang` (la stessa euristica del
# motore).
SENTENCE_MAX_CHARS_BY_LANG: dict[str, int] = {"ko": MAX_SENTENCE_CHARS_KO}


def normalize_guard_lang(lang: str | None) -> str:
    """Codice lingua normalizzato per il guard: trim, minuscole, alias regione.

    ``"ko-KR"``/``"ko_KR"`` diventano ``"ko"``, ``"KO"`` diventa ``"ko"``.
    Non tocca la validazione del motore: ``lang`` resta quello inviato dal
    client.
    """
    code = (lang or "").strip().lower().replace("_", "-")
    return code.split("-", 1)[0]


def sentence_max_chars(lang: str | None) -> int:
    """Soglia della frase più lunga per la lingua effettiva.

    ``lang`` può essere un codice ISO (case e alias regione indifferenti),
    ``"auto"``/``"na"`` (non ancora risolto) o ``None``; in questi ultimi casi
    vale il default non coreano.
    """
    return SENTENCE_MAX_CHARS_BY_LANG.get(normalize_guard_lang(lang), MAX_SENTENCE_CHARS)


class TTSRequest(BaseModel):
    """Richiesta di sintesi per un singolo chunk.

    Contratto con il client nativo: il testo arriva già filtrato, segmentato e
    normalizzato una sola volta in ``LettoreCore``, con lunghezza massima
    ``CLIENT_CHUNK_MAX_CHARS``. Il backend sintetizza il testo ricevuto così
    com'è e non applica alcun richunking.

    I client esterni possono inviare testi più lunghi, fino a
    ``REQUEST_TEXT_MAX_CHARS``; oltre il limite la richiesta viene rifiutata
    dal router con 422 e un messaggio nello stesso formato degli altri limiti
    (non con l'array di validazione Pydantic). Lo stesso vale per il testo dopo
    la normalizzazione quando supera ``NORMALIZED_TEXT_MAX_CHARS`` o quando la
    frase più lunga calcolata da ``chunk_text`` supera la soglia della lingua
    effettiva (``MAX_SENTENCE_CHARS``, oppure ``MAX_SENTENCE_CHARS_KO`` per il
    coreano).
    ``normalize_text`` resta ``True`` di default per i client esterni (il
    sito), che non hanno una pipeline di preparazione propria.
    """

    text: str = Field(min_length=1)
    lang: str | None = None
    voice: str | None = None
    steps: int | None = Field(default=None, ge=5, le=12)
    speed: float | None = Field(default=None, ge=0.7, le=2.0)
    normalize_text: bool | None = None
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
