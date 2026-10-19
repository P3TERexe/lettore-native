# Cattura del Testo Nativamente in Rust tramite AXUIElement

**Stato**: Accettata  
**Data**: 2026-09-03

## Contesto & Problema

Il backend Python richiedeva dipendenze OS-specifiche (`pyperclip`, moduli nativi) per interagire con il sistema operativo, rendendo fragile il setup e la portabilità.

## Decisione Presa

Spostare l'intera cattura del testo a monte nel processo host Tauri (Rust) tramite le API di Accessibilità native di macOS (`AXUIElement`), con fallback automatico a simulazione tastiera `Cmd+C` e clipboard Rust. Rimosse tutte le dipendenze Python di clipboard.

## Alternative Scartate

Cattura in Python (`pyperclip`, script `osascript`/AppKit): lenta, incline a fallimenti di permessi e dipendente da librerie esterne.

## Conseguenze & Vincoli Intoccabili

Il backend Python riceve il testo già catturato via HTTP; non reintrodurre librerie di cattura o clipboard nel runtime Python.
