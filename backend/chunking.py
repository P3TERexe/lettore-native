"""Modulo per la segmentazione del testo (paragrafi e frasi).

Segmentazione leggera basata su regex con protezione delle abbreviazioni comuni
e numeri decimali, senza dipendenze pesanti esterne.
"""

from __future__ import annotations

import re

_PARAGRAPH_SPLIT = re.compile(r"\n\s*\n")
_ABBR_PATTERN = re.compile(r"\b([A-Za-z]+(?:\.[A-Za-z]+)*)\.")
_SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+")

# Abbreviazioni comuni (italiano e inglese) che non devono interrompere la frase
_ABBREVIATIONS = {
    "dott",
    "dott.ssa",
    "sig",
    "sig.ra",
    "prof",
    "prof.ssa",
    "avv",
    "ing",
    "arch",
    "mr",
    "mrs",
    "ms",
    "dr",
    "jr",
    "sr",
    "st",
    "vs",
    "etc",
    "e.g",
    "i.e",
    "p",
    "pp",
    "pag",
    "pagg",
    "cap",
    "art",
    "n",
    "vol",
    "a.m",
    "p.m",
}


def split_into_paragraphs(text: str) -> list[str]:
    """Divide il testo in paragrafi su doppi ritorni a capo o singoli se isolati."""
    parts = [p.strip() for p in _PARAGRAPH_SPLIT.split(text)]
    if len(parts) <= 1:
        parts = [p.strip() for p in text.split("\n")]
    return [p for p in parts if p]


def split_into_sentences(text: str, lang: str = "it") -> list[str]:
    """Divide il testo in frasi preservando abbreviazioni e numeri decimali."""
    text = text.strip()
    if not text:
        return []

    def _protect_abbr(match: re.Match[str]) -> str:
        token = match.group(1)
        if token.lower() in _ABBREVIATIONS:
            return token + "\u200b"
        return match.group(0)

    protected = _ABBR_PATTERN.sub(_protect_abbr, text)
    raw_splits = _SENTENCE_SPLIT.split(protected)

    sentences = [s.replace("\u200b", ".").strip() for s in raw_splits]
    return [s for s in sentences if s]


def _group_sentences(sentences: list[str], max_chars: int) -> list[str]:
    chunks = []
    current = ""
    is_first = True
    for s in sentences:
        limit = 60 if is_first else max_chars
        if not current:
            current = s
        elif len(current) + len(s) + 1 <= limit:
            current += " " + s
        else:
            chunks.append(current)
            current = s
            is_first = False
    if current:
        chunks.append(current)
    return chunks


def smart_chunk_text(
    text: str,
    lang: str = "it",
    split_paragraphs: bool = False,
    max_chunk_chars: int = 150,
) -> list[str]:
    """Segmenta il testo in chunk ottimali per la sintesi vocale."""
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
        sentences = split_into_sentences(text, lang=lang)
        return _group_sentences(sentences, max_chunk_chars)
