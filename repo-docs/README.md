# Lettore Native — Guida del Repository (Seed Mode)

## Project Brief

Lettore Native è un'applicazione desktop per macOS (scritta in Swift 6 con SwiftUI e AppKit) concepita per assistere la lettura vocale ad alta fedeltà con particolare attenzione all'accessibilità, alla dislessia e alla neurodivergenza (DSA / ADHD).

- **Evidence status**: `Confirmed`. Il file [AGENTS.md](../AGENTS.md) e [ROADMAP.md](../ROADMAP.md) definiscono l'architettura nativa per macOS e gli obiettivi di abbattimento del carico cognitivo durante la lettura.
- **Obiettivo**: Fornire una sintesi vocale offline, privata e reattiva (<250ms cold boot, <90MB RAM) capace di catturare il testo da qualsiasi applicazione macOS (tramite Accessibility API e OCR Vision) e riprodurlo tramite un runtime vocale neurale locale.

## Current Repo State

Lo stato attuale del repository riflette il completamento della Fase 3.0 (transizione a client nativo macOS) affiancato da un backend locale Python:

- `Confirmed`: **Applicazione Swift macOS** (`Sources/`):
  - `Sources/LettoreApp`: Entrypoint applicativo con interfaccia SwiftUI principale.
  - `Sources/LettoreCore`: Logica di dominio pura con modelli `@Observable`, segmentazione semantica (`SentenceChunker`), normalizzazione del testo (`TextNormalizer`) e primitive della lettura continua (`ContinuousTextSource`, `DocumentNoiseFilter`, `SentenceCarryBuffer`, `PreferencesStore`).
  - `Sources/LettoreEngine`: Pipeline audio basata su `AVAudioPlayer` (`AudioEngineService`) con metering dei decibel a 20Hz, orchestratore di riproduzione asincrono a chunk (`PlaybackCoordinator`) e controller della sessione continua (`ContinuousReadingController`).
  - `Sources/LettoreSystem`: Integrazione a basso livello con macOS tramite Accessibility API (`AXCaptureService`) per la cattura del testo selezionato e il paging documentale (`AXCaptureService+Continuous`), più Apple Vision (`VisionOCRService`) per l'estrazione ottica del testo.
  - `Sources/LettoreUI`: Componenti visivi floating e morphing elastico stile Dynamic Island (`FloatingPillView`, `DynamicNotchView`, `SuperAccessibleView`), con card e banner della lettura continua nello Studio.
- `Confirmed`: **Lettura continua DSA-11** — la selezione o il cursore è il punto di partenza; la lettura prosegue nel documento con paging automatico AX-first, fallback PageDown solo con l'app di origine in primo piano, filtro rumore leggero e limite di 200.000 caratteri. Il pulsante "Leggi da qui" dello Studio usa il PID dell'ultima app esterna per non catturare Lettore stesso. Validata empiricamente su TextEdit, Safari e VS Code; Preview/PDF resta best effort e Word non è installato. Dettagli e report in `.scratch/dsa-11-lettura-continua/`.
- `Confirmed`: **Backend TTS Python Sidecar** (`backend/`):
  - Server FastAPI locale in ascolto sulla porta `7788` (`main.py`, `tts_manager.py`) per la generazione audio ONNX tramite modello Supertonic.
  - Provider ibrido di default: CoreML solo per `vector_estimator`, CPU per le altre sessioni ONNX; profili `hybrid`/`cpu`/`coreml`/`auto` via `LETTORE_TTS_PROVIDER` e thread configurabili (`LETTORE_TTS_INTRA_THREADS`, default 4). Dettagli e misure in [ADR-009](../docs/adr/009-provider-ibrido-e-thread-tts.md).
- `Confirmed`: **Configurazione Agenti e Customizzazioni** (`.agents/`):
  - Catalogo di skill registrate in `.agents/skills.json` suddivise per categorie tematiche (audio, code quality, documentazione, ponytail, UI/UX, workflow).

## Decided Constraints

I vincoli tecnici consolidati per lo sviluppo sono documentati in [AGENTS.md](../AGENTS.md):

1. **Architettura 100% Nativa macOS**: Abbandono di runtime ibridi (Tauri/web view) per garantire footprint di memoria inferiore a 80-90MB e latenze minime.
2. **Swift 6 & Observation Framework**: Utilizzo della macro `@Observable` al posto di `ObservableObject` / `@Published`.
3. **Audio Engine via `AVAudioPlayer`**: Scelta obbligata rispetto ad `AVAudioEngine` per prevenire l'errore di sistema `-10868` quando l'applicazione viene avviata via CLI tramite `swift run`.
4. **Thread Safety per la UI**: Tutte le interazioni asincrone con la grafica devono passare esplicitamente dal MainActor (`@MainActor` / `MainActor.run`).
5. **Privacy & Offline First**: Nessun dato o testo catturato a schermo deve transitare su server cloud esterni.

## Primary Workflow

Il flusso primario per l'interazione end-to-end è:

- `Implemented (validato su TextEdit, Safari e VS Code; Preview/PDF best effort)`: **Lettura continua da selezione o cursore (DSA-11)**:
  1. L'utente seleziona una parola o posiziona il cursore in un testo in qualsiasi app macOS (Safari, TextEdit, VS Code, Word, Anteprima). Il pulsante "Leggi da qui" dello Studio usa il PID dell'ultima app esterna, perché al clic lo Studio è in primo piano.
  2. `AXCaptureService` risolve l'ancora: valore + range dell'elemento focalizzato, text marker del documento (Safari), valore di un antenato, DFS della viewport scorrevole, oppure fallback al solo elemento focalizzato con avviso.
  3. `DocumentNoiseFilter` pulisce la cattura documentale (numeri di pagina, header/footer ripetuti, de-hyphenation); `TextNormalizer` normalizza il testo.
  4. `SentenceChunker` divide i primi ~8.000 caratteri, tagliati su un confine di frase; il resto viene chunkato in background e `SentenceCarryBuffer` evita frasi spezzate tra pagine.
  5. `ContinuousReadingController` e `PlaybackCoordinator` alimentano la coda; quando restano ≤3 chunk chiedono la pagina successiva e attendono se la coda finisce durante il caricamento.
  6. `AXCaptureService+Continuous` avanza la viewport con azioni/valore AX e, solo se l'app è frontmost, con PageDown; `ScrollEndState` distingue fine reale da scroll bar senza range. Il focus non viene spostato.
  7. `AudioEngineService` riproduce i chunk WAV con metering visivo a 20Hz senza pause percettibili.

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
- `Unknown`: **Comportamento AX di Word e Preview**: Safari e VS Code sono stati validati (ancore marker/value corrette); restano da verificare Word (non installato), Preview/PDF (nessuna ancora AX) e i documenti realmente virtualizzati di Safari. La sonda è tracciata in `.scratch/dsa-11-lettura-continua/issues/01-sonda-ax-app-target.md`.
- `Unknown`: **Permessi Accessibility (TCC) in modalità sandbox**: Verificare le autorizzazioni necessarie per la cattura `AXUIElement` quando l'app verrà pacchettizzata con App Sandbox abilitata.
- `Planned`: **Comandi di verifica del build e test**:
  - Swift Build: `swift build`
  - Swift Test: `swift test`
  - Validatore Repo-Docs: `python3 .agents/skills/documentation/repo-docs/validate_repo_docs.py repo-docs/ --seed --repo-root .`
