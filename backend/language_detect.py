"""Rilevamento leggero della lingua del testo tramite stdlib.

Identifica script non-latini (cirillico, arabo, giapponese, coreano, greco, devanagari)
tramite range Unicode e lingue latine principali (it, en, es, fr, de, pt) tramite stopwords.
Ritorna un codice ISO supportato o None per usare il fallback di default ("na").
"""

from __future__ import annotations

import re

# Stopword frequenti per le principali lingue a caratteri latini
_STOPWORDS: dict[str, set[str]] = {
    "it": {
        "il",
        "la",
        "di",
        "che",
        "per",
        "un",
        "una",
        "sono",
        "con",
        "nel",
        "della",
        "questo",
        "questa",
        "anche",
        "delle",
    },
    "en": {
        "the",
        "and",
        "is",
        "in",
        "to",
        "of",
        "that",
        "it",
        "with",
        "as",
        "for",
        "was",
        "on",
        "are",
        "by",
        "this",
    },
    "es": {
        "el",
        "la",
        "de",
        "que",
        "y",
        "en",
        "un",
        "una",
        "por",
        "con",
        "para",
        "los",
        "las",
        "del",
        "como",
    },
    "fr": {
        "le",
        "la",
        "les",
        "de",
        "des",
        "du",
        "et",
        "est",
        "un",
        "une",
        "que",
        "dans",
        "pour",
        "qui",
        "sur",
    },
    "de": {
        "der",
        "die",
        "das",
        "und",
        "in",
        "den",
        "von",
        "zu",
        "mit",
        "ist",
        "des",
        "nicht",
        "eine",
        "einer",
        "dem",
    },
    "pt": {
        "o",
        "a",
        "os",
        "as",
        "de",
        "do",
        "da",
        "em",
        "um",
        "uma",
        "para",
        "com",
        "não",
        "que",
        "por",
    },
}

_WORD_PATTERN = re.compile(r"\b\w+\b")


def detect(text: str) -> str | None:
    """Ritorna un codice ISO lingua supportato, o None se non rilevabile."""
    clean = text.strip()
    if len(clean) < 5:
        return None

    # Rilevamento immediato per script non-latini
    for char in clean:
        cp = ord(char)
        if 0x0600 <= cp <= 0x06FF:
            return "ar"
        if 0x0400 <= cp <= 0x04FF:
            return "ru"
        if 0x0370 <= cp <= 0x03FF:
            return "el"
        if 0x0900 <= cp <= 0x097F:
            return "hi"
        if 0xAC00 <= cp <= 0xD7AF or 0x1100 <= cp <= 0x11FF:
            return "ko"
        if 0x3040 <= cp <= 0x30FF:
            return "ja"

    # Rilevamento per lingue latine basato su stopword
    words = _WORD_PATTERN.findall(clean.lower())
    if not words:
        return None

    scores = {lang: 0 for lang in _STOPWORDS}
    for word in words:
        for lang, sw in _STOPWORDS.items():
            if word in sw:
                scores[lang] += 1

    best_lang, best_score = max(scores.items(), key=lambda item: item[1])
    if best_score >= 1:
        return best_lang

    return None
