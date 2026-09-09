"""Motore TTS basato su ONNX Runtime e Supertonic 3.

Supporta accelerazione hardware automatica CoreML (Apple Silicon) e CUDA (NVIDIA),
con fallback trasparente su CPUExecutionProvider (ADR-004).
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    import numpy as np

# --- PATCH ONNXRUNTIME PER HARDWARE ACCELERATION (ADR-004) ---
# ort.InferenceSession va sostituito con una SOTTOCLASSE, non con una funzione:
# supertonic esegue isinstance(session, ort.InferenceSession).
try:
    import onnxruntime as ort

    def _resolve_providers(providers: list[str] | None) -> list[str]:
        if providers and "CoreMLExecutionProvider" in providers:
            return providers
        available = ort.get_available_providers()
        resolved = [
            p for p in ("CoreMLExecutionProvider", "CUDAExecutionProvider") if p in available
        ]
        resolved.append("CPUExecutionProvider")
        return resolved

    class _AcceleratedSession(ort.InferenceSession):
        """InferenceSession con selezione automatica dei provider (CoreML/CUDA/CPU)."""

        def __init__(
            self,
            path_or_bytes: Any,
            sess_options: Any = None,
            providers: list[str] | None = None,
            provider_options: Any = None,
            **kwargs: Any,
        ) -> None:
            super().__init__(
                path_or_bytes,
                sess_options=sess_options,
                providers=_resolve_providers(providers),
                provider_options=provider_options,
                **kwargs,
            )

    ort.InferenceSession = _AcceleratedSession
except ImportError:
    pass
# -----------------------------------------------------------

from supertonic import TTS
from supertonic.config import SUPPORTED_LANGUAGES

from .base import BaseTTSEngine

logger = logging.getLogger(__name__)


def _model_cache_dir(model: str) -> Path:
    base = Path.home() / ".cache"
    mapping = {
        "supertonic-3": "supertonic3",
        "supertonic-2": "supertonic2",
        "supertonic": "supertonic",
    }
    return base / mapping.get(model, "supertonic3")


class SupertonicONNXEngine(BaseTTSEngine):
    """Implementazione ONNX Runtime per il modello Supertonic."""

    def __init__(self, model: str = "supertonic-3", auto_download: bool = True) -> None:
        self.model = model
        self.auto_download = auto_download
        self._tts: TTS | None = None

    @property
    def sample_rate(self) -> int | None:
        return self._tts.sample_rate if self._tts else None

    @property
    def voice_names(self) -> list[str]:
        return list(self._tts.voice_style_names) if self._tts else []

    @property
    def supported_languages(self) -> list[str]:
        return list(SUPPORTED_LANGUAGES)

    def load(self) -> None:
        """Carica il modello Supertonic via ONNX Runtime."""
        if self._tts is not None:
            return
        logger.info(
            "Inizializzazione SupertonicONNXEngine (modello=%s, auto_download=%s)...",
            self.model,
            self.auto_download,
        )
        self._tts = TTS(auto_download=self.auto_download, model=self.model)
        logger.info(
            "SupertonicONNXEngine pronto: sample_rate=%s, voci=%s",
            self._tts.sample_rate,
            self._tts.voice_style_names,
        )

    def unload(self) -> None:
        """Rilascia la sessione ONNX e le risorse allocate."""
        self._tts = None
        logger.info("SupertonicONNXEngine rilasciato.")

    def discover_custom_voices(self, cache_dir: Path | None = None) -> list[str]:
        target_dir = (
            cache_dir / "custom_styles"
            if cache_dir
            else _model_cache_dir(self.model) / "custom_styles"
        )
        if not target_dir.is_dir():
            return []
        return sorted(p.stem for p in target_dir.glob("*.json"))

    def _resolve_style(self, voice: str) -> Any:
        if self._tts is None:
            raise RuntimeError("Motore ONNX non inizializzato")
        # 1. Match esatto (es. "M1", "F1")
        if voice in self._tts.voice_style_names:
            return self._tts.get_voice_style(voice)
        
        # 2. Match su suffisso lingua (es. "IT-M1" -> "M1", "EN-F2" -> "F2")
        candidate = voice.strip().split("-")[-1].upper()
        if candidate in self._tts.voice_style_names:
            return self._tts.get_voice_style(candidate)
            
        # 3. Match su file di stile personalizzato
        custom_path = _model_cache_dir(self.model) / "custom_styles" / f"{voice}.json"
        if custom_path.is_file():
            return self._tts.get_voice_style_from_path(custom_path)
            
        # 4. Fallback sicuro su M1 invece di bloccare la sintesi con eccezione 400
        logger.warning("Voce '%s' non trovata in %s. Fallback su 'M1'", voice, self._tts.voice_style_names)
        return self._tts.get_voice_style("M1")

    def synthesize(
        self, text: str, voice: str, lang: str, steps: int, speed: float
    ) -> tuple[np.ndarray, float]:
        if self._tts is None:
            raise RuntimeError("Motore ONNX non inizializzato")
        style = self._resolve_style(voice)
        
        # Sanitizzazione automatica dei caratteri non supportati (es. emoji, varianti grafiche, simboli rari)
        sanitized_text = text
        if hasattr(self._tts, "model") and hasattr(self._tts.model, "text_processor"):
            tp = self._tts.model.text_processor
            is_valid, unsupported = tp.validate_text(sanitized_text)
            if not is_valid and unsupported:
                logger.info("Rimozione caratteri non supportati per TTS: %s", unsupported)
                for c in unsupported:
                    sanitized_text = sanitized_text.replace(c, " ")
                sanitized_text = " ".join(sanitized_text.split())
        
        if not sanitized_text.strip():
            sanitized_text = "..."
            
        # Clamping velocità ammesso da Supertonic (0.7 - 2.0)
        safe_speed = max(0.7, min(2.0, float(speed)))
            
        wav, duration = self._tts.synthesize(
            text=sanitized_text,
            voice_style=style,
            lang=lang,
            total_steps=steps,
            speed=safe_speed,
        )
        duration_sec = float(duration[0])
        return wav, duration_sec
