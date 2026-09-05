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
