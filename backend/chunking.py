"""Modulo per la segmentazione intelligente del testo (paragrafi e frasi).

Usa pySBD (Python Sentence Boundary Disambiguation) per dividere i testi in
frasi o paragrafi preservando abbreviazioni, numeri decimali e punteggiatura.
"""

from __future__ import annotations

import logging
import re

logger = logging.getLogger("lettore.chunking")

_PARAGRAPH_SPLIT = re.compile(r"\n\s*\n")
_FALLBACK_SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+")

# Lingue ufficialmente supportate da pySBD
_PYSBD_LANGUAGES = {
    "en",
    "it",
    "es",
    "fr",
    "de",
    "pt",
    "ru",
    "ja",
    "zh",
    "nl",
    "pl",
    "ro",
    "da",
    "el",
    "sk",
    "ar",
    "bg",
    "hy",
    "mr",
    "my",
    "hi",
    "ur",
}

_segmenters: dict[str, object] = {}


def _get_segmenter(lang: str):
    import pysbd

    normalized_lang = lang.lower() if lang else "en"
    if normalized_lang not in _PYSBD_LANGUAGES:
        normalized_lang = "en"

    if normalized_lang not in _segmenters:
        try:
            _segmenters[normalized_lang] = pysbd.Segmenter(language=normalized_lang, clean=False)
        except Exception as e:
            logger.warning("Impossibile inizializzare pySBD per '%s': %s", lang, e)
            return None
    return _segmenters[normalized_lang]


def split_into_paragraphs(text: str) -> list[str]:
    """Divide il testo in paragrafi su doppi ritorni a capo o singoli se isolati."""
    parts = [p.strip() for p in _PARAGRAPH_SPLIT.split(text)]
    if len(parts) <= 1:
        parts = [p.strip() for p in text.split("\n")]
    return [p for p in parts if p]


def split_into_sentences(text: str, lang: str = "it") -> list[str]:
    """Divide il testo in frasi usando pySBD con fallback su regex."""
    text = text.strip()
    if not text:
        return []

    segmenter = _get_segmenter(lang)
    if segmenter is not None:
        try:
            segments = segmenter.segment(text)
            if isinstance(segments, list):
                result = [s.strip() for s in segments if s and s.strip()]
                if result:
                    return result
        except Exception as e:
            logger.warning("Errore durante segmentazione pySBD: %s", e)

    # Fallback su regex
    parts = [s.strip() for s in _FALLBACK_SENTENCE_SPLIT.split(text)]
    return [s for s in parts if s]


def _group_sentences(sentences: list[str], max_chars: int) -> list[str]:
    chunks = []
    current = ""
    for s in sentences:
        if not current:
            current = s
        elif len(current) + len(s) + 1 <= max_chars:
            current += " " + s
        else:
            chunks.append(current)
            current = s
    if current:
        chunks.append(current)
    return chunks


def smart_chunk_text(
    text: str,
    lang: str = "it",
    split_paragraphs: bool = False,
    max_chunk_chars: int = 150,
) -> list[str]:
    """Segmenta il testo in chunk ottimali per la sintesi vocale,
    privilegiando una bassa latenza per le frasi lunghe.
    """
    text = text.strip()
    if not text:
        return []

    if split_paragraphs:
        paragraphs = split_into_paragraphs(text)
        chunks: list[str] = []
        for para in paragraphs:
            if len(para) <= max_chunk_chars:
                chunks.append(para)
            else:
                sentences = split_into_sentences(para, lang=lang)
                chunks.extend(_group_sentences(sentences, max_chunk_chars))
        return chunks
    else:
        # Segmentazione attiva in frasi per streaming reattivo
        sentences = split_into_sentences(text, lang=lang)
        return _group_sentences(sentences, max_chunk_chars)
