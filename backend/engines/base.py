"""Interfaccia astratta per i motori di sintesi vocale (TTS).

Consente la sostituzione plug-and-play del motore TTS (es. Supertonic ONNX,
modelli PyTorch, Piper, Coqui o servizi remoti) senza modificare la logica
applicativa, le API o il frontend.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import numpy as np


class BaseTTSEngine(ABC):
    """Interfaccia base per un motore TTS."""

    @property
    @abstractmethod
    def sample_rate(self) -> int | None:
        """Sample rate audio in Hz (es. 24000 o 44100)."""
        ...

    @property
    @abstractmethod
    def voice_names(self) -> list[str]:
        """Elenco degli identificatori delle voci integrate disponibili."""
        ...

    @property
    @abstractmethod
    def supported_languages(self) -> list[str]:
        """Elenco dei codici lingua supportati (es. ['it', 'en', ...])."""
        ...

    @abstractmethod
    def load(self) -> None:
        """Inizializza e carica in memoria i pesi o la sessione del motore."""
        ...

    @abstractmethod
    def unload(self) -> None:
        """Rilascia le risorse allocate dal motore."""
        ...

    @abstractmethod
    def synthesize(
        self, text: str, voice: str, lang: str, steps: int, speed: float
    ) -> tuple[np.ndarray, float]:
        """Sintetizza il testo in waveform audio.

        Ritorna:
            (waveform, duration_seconds) dove waveform è un array numpy float32.
        """
        ...

    @abstractmethod
    def discover_custom_voices(self, cache_dir: Path | None = None) -> list[str]:
        """Ritorna l'elenco degli ID delle voci custom disponibili."""
        ...
