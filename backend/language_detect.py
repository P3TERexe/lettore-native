"""Rilevamento automatico della lingua del testo (langdetect).

Ritorna un codice ISO tra quelli supportati da Supertonic, o None se il
rilevamento non è affidabile (testo troppo corto, confidenza bassa, lingua
non supportata) — in quel caso il chiamante usa il fallback "na".
"""

import hashlib
import logging

from langdetect import DetectorFactory, detect_langs
from langdetect.lang_detect_exception import LangDetectException

from .tts_manager import SUPPORTED_LANGUAGES, UNKNOWN_LANG

logger = logging.getLogger(__name__)

DetectorFactory.seed = 0
MIN_TEXT_LENGTH = 10
MIN_CONFIDENCE = 0.5
MAX_CACHE_ENTRIES = 256

# mappature tra codici langdetect e codici ISO Supertonic
_ALIASES = {
    "zh-cn": "na",
    "zh-tw": "na",
    "zh": "na",
    "pt-br": "pt",
    "nb": "no",  # niente norvegese in supertonic -> na via set
    "mk": "na",
    "so": "na",
    "sq": "na",
    "sw": "na",
    "ta": "na",
    "te": "na",
    "th": "na",
    "tl": "na",
    "bn": "na",
    "fa": "na",
    "gu": "na",
    "kn": "na",
    "ml": "na",
    "mr": "na",
    "ne": "na",
    "pa": "na",
}

_SUPPORTED = set(SUPPORTED_LANGUAGES)
_cache: dict[str, str | None] = {}


def detect(text: str) -> str | None:
    """Ritorna un codice ISO supertonic (o None per usare 'na')."""
    clean = text.strip()
    if len(clean) < MIN_TEXT_LENGTH:
        return None
    key = hashlib.sha256(clean.encode("utf-8", "replace")).hexdigest()
    if key in _cache:
        return _cache[key]
    result = _detect(clean)
    if len(_cache) >= MAX_CACHE_ENTRIES:
        _cache.clear()
    _cache[key] = result
    return result


def _detect(clean: str) -> str | None:
    try:
        langs = detect_langs(clean)
    except LangDetectException:
        return None
    if not langs:
        return None
    best = langs[0]
    if best.prob < MIN_CONFIDENCE:
        return None
    code = _ALIASES.get(best.lang, best.lang)
    if code == UNKNOWN_LANG or code not in _SUPPORTED:
        return None
    return code
