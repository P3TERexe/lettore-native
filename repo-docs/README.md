# Lettore Native — Guida del Repository (Seed Mode)

## Project Brief

Lettore Native è un'applicazione desktop per macOS (scritta in Swift 6 con SwiftUI e AppKit) concepita per assistere la lettura vocale ad alta fedeltà con particolare attenzione all'accessibilità, alla dislessia e alla neurodivergenza (DSA / ADHD).

- **Evidence status**: `Confirmed`. Il file [AGENTS.md](../AGENTS.md) e [ROADMAP.md](../ROADMAP.md) definiscono l'architettura nativa per macOS e gli obiettivi di abbattimento del carico cognitivo durante la lettura.
- **Obiettivo**: Fornire una sintesi vocale offline, privata e reattiva (<250ms cold boot, <90MB RAM) capace di catturare il testo da qualsiasi applicazione macOS (tramite Accessibility API e OCR Vision) e riprodurlo tramite un runtime vocale neurale locale.

## Current Repo State

Lo stato attuale del repository riflette il completamento della Fase 3.0 (transizione a client nativo macOS) affiancato da un backend locale Python:

- `Confirmed`: **Applicazione Swift macOS** (`Sources/`):
  - `Sources/LettoreApp`: Entrypoint applicativo con interfaccia SwiftUI principale.
  - `Sources/LettoreCore`: Logica di dominio pura con modelli `@Observable`, segmentazione semantica (`SentenceChunker`) e normalizzazione del testo (`TextNormalizer`).
  - `Sources/LettoreEngine`: Pipeline audio basata su `AVAudioPlayer` (`AudioEngineService`) con metering dei decibel a 20Hz e orchestratore di riproduzione asincrono a chunk (`PlaybackCoordinator`).
  - `Sources/LettoreSystem`: Integrazione a basso livello con macOS tramite Accessibility API (`AXCaptureService`) per la cattura del testo selezionato e Apple Vision (`VisionOCRService`) per l'estrazione ottica del testo.
  - `Sources/LettoreUI`: Componenti visivi floating e morphing elastico stile Dynamic Island (`FloatingPillView`, `DynamicNotchView`, `SuperAccessibleView`).
- `Confirmed`: **Backend TTS Python Sidecar** (`backend/`):
  - Server FastAPI locale in ascolto sulla porta `7788` (`main.py`, `tts_manager.py`) per la generazione audio ONNX tramite modello Supertonic.
- `Confirmed`: **Configurazione Agenti e Customizzazioni** (`.agents/`):
  - Catalogo di skill registrate in `.agents/skills.json` suddivise per categorie tematiche (audio, code quality, documentazione, ponytail, UI/UX, workflow).

## Decided Constraints

I vincoli tecnici consolidati per lo sviluppo sono documentati in [AGENTS.md](../AGENTS.md):

1. **Architettura 100% Nativa macOS**: Abbandono di runtime ibridi (Tauri/web view) per garantire footprint di memoria inferiore a 80-90MB e latenze minime.
2. **Swift 6 & Observation Framework**: Utilizzo della macro `@Observable` al posto di `ObservableObject` / `@Published`.
3. **Audio Engine via `AVAudioPlayer`**: Scelta obbligata rispetto ad `AVAudioEngine` per prevenire l'errore di sistema `-10868` quando l'applicazione viene avviata via CLI tramite `swift run`.
4. **Thread Safety per la UI**: Tutte le interazioni asincrone con la grafica devono passare esplicitamente dal MainActor (`@MainActor` / `MainActor.run`).
5. **Privacy & Offline First**: Nessun dato o testo catturato a schermo deve transitare su server cloud esterni.

## Planned First Workflow

Il flusso primario pianificato per l'interazione end-to-end è:

- `Planned`: **Cattura e Sintesi da Cursore (Read-From-Here / DSA-11)**:
  1. L'utente posiziona il cursore su un testo in qualsiasi app macOS (Safari, Anteprima, Word).
  2. `AXCaptureService` estrae il range di testo partendo dalla posizione del cursore.
  3. `TextNormalizer` applica il filtro per citazioni accademiche e formule.
  4. `SentenceChunker` divide il testo in blocchi di frase preservando i confini logici.
  5. `PlaybackCoordinator` invia i chunk al motore TTS e alimenta la coda circolare.
  6. `AudioEngineService` riproduce i chunk WAV con metering visivo a 20Hz senza pause percettibili.

## Next Implementation Steps

Le prossime tappe di sviluppo, tracciate in [ROADMAP.md](../ROADMAP.md), comprendono:

1. `Planned`: **Integrazione C-API ONNX Runtime in Swift (Milestone M4)** — Eliminazione del backend Python a favore di un processo singolo integrato.
2. `Planned`: **Smart Academic Skip (DSA-1)** — Eliminazione delle citazioni autore-anno e riferimenti numerici per ridurre il carico sulla memoria di lavoro.
3. `Planned`: **Pausa Inter-Frase Regolabile (DSA-2)** — Micro-gap configurabile tra le frasi per agevolare l'elaborazione concettuale ad alte velocità di ascolto.
4. `Planned`: **In-App Update Notifier (SYS-UPDATE)** — Controllo automatico leggero e asincrono delle release GitHub per avvisare l'utente di nuovi aggiornamenti.
5. `Planned`: **Espansione Cross-Platform (Fasi 4.0, 4.5, 5.0)** — Estensione dell'esperienza nativa e offline a iOS (SwiftUI / Live Activities), Windows (WinUI 3 / UIA / DirectML), Linux (GTK4 / AT-SPI2 / PipeWire) e Android (Compose / AccessibilityService / Oboe).

## Unknowns and Verification Checks

Elementi in fase di validazione o con vincoli da verificare sul campo:

- `Unknown`: **Consumo di memoria della C-API ONNX Runtime**: Verificare se il runtime ONNX incorporato direttamente in Swift rispetta il vincolo dei <90MB di memoria residente.
- `Unknown`: **Permessi Accessibility (TCC) in modalità sandbox**: Verificare le autorizzazioni necessarie per la cattura `AXUIElement` quando l'app verrà pacchettizzata con App Sandbox abilitata.
- `Planned`: **Comandi di verifica del build e test**:
  - Swift Build: `swift build`
  - Swift Test: `swift test`
  - Validatore Repo-Docs: `python3 .agents/skills/documentation/repo-docs/validate_repo_docs.py repo-docs/ --seed --repo-root .`
