---
name: macos-accessibility-ax
description: >-
  Guida e procedure per l'integrazione delle API di Accessibilità macOS (AXUIElement,
  AXObserver con kAXSelectedTextChangedNotification, AXIsProcessTrusted) e strategie di
  cattura testo selezionato con fallback su clipboard.
---

# macOS Accessibility (AX) Skill

Questa skill definisce i pattern e le best practice per intercettare il testo selezionato in qualsiasi applicazione macOS attraverso PyObjC e l'API Accessibility di macOS.

---

## 1. Gestione dei Permessi di Sistema

macOS richiede l'autorizzazione esplicita dell'utente in:
`Impostazioni di Sistema → Privacy e Sicurezza → Accessibilità`.

### Verifica Programmatica
```python
from ApplicationServices import AXIsProcessTrusted, AXIsProcessTrustedWithOptions
from Foundation import NSDictionary

def check_ax_permission(prompt_user: bool = False) -> bool:
    if prompt_user:
        options = NSDictionary.dictionaryWithObject_forKey_(
            True, "AXTrustedCheckOptionPrompt"
        )
        return AXIsProcessTrustedWithOptions(options)
    return AXIsProcessTrusted()
```

*Nota*: Se il comando viene eseguito da Terminale, iTerm2, VS Code o Electron, l'app genitrice deve avere il permesso abilitato.

---

## 2. Cattura Selezione (AXUIElement)

Per estrarre il testo selezionato dell'applicazione attualmente in primo piano:

```python
from AppKit import NSWorkspace
from ApplicationServices import (
    AXUIElementCreateApplication,
    AXUIElementCopyAttributeValue,
    kAXFocusedUIElementAttribute,
    kAXSelectedTextAttribute,
)

def get_selected_text_focused() -> str | None:
    front_app = NSWorkspace.sharedWorkspace().frontmostApplication()
    if not front_app:
        return None
    
    app_ref = AXUIElementCreateApplication(front_app.processIdentifier())
    err, focused_elem = AXUIElementCopyAttributeValue(app_ref, kAXFocusedUIElementAttribute, None)
    if err != 0 or not focused_elem:
        return None
        
    err, text = AXUIElementCopyAttributeValue(focused_elem, kAXSelectedTextAttribute, None)
    if err == 0 and text and isinstance(text, str) and text.strip():
        return text.strip()
    return None
```

> [!WARNING]
> Non usare `kAXValueAttribute` come fallback generico nei campi di input, perché restituirebbe l'intero contenuto del campo anziché solo la porzione selezionata.

---

## 3. Modalità Event-Driven con `AXObserver`

Invece di interrogare l'API ogni $N$ millisecondi con un polling timer, è possibile agganciare un observer all'evento di cambio selezione:

```python
from ApplicationServices import (
    AXObserverCreate,
    AXObserverAddNotification,
    AXObserverGetRunLoopSource,
    kAXSelectedTextChangedNotification,
)
from CoreFoundation import CFRunLoopGetCurrent, CFRunLoopAddSource, kCFRunLoopDefaultMode
import objc

@objc.callbackFor(AXObserverCreate)
def _ax_notification_callback(observer, element, notification_name, user_data):
    if notification_name == kAXSelectedTextChangedNotification:
        # Recupera il testo selezionato ed emetti l'evento verso la coda
        pass
```

---

## 4. Strategia di Fallback (Clipboard + CGEvent)

Se un'applicazione non espone gli attributi Accessibility (es. terminali senza integrazione AX o alcune web view custom):
1. Verificare se la clipboard contiene testo recente.
2. Inviare una combinazione simulata `Cmd+C` via `Quartz.CGEventCreateKeyboardEvent`.
3. Leggere il buffer della clipboard.
