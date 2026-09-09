# Registro Decisioni Architetturali (ADR — Architecture Decision Records)

Questo documento traccia in modo cronologico e immutabile le scelte tecniche vincolanti di **Lettore**.  
Serve a prevenire regressioni, refactoring errati e rimozione involontaria di salvaguardie critiche.

---

## Regole di Formattazione per Nuove Voci

Ogni decisione deve seguire tassativamente questa struttura:

```markdown
## [ADR-NUMERO] Titolo Decisione Sintetico (Data YYYY-MM-DD)
- **Stato**: Accettata | Superata (da ADR-X) | Proposta
- **Contesto & Problema**: Qual era l'attrito o il vincolo tecnico.
- **Decisione Presa**: Cosa si è scelto di implementare in modo concreto.
- **Alternative Scartate**: Opzioni valutate e perché sono state rifiutate.
- **Conseguenze & Vincoli Intoccabili**: Cosa NON deve essere modificato/semplificato in futuro per non rompere il sistema.
```

---

## [ADR-001] Cattura del Testo Nativamente in Rust tramite AXUIElement (2026-09-03)
- **Stato**: Accettata
- **Contesto & Problema**: Il backend Python richiedeva dipendenze OS-specifiche (`pyperclip`, moduli nativi) per interagire con il sistema operativo, rendendo fragile il setup e la portabilità.
- **Decisione Presa**: Spostare l'intera cattura del testo a monte nel processo host Tauri (Rust) tramite le API di Accessibilità native di macOS (`AXUIElement`), con fallback automatico a simulazione tastiera `Cmd+C` e clipboard Rust. Rimosse tutte le dipendenze Python di clipboard.
- **Alternative Scartate**: Cattura in Python (`pyperclip`, script `osascript`/AppKit): lenta, incline a fallimenti di permessi e dipendente da librerie esterne.
- **Conseguenze & Vincoli Intoccabili**: Il backend Python riceve il testo già catturato via HTTP; non reintrodurre librerie di cattura o clipboard nel runtime Python.

---

## [ADR-002] Serializzazione dell'Inferenza ONNX con Lock Sincrono (2026-09-03)
- **Stato**: Accettata
- **Contesto & Problema**: `onnxruntime` non è thread-safe per sessioni di inferenza condivise su CPU o CoreML quando chiamato simultaneamente da coroutine asincrone o thread multipli.
- **Decisione Presa**: Mantenere `TTSManager` come singleton in `backend/tts_manager.py` con una singola istanza caricata in RAM e proteggere ogni invocazione di `synthesize()` con `threading.Lock()` sincrono.
- **Alternative Scartate**: Sessioni multiple di ONNX Runtime in parallelo (consumo insostenibile di RAM, ~400MB per istanza) o chiamate async non protette (crash di memoria o segfault C++).
- **Conseguenze & Vincoli Intoccabili**: Non rimuovere mai `with self._lock:` nel metodo di sintesi e non istanziare il modello dentro route async di FastAPI.

---

## [ADR-003] Gestione Anti-Race della Coda Audio Web Audio API (2026-09-03)
- **Stato**: Accettata
- **Contesto & Problema**: La riproduzione sequenziale a chunk su Web Audio API soffre di race conditions: chiamare `.stop()` su un `AudioBufferSourceNode` scatena l'evento `.onended`, che a sua volta chiama `queue.next()`, provocando doppi avanzamenti, sovrapposizioni audio o salti di chunk.
- **Decisione Presa**: In `ui/src/renderer/player.js`:
  1. Azzerare sempre `source.onended = null` prima di invocare `source.stop()`.
  2. Disconnettere esplicitamente i nodi audio con `source.disconnect()`.
  3. Mantenere una guardia booleana anti-rientranza (`isAdvancing`) su `advance()` e `next()`.
- **Alternative Scartate**: Affidarsi alla sola gestione automatica del garbage collector o all'evento nativo `ended` senza rimozione preventiva del listener.
- **Conseguenze & Vincoli Intoccabili**: Non semplificare il ciclo di vita del player audio rimuovendo l'azzeramento del callback prima di fermare la sorgente.

---

## [ADR-004] Patch Dinamica Hardware Acceleration CoreML (2026-09-03)
- **Stato**: Accettata
- **Contesto & Problema**: La libreria `supertonic` istanzia internamente `ort.InferenceSession` richiedendo che sia un tipo (`isinstance(session, ort.InferenceSession)`). Sostituire l'istanza con una funzione wrapper fallisce i controlli di tipo.
- **Decisione Presa**: Creare una sottoclasse formale `_AcceleratedSession(ort.InferenceSession)` che inietta i provider rilevati (`CoreMLExecutionProvider`, poi `CPUExecutionProvider`) prima di passare gli argomenti al costruttore genitore, assegnandola a `ort.InferenceSession`.
- **Alternative Scartate**: Monkey-patching con funzione (fallisce l'istanziazione in `supertonic`) o fork della libreria esterna (overhead di manutenzione).
- **Conseguenze & Vincoli Intoccabili**: Se si aggiorna o si fa refactor dell'import di `onnxruntime`, preservare l'ereditarietà di classe per non disabilitare CoreML.

---

## [ADR-005] Astrazione Modulare BaseTTSEngine per Motori Vocali Plug-and-Play (2026-09-04)
- **Stato**: Accettata
- **Contesto & Problema**: L'accoppiamento diretto di `TTSManager` con l'implementazione interna della libreria `supertonic` impediva la sostituzione o l'affiancamento trasparente di runtime alternativi (es. Piper, Kokoro, Coqui, PyTorch o provider cloud) senza riscrivere router, API o logica applicativa.
- **Decisione Presa**: Definire l'interfaccia astratta `BaseTTSEngine` in `backend/engines/base.py` con contratto uniforme (`sample_rate`, `voice_names`, `supported_languages`, `load()`, `unload()`, `synthesize()`, `discover_custom_voices()`). Incapsulare il runtime Supertonic ONNX in `SupertonicONNXEngine` (`backend/engines/onnx_engine.py`) e istanziarlo tramite il factory `create_engine` guidato da configurazione (`LETTORE_ENGINE`).
- **Alternative Scartate**: Mantenere il codice ONNX direttamente in `TTSManager` con `if/else` per ogni nuovo motore (debito tecnico e violazione Open/Closed Principle).
- **Conseguenze & Vincoli Intoccabili**: L'applicazione e i router devono dipendere unicamente dall'interfaccia `BaseTTSEngine` e da `TTSManager`. Il lock di serializzazione (ADR-002) e la patch CoreML (ADR-004) devono restare rigorosamente attivi all'interno dell'engine ONNX.

---

## [ADR-006] Pipeline di Normalizzazione Fonetica Italiana ed Esclusioni Pre-Sintesi (2026-09-04)
- **Stato**: Accettata
- **Contesto & Problema**: Il modello neurale TTS pronuncia i testi in modo letterale. Sigle, abbreviazioni frequenti (`Dott.`, `Prof.`, `Art.`), importi con valuta (`12.50€`), orari (`14:30`), link (`http://...`) e firme o disclaimer di posta ("Inviato da iPhone") generano un ascolto frammentato, sgradevole o incomprensibile per utenti con disabilità visiva o cognitiva.
- **Decisione Presa**: Implementare `TextNormalizer` in `backend/textnorm/normalizer.py` con una pipeline a due fasi:
  1. `filter_exclusions`: rimozione pulita di stringhe esatte/pattern blacklistati configurati dall'utente, normalizzando punteggiatura orfana o doppi punti.
  2. `normalize_italian`: catena di espansione fonetica deterministica (30 regole ad alta frequenza per la lingua italiana).
  Applicare la normalizzazione a monte della segmentazione (`smart_chunk_text`) e della sintesi vocale su `/v1/queue` e `/v1/tts`.
- **Alternative Scartate**: Normalizzazione demandata al frontend (risulterebbe disallineata rispetto ad esportazioni WAV o chiamate dirette API) oppure affidata a modelli LLM pesanti (latenza e consumo CPU incompatibili con TTS in tempo reale).
- **Conseguenze & Vincoli Intoccabili**: La normalizzazione deve avvenire prima dello smart chunking, affinché le frasi espanse non vengano spezzate erroneamente a metà di un numero o di una valuta.

---

## [ADR-007] Universal Reading Layer con Fallback a 3 Livelli (AX -> Clipboard -> Vision OCR) e Layout Analysis Deterministica (2026-09-05)
- **Stato**: Accettata
- **Contesto & Problema**: Per utenti con dislessia, cecità, ipovisione o ridotta alfabetizzazione, il semplice paradigma "seleziona, copia e ascolta" è insufficiente. Le applicazioni esterne possono esporre il testo tramite Accessibility API, solo tramite clipboard, oppure non esporlo affatto (canvas, PDF scansionati, grafici o app non accessibili). Inoltre, una stringa di testo continua priva di struttura impedisce la navigazione semantica (saltare ai titoli, elenchi, paragrafi o citazioni).
- **Decisione Presa**:
  1. Implementare una pipeline di acquisizione a 3 livelli ordinata per affidabilità e velocità:
     - **Livello 1**: macOS Accessibility (`AXUIElement` in Rust) per estrarre l'albero visivo della finestra target (ruoli `AXHeading`, `AXParagraph`, `AXStaticText`, ecc., testo e coordinate a schermo).
     - **Livello 2**: Fallback su selezione/clipboard per app senza albero AX completo.
     - **Livello 3**: Fallback su screenshot finestra (`screencapture -l`) e riconoscimento OCR offline tramite il framework nativo di macOS **Apple Vision** (`VNRecognizeTextRequest`).
  2. Incapsulare l'analisi del layout in `backend/blocks/layout_analyzer.py`: un algoritmo deterministico locale (100% offline, zero dipendenze LLM pesanti) che raggruppa linee contigue e classifica i blocchi in `heading`, `paragraph`, `list_item`, `quote`, `code`, normalizzandoli con `TextNormalizer`.
  3. Esporre il comando Tauri `capture_universal_blocks` e gli endpoint REST `/v1/blocks/analyze` e `/v1/blocks/ocr`.
  4. Riprogettare l'interfaccia in un **Universal Reading Layer** a schede semantiche navigabili da tastiera (`ArrowDown`/`ArrowUp`, `Cmd+T` per i titoli, `Invio`/`Spazio` per ascoltare) con supporto completo screen reader via live region ARIA e stili calibrati per i 4 profili di accessibilità.
- **Alternative Scartate**: Affidarsi esclusivamente all'OCR (lento ed energivoro se l'app è già accessibile via AX), usare modelli LLM per il layout (latenza di secondi e dipendenze enormi), o limitarsi alla sola visualizzazione interna del testo locale.
---

## [ADR-008] Rewrite 100% Nativo macOS in Swift, AppKit, SwiftUI e AVAudioEngine (2026-09-09)
- **Stato**: Accettata (Branch `rewrite/100-native`)
- **Contesto & Problema**: L'architettura ibrida Tauri 2 + Rust + Python FastAPI sidecar + WebKit JS comporta ~450 MB di consumo RAM, 2.5s di avvio, overhead di serializzazione HTTP/IPC e impossibilità di sfruttare nativamente l'Apple Neural Engine (ANE) e le interazioni pixel-perfect di sistema come il Dynamic Notch hardware e le finestre `.nonactivatingPanel`.
- **Decisione Presa**: Avviare sul branch dedicato `rewrite/100-native` la riprogettazione e riscrittura completa in un'applicazione **100% nativa macOS**:
  1. **Linguaggio & UI**: Swift 6, SwiftUI e AppKit per finestre native (`NotchWindowController`, `FloatingPillController` a molla elastica e `StudioWindowController`).
  2. **Pipeline Audio**: `AVAudioEngine` e `AVAudioPlayerNode` per streaming di campioni PCM a 24 kHz gapless con `AVAudioUnitTimePitch` per velocità a formanti preservate.
  3. **TTS & Inferenza**: Esecuzione locale diretta di Supertonic 3 tramite binding Swift di ONNX Runtime C-API con accelerazione CoreML/Metal (e futuro CoreML puro).
  4. **NLP & Chunking**: `NaturalLanguage.framework` nativo per la segmentazione frasi in sostituzione di `pySBD`.
  5. **Accessibilità di Sistema**: Integrazione diretta con `AXUIElement` e Apple `Vision.framework` senza intermediari.
  Specifiche tecniche dettagliate in [`docs/progettazione-100-native.md`](../docs/progettazione-100-native.md).
- **Alternative Scartate**: Mantenere l'architettura ibrida (troppo pesante per un'utility di lettura continua in background); usare Electron o Flutter (ancora più pesanti e privi di integrazione hardware con la tacca).
- **Conseguenze & Vincoli Intoccabili**: Il rewrite si sviluppa nel branch dedicato `rewrite/100-native` senza rompere il branch principale `main` fino al raggiungimento della parità di feature e dei benchmark di stabilità.


