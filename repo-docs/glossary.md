# Glossary

Terminologia tecnica e concetti chiave utilizzati nel repository Lettore Native.

> [!NOTE]
> Il vocabolario di dominio usato dagli agenti vive in [GLOSSARY.md](../GLOSSARY.md) alla root. Questa tabella resta la vista tecnica per i lettori della guida e deve restare allineata.

| Termine | Definizione | Stato |
| --- | --- | --- |
| **AXUIElement** | Elemento dell'Accessibility API di macOS utilizzato per interrogare la gerarchia dell'interfaccia, estrarre il testo selezionato o tracciare la posizione del cursore a schermo. | `Confirmed` |
| **SentenceChunker** | Modulo di segmentazione del testo che identifica i confini naturali delle frasi e delle pause respiratorie prima dell'invio al sintetizzatore vocale. | `Confirmed` |
| **ReadingTextPreparer** | Unico punto in cui il testo catturato diventa chunk: applica filtro rumore, split del prefisso, chunking, mappa UTF-16 e normalizzazione nell'ordine corretto. Usato da testo manuale, selezione, cattura continua e paging. | `Confirmed` |
| **ReadingQueue** | Value type che possiede la coda e i suoi invarianti: indice corrente, append con reindex, advance/rewind/select, progresso a granularità di chunk. | `Confirmed` |
| **ScrollEndClassifier / ViewportTextCollector** | Decisioni pure della cattura AX: classificazione della scroll bar (`atEnd`/`notAtEnd`/`unknown`) e raccolta deduplicata del testo di viewport con ruoli, URL, marker e cap 200.000 caratteri. | `Confirmed` |
| **ReadingCaptureController** | Policy unica della cattura: sceglie selezione o lettura continua, valida il PID dell'app di origine, prepara i chunk e ripiega sulla coda. Non avvia playback né highlight: restituisce un esito all'App/Studio e scrive gli avvisi in `AppState`. | `Confirmed` |
| **CapturedSelection** | Valore di una cattura di selezione (testo, sessione AX, range e PID) con `trimmedText`/`trimmedSourceRange`; vive in `LettoreCore` e sostituisce `AXCaptureResult`. | `Confirmed` |
| **PillGeometry** | Geometria pura della pillola fluttuante: metriche canoniche, ancoraggio del grip, clamp allo schermo e isteresi del docking. Vive in `LettoreCore`; il pannello AppKit applica soltanto i frame calcolati. | `Confirmed` |
| **VoiceSource** | Motore che ha prodotto un audio: `.neural` (Supertonic) o `.system` (voce di sistema). Viaggia negli eventi di `SpeechOutput`; evita il termine generico *engine*. | `Confirmed` |
| **TextNormalizer** | Pipeline di pre-elaborazione del testo per pulire caratteri speciali, abbreviazioni, citazioni e numeri prima della fonetizzazione. | `Confirmed` |
| **PlaybackCoordinator** | Orchestratore della coda e della sessione di riproduzione: paging, callback verso `AppState` e avanzamento dei chunk. Non conosce cache key, HTTP o `AVAudioPlayer`. | `Confirmed` |
| **SpeechOutput** | Output vocale profondo: possiede sintesi, cache L1/L2, prefetch, fallback alla voce di sistema, metering e serializzazione. Espone `play`/`preload`/`cancelAll` e un flusso di eventi `started`/`progress`/`levels`/`finished`/`synthesisFailed` consumato dal coordinatore. | `Confirmed` |
| **Dynamic Island / Floating Pill** | Componente UI fluttuante che visualizza lo stato di riproduzione e le onde sonore in tempo reale a basso impatto visivo. Usa un unico driver geometrico (`resolvedFrame`) con drag manuale e local event monitor, morphing orizzontale/verticale live deciso dal cursore (`resolvedLiveDock`, isteresi 60/130 px) e aggancio ai bordi laterali dello schermo; il cambio di orientamento durante il drag è istantaneo per evitare la sovrapposizione delle due forme. | `Confirmed` |
| **Supertonic** | Modello neurale di sintesi vocale TTS utilizzato per generare flussi audio naturali a bassa latenza. | `Confirmed` |
| **Provider ibrido** | Configurazione ONNX Runtime predefinita che usa CoreML solo per `vector_estimator` e la CPU per le altre sessioni, bilanciando latenza, CPU e RAM. Selezionabile con `LETTORE_TTS_PROVIDER`. | `Confirmed` |
| **Read-From-Here** | Modalità di lettura continua che avvia la riproduzione dalla posizione corrente del cursore fino al termine del testo senza richiedere una selezione manuale preventiva. | `Confirmed` |
| **Smart Academic Skip** | Funzionalità mirata a DSA/neurodivergenza che filtra citazioni bibliografiche tra parentesi e rimandi di note a piè di pagina durante la lettura. | `Planned` |
