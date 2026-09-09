# Stato delle Feature & Capacità del Motore TTS

> **Nota di aggiornamento**: Questo file documenta in modo rigoroso e verificabile:
> 1. **Feature attualmente implementate** nel codice (verificate e attive nel codebase).
> 2. **Capacità native del motore TTS in uso** (Supertonic 3 via ONNX Runtime) sfruttabili nativamente o pronte per essere esposte.
>
> *Questo file va mantenuto aggiornato ad ogni avanzamento o refactoring.*

---

## 1. Feature Attualmente Implementate (Codebase Reale)

### Cattura Testo & Scorciatoie Globali
- [x] **Cattura nativa macOS via Accessibility API (`AXUIElement`)**:
  - Implementata in Rust (`src-tauri/src/plugins/accessibility/macos.rs`).
  - Cattura la selezione del testo dall'applicazione in primo piano.
  - Fallback automatico via simulazione Cmd+C e clipboard se l'app non espone `kAXSelectedTextAttribute`.
- [x] **"Leggi da qui" (Cattura da cursore e selezione)**:
  - **Nella box di testo locale**: rileva la posizione del cursore o della parola/frase evidenziata, espande l'offset all'inizio della parola corrente per non spezzarla e sintetizza fluidamente da quel punto fino al termine del testo presente nella box (`extractTextFromCursorOffset`).
  - **Nelle applicazioni esterne**: estrazione via `src-tauri/src/plugins/accessibility/macos.rs` (`read_from_cursor_from_pid`) interrogando `kAXSelectedTextRangeAttribute` e `kAXValueAttribute`, con fallback automatico a simulazione tastiera (`Shift + Option + Down` / `Shift + Cmd + Down` + `Cmd + C`).
  - Comando Tauri dedicato `capture_from_cursor`, scorciatoia globale dedicata (default `CommandOrControl+Shift+C`) e pulsante "📍 Leggi da qui" nella toolbar di cattura.
- [x] **Fallback Cross-Platform (Stato attuale)**:
  - Windows: fallback clipboard implementato (`src-tauri/src/plugins/accessibility/windows.rs`).
  - Linux: fallback clipboard implementato (`src-tauri/src/plugins/accessibility/linux.rs`).
### Backend & API (FastAPI + Sidecar)
- [x] **Lifecycle Sidecar & Auto-Recovery**:
  - Rust gestisce il processo Python FastAPI (prima cerca il binario sidecar PyInstaller, poi fallback a `.venv`). Polling `/v1/status` fino a 60s all'avvio.
- [x] **Modularità Motore Vocale (Plug-and-Play TTS)**:
  - Astrazione `BaseTTSEngine` in `backend/engines/base.py` con metodi astratti per sample rate, nomi voci, lingue, caricamento e sintesi.
  - Driver `SupertonicONNXEngine` in `backend/engines/onnx_engine.py` che incapsula il runtime ONNX e l'accelerazione CoreML (ADR-004).
  - Factory dinamico `create_engine` in `backend/engines/factory.py` e configurazione tramite campo `engine` in `BackendConfig` (`LETTORE_ENGINE`).
  - `TTSManager` in `backend/tts_manager.py` completamente disaccoppiato dal runtime ONNX specifico.
- [x] **TTS Engine Singleton & Thread-safety**:
  - `TTSManager` carica il modello in background all'avvio e serializza l'inferenza CPU/CoreML con lock thread-safe (ADR-002).
- [x] **Accelerazione Hardware macOS (CoreML)**:
  - Patch dinamica in `backend/engines/onnx_engine.py` con sottoclasse di `ort.InferenceSession` per agganciare automaticamente `CoreMLExecutionProvider` prima del fallback CPU.
- [x] **Normalizzatore Testo Italiano & Filtro Esclusioni**:
  - Modulo `TextNormalizer` in `backend/textnorm/normalizer.py` con 30 regole ad alta frequenza per la lingua italiana (abbreviazioni professionali/documentali, importi monetari in euro/dollari/sterline, URL/email, orari, ordinali, percentuali, unità di misura metriche).
  - Filtro esclusioni per eliminare stringhe blacklistate (disclaimer di riservatezza, firme email, "Inviato da iPhone") ripulendo la punteggiatura residua.
  - Applicazione trasparente su `/v1/queue` e `/v1/tts`.
- [x] **Anteprima Voce Istantanea (Voice Preview)**:
  - Endpoint `GET /v1/tts/preview?voice=...&lang=...` con frase fissa breve e `steps=5` per latenza minima (<150ms).
  - Pulsante anteprima ▶️ nel selettore voci e su ogni riga del gestore voci.
- [x] **Smart Chunking del Testo**:
  - Segmentazione basata su punteggiatura e limiti di caratteri (min 80, max 240 char) in `backend/chunking.py`.
- [x] **Rilevamento Automatico della Lingua**:
  - Integrazione `lingua-py` con soglia di confidenza (0.35) in `backend/language_detect.py` (`lang="auto"` con fallback `"na"`).
- [x] **Cache LRU delle Sintesi TTS**:
  - Cache in memoria (fino a 64 item) con chiave `(testo, lingua, voce, steps, speed)` per eliminare tempi di ri-sintesi su frasi identiche.
- [x] **Gestione Coda Audio**:
  - Coda FIFO asincrona in `backend/queue_manager.py` con stati (`pending`, `synthesizing`, `synthesized`, `playing`, `done`, `error`) ed endpoint REST per enqueue, pop, status e clear.
- [x] **Registro Voci (`VoiceRegistry`)**:
  - Persistenza in `voices.json` (`~/.config/lettore/voices.json`), mapping nomi amichevoli italiani (es. M1 → Marco, F1 → Giulia) e filtro lingue compatibili.
### Interfaccia Utente & Audio Player (Vite + Vanilla ES Modules)
- [x] **Player Web Audio API Low-Latency**:
  - Decodifica chunk audio WAV su `AudioContext` nativo del browser webview (`ui/src/renderer/player.js`).
  - Pipeline di riproduzione continua (pre-fetching del chunk successivo mentre il chunk corrente è in esecuzione).
  - Gestione anti-gara su `source.stop()`, `onended` e `disconnect()` nodi audio.
- [x] **Player Minimale a Barra Singola (Floating Pill con Dissolvenza)**:
  - Modalità compatta a barra singola fluttuante (380x48 px logici) con geometria arrotondata (border-radius 24px) e glassmorphism scuro (`backdrop-filter: blur(16px)`).
  - Onde vocali animate `#audio-wave` reattive alla riproduzione.
  - Effetto dissolvenza trasparente automatica (`.pill-fade`, opacity 0.28) dopo 2.5s di inattività allo stop o fine riproduzione, con ripristino immediato a opacità 1.0 al passaggio del mouse o click.
- [x] **Megafono Widget & Control Hub Illustrato (Titlebar & System Tray)**:
  - Silhouette vettoriale autentica a megafono (cono, impugnatura, onde audio anteriori) posizionata in `.brand-area` indipendente dall'area di drag (`-webkit-app-region: no-drag; pointer-events: auto !important`).
  - Popover rapido `#megaphone-popover` completamente ridisegnato a Command Hub illustrato: header con live status indicator ("Pronto", "In Lettura", "In Pausa"), tessere interattive ricche con icone bicolore (Play/Pausa con chip scorciatoia, Leggi da Cursore, Peaker a Riquadri, Modalità Pillola) e footer con tasto Stop dedicato.
  - Voci dedicate nel menu System Tray ("Pillola Fluttuante", "Leggi da qui (Cursore)", "Play / Pausa", "Stop").
- [x] **Universal Reading Layer (Identificazione e Navigazione Semantica a Blocchi)**:
  - Pipeline di acquisizione a fallback a 3 livelli ordinata per efficienza:
    1. **Livello 1 (macOS Accessibility AX)**: estrazione nativa Rust dell'albero della finestra attiva (`AXHeading`, `AXParagraph`, `AXStaticText`, `AXTextArea`, `AXList`, ecc., testo e coordinate bounding box).
    2. **Livello 2 (Clipboard Fallback)**: estrazione del testo selezionato per app non pienamente compatibili con l'albero AX.
    3. **Livello 3 (macOS Apple Vision OCR Offline)**: screenshot finestra tramite `screencapture` e riconoscimento testuale offline ad alta accuratezza senza connessione internet.
  - Modulo Layout Analysis deterministico in Python (`backend/blocks/layout_analyzer.py`) che classifica i blocchi (`heading`, `paragraph`, `list_item`, `quote`, `code`), calcola le parole e applica la normalizzazione fonetica pre-sintesi (`TextNormalizer`).
  - Endpoint REST FastAPI dedicati `/v1/blocks/analyze` e `/v1/blocks/ocr`.
  - Interfaccia overlay `#text-peaker-overlay` arricchita nel **Universal Reading Layer**: badge applicazione sorgente, schede cromatiche per ogni tipo semantico, pulsanti rapidi di scansione (⚡ App AX, 📋 Appunti, 📷 OCR Schermo).
  - Navigazione tastiera/VoiceOver completa: frecce `↓`/`↑` per selezionare i blocchi con auto-scroll, `Cmd+T` per saltare al prossimo titolo, `Cmd+P` per saltare al prossimo paragrafo, `Invio`/`Spazio` per ascolto immediato.
  - Live region ARIA `aria-live="polite"` per annunci vocali dettagliati a persone non vedenti.
  - Pieno supporto ai 4 profili di inclusione (Dislessia, Analfabetismo, Cecità, Ipovisione).

- [x] **Finestra Desktop Frameless Always-on-Top**:
  - Finestra configurata con `alwaysOnTop: true`, trasparenze e drag region nativo (`data-tauri-drag-region`).
- [x] **Pannello Impostazioni & Persistenza**:
  - Selezione voce, regolazione velocità (`speed`), regolazione passi di qualità (`steps`), volume e scelta lingua (o Auto).
  - Toggle normalizzazione testo e configurazione stringhe escluse.
  - Rimappatura delle scorciatoie globali da tastiera (cattura, cursore, play, pausa, stop).
  - Persistenza impostazioni su file JSON (`settings.json`) nel backend/host Tauri e sincronizzazione automatica su `/v1/config`.
---

## 2. Feature Native di Supertonic 3 (Sfruttabili dalla Libreria in Uso)

La libreria in uso è **`supertonic`** (modello **Supertonic 3** basato su ONNX Runtime, ~99M parametri, ~400MB).  
Di seguito le capacità native fornite dalla libreria e come possono essere sfruttate nel progetto:

### A. Controllo Fine della Sintesi (Steps & Velocità)
- **`total_steps` (Qualità vs Latenza)**:
  - La libreria permette di variare i passi di denoising da `1` a `20+`:
    - `steps=5–6`: Sintesi ultra-rapida / real-time streaming (<150ms TTFB).
    - `steps=8`: Default bilanciato (qualità naturale / reattività).
    - `steps=12–16`: Massima fedeltà sonora per esportazione tracce audio/libri.
- **`speed` continuo**:
  - Supporto nativo per fattore di velocità continuo (`0.5x` – `2.5x`) senza alterazione dell'intonazione (nessun effetto pitch-shift o chipmunk).

### B. Voci Built-in & Cloni Personalizzati (`Voice Styles`)
- **10 Voci Base Pre-addestrate**:
  - 5 stili maschili (`M1`, `M2`, `M3`, `M4`, `M5`) e 5 stili femminili (`F1`, `F2`, `F3`, `F4`, `F5`) inclusi nel checkpoint ONNX.
- **Supporto Voci Custom (`get_voice_style_from_path`)**:
  - La libreria supporta nativamente il caricamento di stili vocali da vettori/embedding JSON generati con Supertone Voice Builder.
  - Può caricare al volo file `.json` da `~/.cache/supertonic3/custom_styles/` senza riavviare o riaddestrare il modello.
- **Voice Blending / Stili Multipli (Sfruttabile)**:
  - Poiché lo stile vocale è un tensore numerico (voice vector/latente), è possibile matematicamente interpolare due stili (es. 70% F1 + 30% F2) per generare nuove voci ibride uniche direttamente su ONNX.

### C. Supporto Multilingue (31 Lingue + Fallback Neutro)
- **31 Lingue Ufficiali con token dedicato**:
  - Supportate nativamente: `it` (Italiano), `en` (Inglese), `es` (Spagnolo), `fr` (Francese), `de` (Tedesco), `pt` (Portoghese), `ru` (Russo), `zh`/`ja`/`ko` (Asiatiche), `ar`, `el`, `nl`, `pl`, `tr`, `uk`, `hi`, ecc.
- **Fallback `na` (Language-Agnostic)**:
  - La libreria supporta il token lingua `"na"` per sintesi cross-lingue o testi misti, permettendo alla voce di pronunciare parole straniere con fonetica standard senza fallire.

### D. Streaming Audio & Bassa Latenza (Chunk-by-Chunk)
- **Generazione a blocchi indipendenti**:
  - `synthesize()` accetta frasi o porzioni di testo singole restituendo l'array numpy/audio e la durata esatta in secondi.
  - Sfruttabile per una pipeline di streaming predittivo (sintetizza la prima frase in ~100ms, poi procede in background per le successive).

### E. Accelerazione Esecuzione ONNX Runtime
- **Compatibilità con Execution Providers multipli**:
  - `CPUExecutionProvider` (universale, ottimizzato per istruzioni AVX/ARM NEON).
  - `CoreMLExecutionProvider` (macOS Apple Silicon via Neural Engine / GPU).
  - `DmlExecutionProvider` (DirectML per GPU Windows AMD/Intel/NVIDIA - sfruttabile con `onnxruntime-directml`).
  - `CUDAExecutionProvider` / `TensorrtExecutionProvider` (sfruttabile per ambienti con schede NVIDIA).

---

## 3. Architettura 100% Nativa macOS (Branch `rewrite/100-native`)

Sul branch `rewrite/100-native` è stata implementata e collaudata la nuova architettura Swift 6 nativa priva di runtime Python e WebKit:

- [x] **Package Swift Modulare (`native/Lettore`)**:
  - `LettoreCore`: Modelli `@Observable`, `ReadingBlock`, `ReadingChunk`, `VoiceProfile`, `PlaybackState`, `AccessibilityProfile`.
  - `SentenceChunker`: Segmentazione intelligente tramite `NaturalLanguage.framework` (`NLTokenizer`) unita a disambiguazione regole ed abbreviazioni italiane (`Dott.`, `Sig.ra`, `Prof.`, ecc.).
  - `TextNormalizer`: Normalizzatore fonetico deterministico Swift con 30 regole (valute `12,50 €`, percentuali `20%`, date, link `https://...`, email, rimozione blacklist esclusioni).
  - `LettoreEngine`:
    - `AudioEngineService`: Pipeline nativa `AVAudioEngine` + `AVAudioPlayerNode` + `AVAudioUnitTimePitch` (0.5x–3.0x pitch-preserved) e `installTap` real-time per livelli FFT a 60fps.
    - `TTSPipelineProtocol` & `MockTTSPipeline`: Generazione buffer audio PCM 24 kHz Float32 per test e sviluppo offline.
  - `LettoreSystem`:
    - `AXCaptureService`: Estrazione testo via `AXUIElement` nativo macOS con fallback clipboard tastiera `CGEvent`.
    - `VisionOCRService`: Riconoscimento testo offline e ad alta precisione tramite Apple `Vision.framework` (`VNRecognizeTextRequest`).
  - `LettoreUI`:
    - `FloatingPillView`: Pillola fluttuante con morph elastico a hover (`.spring(response: 0.35, dampingFraction: 0.75)`): onda sonora a riposo -> espansione controlli, scrubber a 4 livelli e slider velocità.
    - `DynamicNotchView`: HUD espandibile integrato nella tacca hardware dei MacBook Pro/Air.
    - `SuperAccessibleView`: Visualizzazione ad altissimo contrasto WCAG AAA (14.2:1) con font ad alta leggibilità e pista di lettura visiva per ipovedenti.
  - `LettoreApp`: Entrypoint `App` SwiftUI con `WindowGroup` e `MenuBarExtra` per la menubar macOS.
  - `LettoreCoreTests`: Suite di 9 test unitari automatizzati (`LettoreCoreTests`), esecuzione in 0.17s con 100% pass rate.

