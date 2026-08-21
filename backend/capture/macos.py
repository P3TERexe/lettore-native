"""Cattura selezione su macOS tramite AXUIElement (PyObjC).

Richiede il permesso Accessibilità per il processo che esegue il backend.
"""

import logging

logger = logging.getLogger(__name__)

HAVE_AX = False
AXUIElementCreateApplication = AXUIElementCopyAttributeValue = None
AXIsProcessTrusted = None
kAXErrorSuccess = kAXFocusedUIElementAttribute = kAXSelectedTextAttribute = None
kAXParentAttribute = kAXValueAttribute = kAXErrorAttributeUnsupported = None
NSWorkspace = None

try:
    from AppKit import NSWorkspace
    from ApplicationServices import (
        AXIsProcessTrusted,
        AXUIElementCopyAttributeValue,
        AXUIElementCreateApplication,
        kAXErrorSuccess,
        kAXFocusedUIElementAttribute,
        kAXParentAttribute,
        kAXSelectedTextAttribute,
    )

    HAVE_AX = True
except Exception:  # noqa: BLE001
    logger.debug("PyObjC AX non disponibile su questo sistema", exc_info=True)


_CGEventCreateKeyboardEvent = _CGEventPost = None
_kCGHIDEventTap = _kCGEventKeyDown = _kCGEventKeyUp = None
_kCGEventFlagMaskCommand = 1 << 20  # kCGEventFlagMaskCommand

try:
    from Quartz import (
        CGEventCreateKeyboardEvent,
        CGEventPost,
        kCGEventKeyDown,
        kCGEventKeyUp,
        kCGHIDEventTap,
    )

    _CGEventCreateKeyboardEvent = CGEventCreateKeyboardEvent
    _CGEventPost = CGEventPost
    _kCGEventKeyDown = kCGEventKeyDown
    _kCGEventKeyUp = kCGEventKeyUp
    _kCGHIDEventTap = kCGHIDEventTap
except Exception:  # noqa: BLE001
    logger.debug("Quartz non disponibile (auto-copy disabilitato)", exc_info=True)


class CapturePermissionError(Exception):
    """Permesso Accessibilità non concesso."""


def _copy_attr(element, attr):
    try:
        err, value = AXUIElementCopyAttributeValue(element, attr, None)
    except Exception:  # noqa: BLE001
        return None
    if err != kAXErrorSuccess:
        return None
    return value


def _focused_text() -> str | None:
    """Testo selezionato nell'app in primo piano (walk-up dagli elementi focalizzati)."""
    app = NSWorkspace.sharedWorkspace().frontmostApplication()
    if app is None:
        return None
    pid = app.processIdentifier()
    app_el = AXUIElementCreateApplication(pid)
    node = _copy_attr(app_el, kAXFocusedUIElementAttribute)
    depth = 0
    while node is not None and depth < 12:
        text = _copy_attr(node, kAXSelectedTextAttribute)
        if text and isinstance(text, str) and text.strip():
            return str(text)
        node = _copy_attr(node, kAXParentAttribute)
        depth += 1
    return None


def read_selection() -> str | None:
    """Ritorna la selezione testuale corrente, o None."""
    if not HAVE_AX:
        return None
    if not AXIsProcessTrusted():
        raise CapturePermissionError(
            "Permesso Accessibilità non concesso: abilita il processo in "
            "Impostazioni → Privacy e sicurezza → Accessibilità"
        )
    try:
        return _focused_text()
    except Exception:  # noqa: BLE001
        logger.debug("Lettura AX fallita", exc_info=True)
        return None


def permission_granted() -> bool:
    """True se il processo corrente ha il permesso Accessibilità."""
    if not HAVE_AX or AXIsProcessTrusted is None:
        return False
    try:
        return bool(AXIsProcessTrusted())
    except Exception:  # noqa: BLE001
        return False


def post_copy() -> bool:
    """Simula Cmd+C sull'app in primo piano (richiede permesso Accessibilità)."""
    if not HAVE_AX or _CGEventCreateKeyboardEvent is None:
        return False
    if not AXIsProcessTrusted():
        raise CapturePermissionError("Permesso Accessibilità non concesso")
    try:
        key_c = 8  # kVK_ANSI_C
        down = _CGEventCreateKeyboardEvent(None, key_c, True)
        up = _CGEventCreateKeyboardEvent(None, key_c, False)
        for ev in (down, up):
            if ev is None:
                return False
            ev.setFlags(_kCGEventFlagMaskCommand)
            _CGEventPost(_kCGHIDEventTap, ev)
        return True
    except Exception:  # noqa: BLE001
        logger.debug("Post Cmd+C fallito", exc_info=True)
        return False
