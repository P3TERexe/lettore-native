# AGENTS.md

## Architettura 100% Native macOS (Fase 3.0)

Lettore Native è ora un'applicazione **macOS nativa** scritta in Swift 6, basata su **SwiftUI** e **AppKit**.
L'architettura ibrida precedente (Tauri / HTML / JS) è stata completamente abbandonata per massimizzare le prestazioni, ridurre la memoria consumata (<80MB) e sfruttare l'integrazione a basso livello con il sistema operativo (Accessibility API e CoreAudio).

Il progetto è composto da due parti:
- **`Sources/`** — Applicazione macOS Swift (Client UI, Audio Engine, Core Logic).
- **`backend/`** — Server locale FastAPI in Python (porta `7788`). Genera l'audio TTS tramite il runtime ONNX Supertonic. Viene usato come sidecar.

> **Nota per M4:** In futuro, il backend Python verrà eliminato e il modello ONNX verrà integrato direttamente in Swift tramite C-API (ONNX Runtime) per un'architettura a *zero-processi-esterni*.

## Comandi Swift (macOS)

Tutti i comandi Swift devono essere eseguiti dalla root del progetto:

```bash
swift build                    # Compila il progetto
swift run LettoreApp           # Avvia l'applicazione nativa
swift test                     # Esegue la suite di test XCTest
```

## Struttura del Codice Swift

Il codice Swift è organizzato in moduli SPM (Swift Package Manager) all'interno di `Sources/`:

- **`LettoreApp`**: Modulo principale. Usa `@main` in `LettoreApp.swift` e lancia il `LettoreStudioView`.
- **`LettoreCore`**: Logica pura senza dipendenze di sistema. Modelli (annotati con `@Observable`), `SentenceChunker` e `TextNormalizer`.
- **`LettoreEngine`**: Pipeline Audio nativa.
  - `AudioEngineService` gestisce la riproduzione del WAV tramite `AVAudioPlayer` (garantisce il funzionamento anche quando l'app viene avviata da terminale CLI) e si occupa del metering (estrazione decibel) per l'onda visiva a 20Hz.
  - `PlaybackCoordinator` orchestra la coda (chunk) e chiama il server TTS locale.
- **`LettoreSystem`**: Interazioni col sistema operativo.
  - `AXCaptureService` utilizza le Accessibility API (`AXUIElement`) per intercettare il testo da qualsiasi applicazione.
  - `VisionOCRService` cattura schermate locali e legge il testo con il framework Apple Vision (offline).
- **`LettoreUI`**: Componenti SwiftUI.
  - `FloatingPillView` crea l'animazione morphing stile Dynamic Island.

## Comandi Python (Backend)

Il server Python vive nella cartella `backend/`:

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python main.py
```

## Gotchas & Convenzioni

- I messaggi di commit, le PR e i documenti di design (in `dev-docs/`) sono **sempre in italiano**.
- **Observation Framework:** Usa `@Observable` di Swift 6 al posto del vecchio `ObservableObject`. Nessun `@Published` è necessario all'interno delle classi `@Observable`.
- **Memoria Audio:** `AVAudioEngine` è stato dismesso in favore di `AVAudioPlayer` perché `AVAudioEngine` restituisce un errore irreversibile di sistema (`-10868`) quando l'applicazione viene lanciata tramite il comando CLI `swift run`, mancando del layer di inizializzazione standard GUI di Apple.
- Le callback asincrone che interagiscono con la UI devono sempre usare `MainActor.run { ... }` o `Task { @MainActor in ... }`.
- Mantieni i documenti in `dev-docs/` sempre aggiornati. Essi rappresentano la singola fonte di verità strategica del progetto.
