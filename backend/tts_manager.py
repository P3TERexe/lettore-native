"""TTSManager: singleton attorno a supertonic.TTS.

Il modello viene caricato in un thread in background all'avvio (il primo
download ~400MB avviene qui). La sintesi è serializzata con un lock perché
onnxruntime non è thread-safe per sessioni condivise.
"""

import logging
import threading
import time

# --- PATCH ONNXRUNTIME PER HARDWARE ACCELERATION SU MACOS ---
# Attenzione: ort.InferenceSession va sostituito con una SOTTOCLASSE, non
# con una funzione — supertonic fa isinstance(session, ort.InferenceSession)
# e il secondo argomento deve restare un tipo.
try:
    import onnxruntime as ort

    def _resolve_providers(providers):
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
            self, path_or_bytes, sess_options=None, providers=None, provider_options=None, **kwargs
        ):
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

from collections import OrderedDict
from pathlib import Path

from supertonic import TTS
from supertonic.config import SUPPORTED_LANGUAGES

from .audio_utils import numpy_to_wav_bytes

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


def _model_cache_dir(model: str) -> Path:
    base = Path.home() / ".cache"
    mapping = {
        "supertonic": "supertonic",
        "supertonic-2": "supertonic2",
        "supertonic-3": "supertonic3",
    }
    return base / mapping.get(model, "supertonic3")


def _discover_custom_voices(model: str) -> list[str]:
    custom_dir = _model_cache_dir(model) / "custom_styles"
    if not custom_dir.is_dir():
        return []
    return sorted(p.stem for p in custom_dir.glob("*.json"))


class TTSManager:
    def __init__(self, model: str = "supertonic-3", auto_download: bool = True):
        self.model = model
        self.auto_download = auto_download
        self._engine: TTS | None = None
        self._engine_error: str | None = None
        self._lock = threading.Lock()
        self._init_lock = threading.Lock()
        self.loading = False
        self.ready = False
        self._load_thread = threading.Thread(target=self._load, name="tts-load", daemon=True)
        self._cache = OrderedDict()
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
                    "Caricamento modello %s (primo download ~400MB se assente)...", self.model
                )
                self._engine = TTS(auto_download=self.auto_download, model=self.model)
                self.ready = True
                logger.info(
                    "Modello pronto: sample_rate=%s, voci=%s",
                    self._engine.sample_rate,
                    self._engine.voice_style_names,
                )
            except Exception as exc:  # noqa: BLE001
                self._engine_error = f"{type(exc).__name__}: {exc}"
                logger.exception("Errore caricamento modello")
            finally:
                self.loading = False

    def wait_ready(self, timeout: float = 600.0) -> None:
        """Blocca finché il modello non è pronto (o fallisce)."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.ready:
                return
            if self._engine_error:
                raise RuntimeError(self._engine_error)
            time.sleep(0.25)
        raise TimeoutError("Tempo scaduto attendendo il caricamento del modello")

    def voices(self) -> tuple[list[str], list[str]]:
        builtin = list(self._engine.voice_style_names) if self._engine else []
        return builtin, _discover_custom_voices(self.model)

    def languages(self) -> list[dict]:
        return [{"code": c, "label": _LANGUAGE_LABELS.get(c, c)} for c in LANGUAGES]

    def synthesize(
        self, text: str, lang: str, voice: VoiceSpec, steps: int, speed: float
    ) -> tuple[bytes, int]:
        """Ritorna (wav_bytes, duration_ms). Lancia RuntimeError se il modello non è pronto.

        lang="auto" esegue il rilevamento automatico della lingua per il
        singolo testo; se non affidabile usa il fallback "na".
        """
        if not self.ready:
            if self._engine_error:
                raise RuntimeError(self._engine_error)
            raise RuntimeError("modello non ancora caricato")

        cache_key = (text, lang, voice, steps, speed)
        with self._cache_lock:
            if cache_key in self._cache:
                self._cache.move_to_end(cache_key)
                logger.info("TTS Cache HIT: %d char", len(text))
                return self._cache[cache_key]

        effective_lang = self.resolve_lang(text, lang)
        style = self._resolve_style(voice)
        with self._lock:
            wav, duration = self._engine.synthesize(
                text=text,
                voice_style=style,
                lang=effective_lang,
                total_steps=steps,
                speed=speed,
            )
        duration_ms = int(float(duration[0]) * 1000.0)
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

    def _resolve_style(self, voice: VoiceSpec):
        assert self._engine is not None
        if voice in self._engine.voice_style_names:
            return self._engine.get_voice_style(voice)
        custom_path = _model_cache_dir(self.model) / "custom_styles" / f"{voice}.json"
        if custom_path.is_file():
            return self._engine.get_voice_style_from_path(custom_path)
        raise ValueError(f"voce sconosciuta: {voice}")
