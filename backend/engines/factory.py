"""Factory per l'istanziazione modulare dei motori TTS."""

from __future__ import annotations

import logging

from .base import BaseTTSEngine
from .onnx_engine import SupertonicONNXEngine

logger = logging.getLogger(__name__)


def create_engine(
    engine_type: str = "supertonic",
    model: str = "supertonic-3",
    auto_download: bool = True,
) -> BaseTTSEngine:
    """Crea e ritorna un'istanza del motore TTS richiesto.

    Args:
        engine_type: Identificativo del motore ("supertonic").
        model: Nome o percorso del modello.
        auto_download: Se scaricare automaticamente i pesi se mancanti.

    Raises:
        ValueError: Se l'engine_type richiesto non è supportato.
    """
    normalized_type = engine_type.strip().lower()
    if normalized_type == "supertonic":
        return SupertonicONNXEngine(model=model, auto_download=auto_download)

    raise ValueError(
        f"Motore TTS sconosciuto o non registrato: '{engine_type}'. "
        f"Motori supportati: ['supertonic']"
    )
