"""Lettura clipboard cross-platform (fallback universale)."""

import logging
import shutil
import subprocess

import pyperclip

logger = logging.getLogger(__name__)


def read_clipboard() -> str:
    """Ritorna il testo in clipboard, o '' se non testuale/non disponibile."""
    try:
        return (pyperclip.paste() or "").strip()
    except Exception:  # noqa: BLE001
        logger.debug("pyperclip fallito, uso fallback di sistema", exc_info=True)

    if shutil.which("pbpaste"):
        out = subprocess.run(["pbpaste"], capture_output=True, text=True, timeout=3)
        return out.stdout.strip()
    if shutil.which("wl-paste"):
        out = subprocess.run(
            ["wl-paste", "--no-newline"], capture_output=True, text=True, timeout=3
        )
        return out.stdout.strip()
    if shutil.which("xclip"):
        out = subprocess.run(
            ["xclip", "-selection", "clipboard", "-o"], capture_output=True, text=True, timeout=3
        )
        return out.stdout.strip()
    return ""
