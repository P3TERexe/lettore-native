"""Cattura selezione su Windows tramite UI Automation (comtypes).

Nota: alcune app elevate (admin) non espongono UIA a processi non elevati.
"""

import logging

logger = logging.getLogger(__name__)

HAVE_UIA = False
uia = None
comtypes = None

try:
    import comtypes
    import comtypes.client

    comtypes.client.GetModule("UIAutomationCore.dll")
    from comtypes.gen import UIAutomationClient as uia

    HAVE_UIA = True
except Exception:  # noqa: BLE001
    logger.debug("UI Automation non disponibile", exc_info=True)

if HAVE_UIA:

    def _element_text(element) -> str | None:
        try:
            pattern = element.GetCurrentPattern(uia.UIA_TextPatternId)
        except Exception:  # noqa: BLE001
            return None
        if not pattern:
            return None
        try:
            ranges = pattern.GetSelection()
        except Exception:  # noqa: BLE001
            return None
        if ranges is None or ranges.Length == 0:
            return None
        try:
            return ranges.GetElement(0).GetText(-1)
        except Exception:  # noqa: BLE001
            return None


def read_selection() -> str | None:
    if not HAVE_UIA:
        return None
    try:
        automation = comtypes.client.CreateObject(uia.CUIAutomation)
        focused = automation.GetFocusedElement()
        if focused is None:
            return None
        node = focused
        depth = 0
        while node is not None and depth < 12:
            text = _element_text(node)
            if text:
                return text
            try:
                node = (
                    uia.IUIAutomationElement(node).GetParentElement()
                    if False
                    else node.GetParentElement()
                )
            except Exception:  # noqa: BLE001
                break
            depth += 1
    except Exception:  # noqa: BLE001
        logger.debug("Lettura UIA fallita", exc_info=True)
    return None


def permission_granted() -> bool:
    return HAVE_UIA


def post_copy() -> bool:
    return False
