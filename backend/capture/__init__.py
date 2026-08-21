"""CaptureManager: orchestrazione cattura testo.

Ordine: Accessibility di piattaforma (AX/UIA/AT-SPI) → fallback clipboard.
"""

import logging
import sys
import threading
import time

from ..models import CaptureResponse
from . import clipboard

logger = logging.getLogger(__name__)

if sys.platform == "darwin":
    from . import macos as _platform
elif sys.platform == "win32":
    from . import windows as _platform
else:
    from . import linux as _platform


class CaptureManager:
    def __init__(self, enabled: bool = True, delay_ms: int = 400):
        self.enabled = enabled
        self.delay_ms = max(50, delay_ms)
        self.available = (
            _platform.HAVE_AX
            if getattr(_platform, "HAVE_AX", False)
            else getattr(_platform, "HAVE_UIA", getattr(_platform, "HAVE_ATSPI", False))
        )
        if sys.platform == "darwin":
            self.available = _platform.HAVE_AX
        elif sys.platform == "win32":
            self.available = _platform.HAVE_UIA
        else:
            self.available = _platform.HAVE_ATSPI

        self._last: str = ""
        self._callback = None
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._warned_permission = False

    # --- lettura on demand -------------------------------------------------

    @property
    def permission_granted(self) -> bool:
        fn = getattr(_platform, "permission_granted", None)
        return bool(fn() if callable(fn) else False)

    def read_selection(self, auto_copy: bool = False) -> CaptureResponse:
        resp = self._read_selection_impl()
        if resp.text or not auto_copy or not self.available:
            return resp
        try:
            posted = _platform.post_copy()
        except _platform.CapturePermissionError:  # type: ignore[attr-defined]
            return CaptureResponse(
                text="", source="accessibility", error="accessibility_permission"
            )
        if not posted:
            return resp
        time.sleep(0.35)
        try:
            text = _platform.read_selection()
        except _platform.CapturePermissionError:  # type: ignore[attr-defined]
            return resp
        if text:
            return CaptureResponse(text=text, source="accessibility")
        text = clipboard.read_clipboard()
        if text:
            return CaptureResponse(text=text, source="clipboard")
        return resp

    def _read_selection_impl(self) -> CaptureResponse:
        if not self.enabled:
            return CaptureResponse(text="", source="none", error="capture_disabled")
        error = None
        if self.available:
            try:
                text = _platform.read_selection()
                if text:
                    return CaptureResponse(text=text, source="accessibility")
            except _platform.CapturePermissionError:  # type: ignore[attr-defined]
                error = "accessibility_permission"
                if not self._warned_permission:
                    self._warned_permission = True
                    logger.warning("Permesso Accessibilità non concesso")
            except Exception:  # noqa: BLE001
                logger.debug("Cattura AX fallita", exc_info=True)
                error = "accessibility_error"
        if error != "capture_disabled":
            text = clipboard.read_clipboard()
            if text:
                return CaptureResponse(text=text, source="clipboard")
        return CaptureResponse(text="", source="accessibility", error=error)

    # --- watcher automatico (capture_auto) ---------------------------------

    def start_watcher(self, callback) -> None:
        if self._thread is not None or not self.available:
            return
        self._callback = callback
        self._stop.clear()
        self._thread = threading.Thread(target=self._watch_loop, name="capture-watch", daemon=True)
        self._thread.start()

    def stop_watcher(self) -> None:
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=2)
            self._thread = None

    def _watch_loop(self) -> None:
        while not self._stop.is_set():
            time.sleep(1.0)
            if self._stop.is_set():
                return
            if not self.available:
                continue
            try:
                text = _platform.read_selection()
            except Exception:  # noqa: BLE001
                continue
            if not text or not text.strip() or text == self._last:
                continue
            # Debounce: aspetta che la selezione si stabilizzi (es. durante selezione col mouse)
            time.sleep(max(0.4, self.delay_ms / 1000.0))
            if self._stop.is_set():
                return
            try:
                text2 = _platform.read_selection()
            except Exception:  # noqa: BLE001
                continue
            if text2 and text2 == text and text2 != self._last:
                self._last = text2
                try:
                    if self._callback is not None and self._callback(text2) is False:
                        self._stop.set()
                        return
                except Exception:  # noqa: BLE001
                    logger.debug("Callback cattura fallita", exc_info=True)
