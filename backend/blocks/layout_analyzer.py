from __future__ import annotations

import re
from typing import Any

from backend.blocks.models import BlockType, BoundingBox, DocumentModel, RawElement, TextBlock
from backend.textnorm.normalizer import TextNormalizer

_HEADING_MD_PATTERN = re.compile(r"^(#{1,6})\s+(.+)$")
_LIST_ITEM_PATTERN = re.compile(r"^([•\-\*]|\d+[\.\)]|[a-z][\.\)])\s+(.+)$", re.IGNORECASE)
_QUOTE_PATTERN = re.compile(r"^(>|«|\"\")\s*(.+)$")
_CODE_PATTERN = re.compile(r"^(```|~~~|\t| {4,})")


def _classify_text_segment(text: str, role: str | None = None) -> tuple[BlockType, int | None]:
    """Determina il tipo semantico e l'eventuale livello gerarchico di un blocco."""
    trimmed = text.strip()
    if not trimmed:
        return BlockType.PARAGRAPH, None

    # Se il ruolo AX nativo indica chiaramente un tipo
    if role:
        r_lower = role.lower()
        if "heading" in r_lower or "header" in r_lower or "title" in r_lower:
            return BlockType.HEADING, 1
        if "list" in r_lower or "row" in r_lower or "item" in r_lower:
            return BlockType.LIST_ITEM, None
        if "code" in r_lower:
            return BlockType.CODE, None
        if "quote" in r_lower:
            return BlockType.QUOTE, None

    # Verifica pattern Markdown Heading
    md_match = _HEADING_MD_PATTERN.match(trimmed)
    if md_match:
        level = len(md_match.group(1))
        return BlockType.HEADING, level

    # Verifica pattern Elenco Puntato / Numerato
    if _LIST_ITEM_PATTERN.match(trimmed):
        return BlockType.LIST_ITEM, None

    # Verifica pattern Citazione
    if _QUOTE_PATTERN.match(trimmed):
        return BlockType.QUOTE, None

    # Verifica Blocco di Codice
    if _CODE_PATTERN.match(trimmed) or trimmed.startswith("```"):
        return BlockType.CODE, None

    # Euristica per Titoli privi di markup (linea breve, senza punto finale, maiuscola o capitalizzata)
    lines = trimmed.split("\n")
    if len(lines) == 1 and len(trimmed) <= 75 and not trimmed.endswith((".", ";", ":", ",")):
        if trimmed.isupper() or (
            len(trimmed) >= 3 and trimmed[0].isupper() and len(trimmed.split()) <= 8
        ):
            return BlockType.HEADING, 2

    return BlockType.PARAGRAPH, None


def _clean_block_text(text: str, block_type: BlockType) -> str:
    """Rimuove simboli di marcatura superficiali (es. # iniziali, > di citazione)."""
    trimmed = text.strip()
    if block_type == BlockType.HEADING:
        md_match = _HEADING_MD_PATTERN.match(trimmed)
        if md_match:
            return md_match.group(2).strip()
    elif block_type == BlockType.QUOTE:
        q_match = _QUOTE_PATTERN.match(trimmed)
        if q_match:
            return q_match.group(2).strip()
    elif block_type == BlockType.CODE:
        if trimmed.startswith("```") and trimmed.endswith("```"):
            return trimmed.strip("`").strip()
    return trimmed


def _combine_bboxes(b1: BoundingBox | None, b2: BoundingBox | None) -> BoundingBox | None:
    if not b1:
        return b2
    if not b2:
        return b1

    x1 = min(b1.x, b2.x)
    y1 = min(b1.y, b2.y)
    x2 = max(b1.x + b1.width, b2.x + b2.width)
    y2 = max(b1.y + b1.height, b2.y + b2.height)

    return BoundingBox(x=x1, y=y1, width=max(0.0, x2 - x1), height=max(0.0, y2 - y1))


def analyze_layout(
    text: str | None = None,
    raw_elements: list[RawElement | dict[str, Any]] | None = None,
    app_name: str | None = None,
    source: str = "manual",
    exclusions: list[str] | None = None,
) -> DocumentModel:
    """Analizza elementi grezzi o testo lineare e produce un DocumentModel strutturato."""
    blocks: list[TextBlock] = []

    # Caso 1: Elementi grezzi con ruoli e/o coordinate (da AX o da Vision OCR)
    if raw_elements and len(raw_elements) > 0:
        parsed_elements: list[RawElement] = []
        for el in raw_elements:
            if isinstance(el, RawElement):
                parsed_elements.append(el)
            elif isinstance(el, dict):
                bbox_data = el.get("bbox")
                bbox = (
                    BoundingBox(**bbox_data) if bbox_data and isinstance(bbox_data, dict) else None
                )
                parsed_elements.append(
                    RawElement(
                        role=str(el.get("role", "AXStaticText")),
                        text=str(el.get("text", "")).strip(),
                        bbox=bbox,
                        confidence=float(el.get("confidence", 1.0)),
                    )
                )

        # Filtra elementi con testo vuoto
        parsed_elements = [e for e in parsed_elements if e.text]

        # Ordina per posizione a schermo (dall'alto verso il basso, poi da sinistra a destra)
        if any(e.bbox for e in parsed_elements):
            parsed_elements.sort(
                key=lambda e: (round(e.bbox.y, -1) if e.bbox else 0, e.bbox.x if e.bbox else 0)
            )

        # Raggruppa elementi consecutivi che appartengono al medesimo paragrafo
        grouped: list[tuple[RawElement, list[RawElement]]] = []
        for el in parsed_elements:
            if not grouped:
                grouped.append((el, []))
                continue

            last_main, last_children = grouped[-1]
            last_el = last_children[-1] if last_children else last_main

            # Condizioni di unione per paragrafi scorrevoli (stesso ruolo, distanza verticale minima)
            can_merge = False
            if (
                last_main.role in ("AXStaticText", "AXParagraph", "AXTextArea", "OCRLine")
                and el.role in ("AXStaticText", "AXParagraph", "AXTextArea", "OCRLine")
                and not _HEADING_MD_PATTERN.match(el.text)
                and not _LIST_ITEM_PATTERN.match(el.text)
            ):
                if last_el.bbox and el.bbox:
                    # Distanza verticale tra fondo del precedente e cima del corrente
                    v_gap = el.bbox.y - (last_el.bbox.y + last_el.bbox.height)
                    # Tolleranza ~25px per considerare righe consecutive dello stesso paragrafo
                    if -5.0 <= v_gap <= 28.0:
                        can_merge = True
                elif not last_el.bbox and not el.bbox:
                    can_merge = True

            if can_merge:
                last_children.append(el)
            else:
                grouped.append((el, []))

        for idx, (main_el, children) in enumerate(grouped):
            all_parts = [main_el] + children
            full_text = " ".join(part.text for part in all_parts if part.text)
            block_type, level = _classify_text_segment(full_text, main_el.role)
            clean_display_text = _clean_block_text(full_text, block_type)

            # Normalizzazione fonetica per TTS
            clean_tts = TextNormalizer.normalize_italian(clean_display_text)
            if exclusions:
                clean_tts = TextNormalizer.filter_exclusions(clean_tts, exclusions)

            # Combina i bounding box di tutti gli elementi figli
            combined_bbox = main_el.bbox
            for child in children:
                combined_bbox = _combine_bboxes(combined_bbox, child.bbox)

            avg_confidence = sum(p.confidence for p in all_parts) / max(len(all_parts), 1)

            blocks.append(
                TextBlock(
                    id=f"block-{idx + 1}",
                    type=block_type,
                    text=clean_display_text,
                    clean_text=clean_tts,
                    level=level,
                    bbox=combined_bbox,
                    word_count=len(clean_display_text.split()),
                    confidence=round(avg_confidence, 3),
                    source=source,
                )
            )

    # Caso 2: Solo testo puro (Clipboard, input manuale, fallback)
    elif text and text.strip():
        # Separa per ritorni a capo multipli
        raw_sections = [s.strip() for s in re.split(r"\n\s*\n+", text) if s.strip()]
        if not raw_sections:
            raw_sections = [text.strip()]

        for _idx, sec in enumerate(raw_sections):
            # Se la sezione contiene più elementi di lista puntata, separali
            lines = [line.strip() for line in sec.split("\n") if line.strip()]
            is_all_list = len(lines) > 1 and all(_LIST_ITEM_PATTERN.match(line) for line in lines)

            sub_chunks = lines if is_all_list else [sec]

            for sub_text in sub_chunks:
                b_type, lvl = _classify_text_segment(sub_text)
                disp_text = _clean_block_text(sub_text, b_type)
                clean_tts = TextNormalizer.normalize_italian(disp_text)
                if exclusions:
                    clean_tts = TextNormalizer.filter_exclusions(clean_tts, exclusions)

                blocks.append(
                    TextBlock(
                        id=f"block-{len(blocks) + 1}",
                        type=b_type,
                        text=disp_text,
                        clean_text=clean_tts,
                        level=lvl,
                        bbox=None,
                        word_count=len(disp_text.split()),
                        confidence=1.0,
                        source=source,
                    )
                )

    return DocumentModel(
        source=source,
        app_name=app_name,
        total_blocks=len(blocks),
        blocks=blocks,
    )
