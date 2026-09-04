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
- [x] **Scorciatoie globali di sistema**:
  - Registrazione scorciatoia globale di cattura e lettura (default configurabile, es. `CmdOrCtrl+Shift+Space`) gestita in Rust con `shortcuts.rs`.
- [x] **Fallback Cross-Platform (Stato attuale)**:
  - Windows: fallback clipboard implementato (`src-tauri/src/plugins/accessibility/windows.rs`).
  - Linux: fallback clipboard implementato (`src-tauri/src/plugins/accessibility/linux.rs`).

### Backend & API (FastAPI + Sidecar)
- [x] **Lifecycle Sidecar & Auto-Recovery**:
  - Rust gestisce il processo Python FastAPI (prima cerca il binario sidecar PyInstaller, poi fallback a `.venv`). Polling `/v1/status` fino a 60s all'avvio.
- [x] **TTS Engine Singleton & Thread-safety**:
  - `TTSManager` carica il modello in background all'avvio e serializza l'inferenza CPU/CoreML con lock thread-safe.
- [x] **Accelerazione Hardware macOS (CoreML)**:
  - Patch dinamica in `backend/tts_manager.py` con sottoclasse di `ort.InferenceSession` per agganciare automaticamente `CoreMLExecutionProvider` prima del fallback CPU.
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
- [x] **Finestra Desktop Frameless Always-on-Top**:
  - Finestra compatta configurata con `alwaysOnTop: true`, trasparenze e drag region nativo (`data-tauri-drag-region`).
- [x] **System Tray / Menubar**:
  - Icona tray di sistema con menu di stato, controlli di visibilità finestra ed uscita.
- [x] **Pannello Impostazioni & Persistenza**:
  - Selezione voce, regolazione velocità (`speed`), regolazione passi di qualità (`steps`), volume e scelta lingua (o Auto).
  - Persistenza impostazioni sia su file JSON nel backend che su `localStorage` nel frontend.

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
