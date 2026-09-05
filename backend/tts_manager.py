"""TTSManager: singleton di orchestrazione del motore TTS.

Disaccoppia l'applicazione dal runtime di inferenza specifico (es. ONNX Runtime,
PyTorch, Piper) mediante l'interfaccia BaseTTSEngine.

Il caricamento dei pesi avviene in background all'avvio. La sintesi è rigorosamente
serializzata con threading.Lock() sincrono per garantire stabilità e prevenire
race condition nei provider nativi (ADR-002).
"""

from __future__ import annotations

import logging
import threading
import time
from collections import OrderedDict
from typing import TYPE_CHECKING

from supertonic.config import SUPPORTED_LANGUAGES

from .audio_utils import numpy_to_wav_bytes
from .engines import BaseTTSEngine, create_engine

if TYPE_CHECKING:
    from pathlib import Path

logger = logging.getLogger(__name__)

UNKNOWN_LANG = "na"
LANGUAGES = SUPPORTED_LANGUAGES + [UNKNOWN_LANG]
AUTO_LANG = "auto"

_LANGUAGE_LABELS = {
    "en": "English",
    "ko": "한국어",
    "ja": "日本語",
    "ar": "العربية",
    "bg": "Български",
    "cs": "Čeština",
    "da": "Dansk",
    "de": "Deutsch",
    "el": "Ελληνικά",
    "es": "Español",
    "et": "Eesti",
    "fi": "Suomi",
    "fr": "Français",
    "hi": "हिन्दी",
    "hr": "Hrvatski",
    "hu": "Magyar",
    "id": "Bahasa Indonesia",
    "it": "Italiano",
    "lt": "Lietuvių",
    "lv": "Latviešu",
    "nl": "Nederlands",
    "pl": "Polski",
    "pt": "Português",
    "ro": "Română",
    "ru": "Русский",
    "sk": "Slovenčina",
    "sl": "Slovenščina",
    "sv": "Svenska",
    "tr": "Türkçe",
    "uk": "Українська",
    "vi": "Tiếng Việt",
    UNKNOWN_LANG: "Auto (rileva lingua)",
}

VoiceSpec = str


class TTSManager:
    """Gestore unificato e thread-safe del motore vocale."""

    def __init__(
        self,
        model: str = "supertonic-3",
        auto_download: bool = True,
        engine: str = "supertonic",
    ) -> None:
        self.model = model
        self.auto_download = auto_download
        self.engine_type = engine
        self._engine: BaseTTSEngine | None = None
        self._engine_error: str | None = None
        self._lock = threading.Lock()
        self._init_lock = threading.Lock()
        self.loading = False
        self.ready = False
        self._load_thread = threading.Thread(target=self._load, name="tts-load", daemon=True)
        self._cache: OrderedDict[tuple, tuple[bytes, int]] = OrderedDict()
        self._cache_lock = threading.Lock()
        self._cache_max_size = 64

    @property
    def sample_rate(self) -> int | None:
        return self._engine.sample_rate if self._engine else None

    def start(self) -> None:
        self._load_thread.start()

    def _load(self) -> None:
        with self._init_lock:
            if self.ready or self._engine:
                return
            self.loading = True
            try:
                logger.info(
                    "Caricamento motore TTS '%s' (modello=%s)...",
                    self.engine_type,
                    self.model,
                )
                self._engine = create_engine(
                    engine_type=self.engine_type,
                    model=self.model,
                    auto_download=self.auto_download,
                )
                self._engine.load()
                self.ready = True
                logger.info(
                    "Motore '%s' pronto: sample_rate=%s, voci=%s",
                    self.engine_type,
                    self._engine.sample_rate,
                    self._engine.voice_names,
                )
            except Exception as exc:  # noqa: BLE001
                self._engine_error = f"{type(exc).__name__}: {exc}"
                logger.exception("Errore caricamento motore TTS")
            finally:
                self.loading = False

    def wait_ready(self, timeout: float = 600.0) -> None:
        """Blocca finché il motore non è pronto (o fallisce)."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.ready:
                return
            if self._engine_error:
                raise RuntimeError(self._engine_error)
            time.sleep(0.25)
        raise TimeoutError("Tempo scaduto attendendo il caricamento del modello TTS")

    def voices(self, cache_dir: Path | None = None) -> tuple[list[str], list[str]]:
        if not self._engine:
            return [], []
        builtin = self._engine.voice_names
        custom = self._engine.discover_custom_voices(cache_dir=cache_dir)
        return builtin, custom

    def languages(self) -> list[dict[str, str]]:
        supported = self._engine.supported_languages if self._engine else SUPPORTED_LANGUAGES
        langs = list(supported)
        if UNKNOWN_LANG not in langs:
            langs.append(UNKNOWN_LANG)
        return [{"code": c, "label": _LANGUAGE_LABELS.get(c, c)} for c in langs]

    def synthesize(
        self, text: str, lang: str, voice: VoiceSpec, steps: int, speed: float
    ) -> tuple[bytes, int]:
        """Ritorna (wav_bytes, duration_ms). Lancia RuntimeError se il modello non è pronto."""
        if not self.ready:
            if self._engine_error:
                raise RuntimeError(self._engine_error)
            raise RuntimeError("modello non ancora caricato")

        assert self._engine is not None

        cache_key = (text, lang, voice, steps, speed)
        with self._cache_lock:
            if cache_key in self._cache:
                self._cache.move_to_end(cache_key)
                logger.info("TTS Cache HIT: %d char", len(text))
                return self._cache[cache_key]

        effective_lang = self.resolve_lang(text, lang)
        with self._lock:
            wav, duration_sec = self._engine.synthesize(
                text=text,
                voice=voice,
                lang=effective_lang,
                steps=steps,
                speed=speed,
            )
        duration_ms = int(duration_sec * 1000.0)
        wav_bytes = numpy_to_wav_bytes(wav, self.sample_rate)
        res = (wav_bytes, duration_ms)

        with self._cache_lock:
            self._cache[cache_key] = res
            if len(self._cache) > self._cache_max_size:
                self._cache.popitem(last=False)

        return res

    @staticmethod
    def resolve_lang(text: str, lang: str) -> str:
        if lang != AUTO_LANG:
            return lang
        from .language_detect import detect  # import locale: evita cicli

        detected = detect(text)
        if detected is not None:
            logger.debug("Lingua rilevata: %s", detected)
            return detected
        return UNKNOWN_LANG
