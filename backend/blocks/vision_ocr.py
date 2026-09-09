from __future__ import annotations

import logging
import os
import sys
from typing import Any

from backend.blocks.models import BoundingBox, RawElement

logger = logging.getLogger(__name__)

_VISION_AVAILABLE: bool | None = None
_VNRecognizeTextRequest: Any = None
_VNImageRequestHandler: Any = None
_NSData: Any = None


def _init_vision() -> bool:
    global _VISION_AVAILABLE, _VNRecognizeTextRequest, _VNImageRequestHandler, _NSData
    if _VISION_AVAILABLE is not None:
        return _VISION_AVAILABLE

    if sys.platform != "darwin":
        _VISION_AVAILABLE = False
        return False

    try:
        import objc
        from Foundation import NSBundle, NSData

        bundle = NSBundle.bundleWithPath_("/System/Library/Frameworks/Vision.framework")
        if not bundle or not bundle.load():
            _VISION_AVAILABLE = False
            return False

        _VNRecognizeTextRequest = objc.lookUpClass("VNRecognizeTextRequest")
        _VNImageRequestHandler = objc.lookUpClass("VNImageRequestHandler")
        _NSData = NSData
        _VISION_AVAILABLE = True
        logger.info("Apple Vision.framework OCR caricato con successo.")
        return True
    except Exception as e:
        logger.warning("Inizializzazione Apple Vision.framework non riuscita: %s", e)
        _VISION_AVAILABLE = False
        return False


def is_vision_available() -> bool:
    """Verifica se il motore OCR Apple Vision è supportato su questa piattaforma."""
    return _init_vision()


def perform_vision_ocr(
    image_bytes: bytes | None = None,
    image_path: str | None = None,
    languages: list[str] | None = None,
) -> list[RawElement]:
    """Esegue il riconoscimento ottico dei caratteri (OCR) offline tramite Apple Vision.

    Restituisce la lista di frammenti/righe testuali identificati con relativi bounding boxes.
    """
    if not _init_vision():
        logger.warning("Vision OCR non disponibile su questo sistema.")
        return []

    data = None
    if image_bytes:
        data = _NSData.dataWithBytes_length_(image_bytes, len(image_bytes))
    elif image_path and os.path.exists(image_path):
        with open(image_path, "rb") as f:
            b = f.read()
            data = _NSData.dataWithBytes_length_(b, len(b))

    if not data:
        logger.warning("Dati immagine non forniti o file inesistente.")
        return []

    try:
        handler = _VNImageRequestHandler.alloc().initWithData_options_(data, None)
        request = _VNRecognizeTextRequest.alloc().init()
        request.setRecognitionLevel_(1)  # 1 = accurate, 0 = fast
        request.setUsesLanguageCorrection_(True)

        lang_list = languages or ["it-IT", "en-US"]
        request.setRecognitionLanguages_(lang_list)

        success = handler.performRequests_error_([request], None)
        if not success:
            logger.error("Esecuzione di VNRecognizeTextRequest non riuscita.")
            return []

        results = request.results()
        if not results:
            return []

        elements: list[RawElement] = []
        for obs in results:
            candidates = obs.topCandidates_(1)
            if not candidates:
                continue

            candidate = candidates[0]
            text = str(candidate.string()).strip()
            if not text:
                continue

            confidence = 1.0
            if hasattr(candidate, "confidence"):
                try:
                    confidence = float(candidate.confidence())
                except Exception:
                    pass

            bbox: BoundingBox | None = None
            if hasattr(obs, "boundingBox"):
                box = obs.boundingBox()
                # Le coordinate Vision hanno l'origine in basso a sinistra (0.0 a 1.0)
                # Convertiamo l'asse Y con origine in alto per coerenza con lo schermo UI
                top_y = 1.0 - (float(box.origin.y) + float(box.size.height))
                bbox = BoundingBox(
                    x=round(float(box.origin.x) * 1000, 1),
                    y=round(max(0.0, top_y) * 1000, 1),
                    width=round(float(box.size.width) * 1000, 1),
                    height=round(float(box.size.height) * 1000, 1),
                )

            elements.append(
                RawElement(
                    role="OCRLine",
                    text=text,
                    bbox=bbox,
                    confidence=round(confidence, 3),
                )
            )

        return elements
    except Exception as exc:
        logger.error("Errore durante l'elaborazione OCR: %s", exc, exc_info=True)
        return []
