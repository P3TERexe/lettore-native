# Lettore Native — Specifiche di Progettazione Architetturale 100% Native (macOS)

Documento di progettazione tecnica per la riscrittura completa di **Lettore** in un'applicazione **100% nativa macOS** (Swift 6, SwiftUI, AppKit, AVAudioEngine, ONNX Runtime C-API / CoreML).

---

## 1. Visione & Obiettivi Prestazionali

L'attuale architettura di Lettore si basa su tre runtime eterogenei:
* **Host Rust / Tauri 2** (gestione finestre e scorciatoie)
* **Sidecar Python FastAPI** (segmentazione, inferenza ONNX Supertonic 3, server HTTP su `127.0.0.1:7788`)
* **Frontend WebKit / Vanilla JS** (Web Audio API, player a code, interfaccia DOM)

Sebbene funzionale, questo stack comporta un consumo di memoria di circa 450 MB, tempi di bootstrap di 2-3 secondi e un carico di serializzazione JSON su socket locale.

### Obiettivi della Versione 100% Nativa:
| Metrica | Stack Attuale (Tauri + Python + JS) | Obiettivo Nativo (Swift + AppKit) | Miglioramento |
| :--- | :--- | :--- | :--- |
| **Consumo RAM a Riposo** | ~320 MB | **< 45 MB** | **-85%** |
| **Consumo RAM in Riproduzione** | ~480 MB | **< 120 MB** (modello incluso) | **-75%** |
| **Tempo di Avvio (Cold Start)** | 2.4 - 3.5 s (polling uvicorn) | **< 180 ms** | **15x più veloce** |
| **Latenza First-Chunk (Testo → Voce)** | 300 - 450 ms (IPC HTTP + WebAudio) | **< 60 ms** (in-memory buffer) | **5x più reattivo** |
| **Dimensione Pacchetto App** | ~380 MB (bundle Python + PyInstaller) | **~45 MB** (binario + modelli quantizzati) | **-88%** |
| **Efficienza Energetica** | Carico CPU ~18-25% | **Carico CPU < 3%** (Apple Neural Engine / ANE) | **Massima autonomia batteria** |

---

## 2. Diagramma Architetturale Nativo

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            PRESENTATION LAYER                               │
│  ┌───────────────────────┐ ┌───────────────────────┐ ┌───────────────────┐  │
│  │   Dynamic Notch HUD   │ │  Floating Liquid Pill │ │   Studio Window   │  │
│  │ (NSScreen.auxiliary)  │ │ (Hover Morph Spring)  │ │(Unified Toolbar)  │  │
│  └───────────┬───────────┘ └───────────┬───────────┘ └─────────┬─────────┘  │
│              │                         │                       │            │
│  ┌───────────┴─────────────────────────┴───────────────────────┴─────────┐  │
│  │            Super Accessible Profile (WCAG AAA · 14.2:1)               │  │
│  └─────────────────────────────────────┬─────────────────────────────────┘  │
└────────────────────────────────────────┼────────────────────────────────────┘
                                         │
┌────────────────────────────────────────▼────────────────────────────────────┐
│                        CORE & COORDINATION LAYER                            │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │ AppState (@Observable Central Domain Store)                           │  │
│  └───────────────────────────────────┬───────────────────────────────────┘  │
│                                      │                                      │
│  ┌───────────────────────────────────▼───────────────────────────────────┐  │
│  │ PlaybackCoordinator (Swift Actor · Thread-Safe Audio Queue)            │  │
│  ├───────────────────────────────────┬───────────────────────────────────┤  │
│  │ SentenceChunker (NaturalLanguage) │ TextNormalizer (Swift Regex)      │  │
│  └───────────────────────────────────┴───────────────────────────────────┘  │
└────────────────────────────────────────┼────────────────────────────────────┘
                                         │
┌────────────────────────────────────────▼────────────────────────────────────┐
│                       ENGINE & INFERENCE LAYER                              │
│  ┌─────────────────────────────────────┬─────────────────────────────────┐  │
│  │ SupertonicPipeline (Swift)          │ AudioEngineService (AVAudioEngine)│
│  │ - Unicode Indexer nativo            │ - AVAudioPlayerNode (Streaming) │  │
│  │ - TextEncoder / DP / Vocoder        │ - AVAudioUnitTimePitch (Speed)  │  │
│  │ - ONNX Runtime C-API / CoreML EP    │ - 60fps FFT Tap (Metal Shaders) │  │
│  └─────────────────────────────────────┴─────────────────────────────────┘  │
└────────────────────────────────────────┼────────────────────────────────────┘
                                         │
┌────────────────────────────────────────▼────────────────────────────────────┐
│                       SYSTEM INTEGRATION LAYER                              │
│  ┌─────────────────────────┐ ┌────────────────────────┐ ┌─────────────────┐ │
│  │ AXCaptureService        │ │ VisionOCRService       │ │ GlobalShortcuts │ │
│  │ (AXUIElement + Overlay) │ │ (Apple Vision.framework)│ │(Carbon/NSEvent) │ │
│  └─────────────────────────┘ └────────────────────────┘ └─────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Specifiche Tecniche dei Moduli

### 3.1 Pipeline di Inferenza Vocale (`SupertonicKit`)
Invece del sidecar Python, la sintesi vocale viene eseguita direttamente nel processo Swift.

* **Integrazione ONNX Runtime**:
  * Utilizzo del package Swift ufficiale di ONNX Runtime (`onnxruntime-swift` / binding C).
  * Configurazione della sessione con allocazione zero-copy:
    ```swift
    let sessionOptions = try ORTSessionOptions()
    try sessionOptions.setGraphOptimizationLevel(.all)
    // Abilita CoreML Execution Provider su Apple Silicon (NPU/ANE)
    try sessionOptions.appendExecutionProvider("CoreML", options: ["enable_on_subgraph": "1"])
    ```
* **Gestione dei Modelli**:
  * I quattro componenti di Supertonic 3 (`text_encoder`, `duration_predictor`, `vector_estimator`, `vocoder`) vengono caricati in streaming all'avvio in background (`Task.detached(priority: .userInitiated)`).
* **Voci e Stili**:
  * I vettori di stile vocale (`M1`, `M2`, `F1`, `F2` e profili personalizzati) sono caricati in memoria come struct `VoiceStyle(name: String, language: String, vector: [Float32])`.

---

### 3.2 Pipeline Audio a Bassissima Latenza (`AVAudioEngine`)
Sostituzione di Web Audio API con l'infrastruttura audio nativa di macOS.

* **Grafico dei Nodi**:
  ```
  [AVAudioPlayerNode] ──> [AVAudioUnitTimePitch] ──> [MainMixerNode] ──> [Output]
                                  │
                          (installTap: FFT/RMS) ──> [Metal Waveform Shader]
  ```
* **Regolazione della Velocità**:
  * La velocità (0.5x – 3.0x) viene modulata istantaneamente modificando la proprietà `.rate` di `AVAudioUnitTimePitch`: preserva perfettamente l'altezza tonale (formanti vocali) senza alcuna distorsione.
* **Concatenazione Gapless a Doppio Buffer**:
  * L'actor `PlaybackCoordinator` mantiene un buffer di pre-rendering di 2 frasi. Mentre la frase $N$ è in riproduzione, la frase $N+1$ viene sintetizzata in background e accodata su `AVAudioPlayerNode.scheduleBuffer(...)` con precisione al singolo campione (24 kHz, 32-bit Float).

---

### 3.3 Gestione Finestre & Nuovi Paradigmi UI

#### A. Dynamic Notch HUD (`NotchWindowController`)
* **Classe Base**: `NSPanel` con `styleMask: [.nonactivatingPanel, .borderless]` e `level: .statusBar`.
* **Posizionamento**:
  ```swift
  guard let screen = NSScreen.main else { return }
  let notchRect = screen.auxiliaryTopLeftArea ?? NSRect(x: screen.frame.midX - 100, y: screen.frame.maxY - 36, width: 200, height: 36)
  // Ancoraggio geometrico ai bordi della tacca hardware
  ```
* **Comportamento**: Si allarga morbidamente a sinistra (onda vocale) e a destra (controlli riproduzione) all'avvio della lettura via scorciatoia.

#### B. Floating Liquid Pill con Hover Morph (`FloatingPillController`)
* **Stato Collassato (Ascolto)**: Dimensioni minime (~120×38px). Visualizza solo l'onda vocale che pulsa in tempo reale.
* **Stato Espanso (Hover)**: Al passaggio del puntatore del mouse (rilevato tramite `NSTrackingArea`), la capsula si allarga a ~440px tramite animazione a molla fluida:
  ```swift
  withAnimation(.spring(response: 0.35, dampingFraction: 0.75, blendDuration: 0)) {
      isHovered = true
  }
  ```
  Svela i tasti `↺ 5s`, Play/Pausa con progress ring circolare, `15s ↻`, velocità `1.05×` e salto paragrafi `⏮ // ⏭`.
* **Zero Furto di Focus**: L'utente può cliccare sulla pillola senza che l'applicazione su cui sta lavorando (Safari, Xcode, Word) perda lo stato attivo della finestra.

#### C. Studio Mode Completo (`StudioWindowController`)
* Finestra unificata Sequoia (`.windowToolbarStyle(.unified)`), sidebar nativa con SF Symbols e navigazione a blocchi semantici.

---

### 3.4 Cattura Testo di Sistema (`AXCaptureService`)
* Utilizzo diretto delle API di accessibilità macOS (`ApplicationServices`):
  * `AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute, ...)`
  * `AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextAttribute, ...)`
  * `AXUIElementCopyParameterizedAttributeValue(focusedElement, kAXBoundsForRangeParameterizedAttribute, ...)`
* **Overlay di Evidenziazione Trasparente**:
  * Una finestra trasparente a tutto schermo (`NSWindow` con `backgroundColor = .clear` e `ignoresMouseEvents = true`) disegna un rettangolo ad angoli arrotondati con velatura calda (*Apple Books style*) direttamente sopra il testo dell'app di lettura.

---

## 4. Mappatura File: Stack Attuale vs Architettura Nativa

| Componente Attuale (Tauri/Python/JS) | Modulo Nativo Swift Corrispondente | Ruolo |
| :--- | :--- | :--- |
| `src-tauri/src/main.rs`, `lib.rs` | `LettoreApp/LettoreApp.swift` | Ciclo di vita applicazione e gestione menu |
| `src-tauri/src/plugins/accessibility/` | `LettoreSystem/AXCaptureService.swift` | Cattura selezione e coordinate cursore via AX |
| `backend/api/`, `main.py` | *(Eliminati)* | Sostituiti da chiamate in-memory dirette tra Actor |
| `backend/chunking.py` | `LettoreCore/SentenceChunker.swift` | Segmentazione frasi con `NaturalLanguage.framework` |
| `backend/normalizer.py` | `LettoreCore/TextNormalizer.swift` | Espansione numeri, valute, abbreviazioni |
| `backend/engines/onnx_engine.py` | `LettoreEngine/SupertonicPipeline.swift` | Esecuzione grafi ONNX / CoreML |
| `backend/queue_manager.py` | `LettoreCore/PlaybackCoordinator.swift` | Coda di riproduzione thread-safe |
| `backend/blocks/vision_ocr.py` | `LettoreSystem/VisionOCRService.swift` | OCR offline locale tramite Apple Vision |
| `ui/src/renderer/player.js` | `LettoreEngine/AudioEngineService.swift` | Pipeline audio con `AVAudioEngine` |
| `ui/src/renderer/index.html`, `styles.css` | `LettoreUI/` (SwiftUI Views) | Interfaccia utente nativa Liquid Glass |

---

## 5. Piano di Realizzazione a Fasi (Milestone)

### Fase 1: Progetto Base & Engine Audio Nativo (Completata ✅)
- [x] Creazione del package Swift modulare `Lettore` in `native/Lettore/`.
- [x] Implementazione di `AudioEngineService` con `AVAudioEngine`, `AVAudioUnitTimePitch` (0.5x–3.0x pitch-preserved), streaming di buffer PCM e tap FFT real-time a 60fps.
- [x] Implementazione di `SentenceChunker` nativo con `NaturalLanguage` e disambiguazione euristica per abbreviazioni italiane.
- [x] Implementazione di `TextNormalizer` deterministico Swift (valute, percentuali, link, blacklist esclusioni).
- [x] Implementazione di `MockTTSPipeline` e test unitari automatizzati completi (`LettoreCoreTests`, 9/9 passati in 0.17s).

### Fase 2: Integrazione di Sistema & Accessibility (Completata ✅)
- [x] Implementazione di `AXCaptureService` (attraversamento albero `AXUIElement` e fallback clipboard).
- [x] Implementazione di `VisionOCRService` tramite Apple `Vision.framework` (`VNRecognizeTextRequest`).
- [x] Implementazione di `AppState` centralizzato reattivo con `@Observable`.

### Fase 3: Windowing AppKit & Controller Dynamic Island (Completata ✅)
- [x] Realizzazione di `FloatingPillView` in SwiftUI con morph elastico ad hover (`.spring(response: 0.35, dampingFraction: 0.75)`): solo onda vocale a riposo → espansione a Dynamic Island con scrub a 4 granularità (secondi, parole, paragrafi, capitoli).
- [x] Realizzazione di `DynamicNotchView` per MacBook con ancoraggio alla tacca hardware.
- [x] Realizzazione di `SuperAccessibleView` ad altissimo contrasto WCAG AAA (14.2:1) con reading runway.

### Fase 4: Pipeline Supertonic ONNX / CoreML in Swift (In Corso ⏳)
- [ ] Integrazione libreria ONNX Runtime C-API / CoreML Execution Provider.
- [ ] Porting dell'indexer Unicode e del caricatore dei profili vocali.
- [ ] Sintesi end-to-end Supertonic 3 in-process.

### Fase 5: Studio Mode, Sandboxing & Benchmark (Pianificata 📋)
- [ ] Finestra principale Studio Mode Sequoia.
- [ ] Sandboxing AppKit, firma & notarizzazione macOS.
- [ ] Benchmark comparativi di memoria RAM (<80 MB) e latenza (<60ms) rispetto all'app ibrida.

