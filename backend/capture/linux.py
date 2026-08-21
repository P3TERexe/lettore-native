"""Cattura selezione su Linux tramite AT-SPI (pyatspi).

Richiede il supporto AT-SPI attivo (es. GNOME: org.gnome.desktop.interface
toolkit-accessibility true).
"""

import logging

logger = logging.getLogger(__name__)

HAVE_ATSPI = False
pyatspi = None

try:
    import pyatspi

    HAVE_ATSPI = True
except Exception:  # noqa: BLE001
    logger.debug("AT-SPI non disponibile", exc_info=True)


def _selected_text_of(accessible) -> str | None:
    interfaces = set(accessible.get_interfaces())
    if pyatspi.TEXT not in interfaces:
        return None
    try:
        count = accessible.get_selected_text_count()
    except Exception:  # noqa: BLE001
        return None
    if not count:
        return None
    parts = []
    for i in range(count):
        try:
            parts.append(accessible.get_selected_text(i))
        except Exception:  # noqa: BLE001
            continue
    return "".join(parts) or None


def _walk_focused(accessible, depth=0) -> str | None:
    if accessible is None or depth > 10:
        return None
    if pyatspi.STATE_FOCUSED in accessible.get_state():
        text = _selected_text_of(accessible)
        if text:
            return text
    for child in accessible:
        found = _walk_focused(child, depth + 1)
        if found:
            return found
    return None


def read_selection() -> str | None:
    if not HAVE_ATSPI:
        return None
    try:
        desktop = pyatspi.Registry.getDesktop(0)
        text = _walk_focused(desktop)
        if text:
            return text
    except Exception:  # noqa: BLE001
        logger.debug("Lettura AT-SPI fallita", exc_info=True)
    return None


def permission_granted() -> bool:
    return HAVE_ATSPI


def post_copy() -> bool:
    return False
