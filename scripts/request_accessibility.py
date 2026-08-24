#!/usr/bin/env python3
"""Script per richiedere a macOS il permesso di Accessibilità con popup di sistema."""

import sys


def request_permission():
    try:
        from ApplicationServices import (
            AXIsProcessTrustedWithOptions,
            kAXTrustedCheckOptionPrompt,
        )
        from Foundation import NSDictionary

        options = NSDictionary.dictionaryWithObject_forKey_(True, kAXTrustedCheckOptionPrompt)
        trusted = AXIsProcessTrustedWithOptions(options)
        if trusted:
            print("OK: Permesso di Accessibilità già concesso per questo ambiente.")
            return 0
        else:
            print("ATTENZIONE: macOS ha generato una richiesta di autorizzazione.")
            print("Apri 'Impostazioni di Sistema -> Privacy e Sicurezza -> Accessibilità'")
            print("e attiva lo switch per l'applicazione segnalata da macOS.")
            return 1
    except Exception as exc:
        print(f"Errore durante la richiesta di permesso: {exc}")
        return 2


if __name__ == "__main__":
    sys.exit(request_permission())
