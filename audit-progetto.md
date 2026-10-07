# Audit completo e soluzioni per Lettore Native

## Contesto
Richiesta: analizzare tutto il codice del progetto, infrastruttura, interfaccia, ottimizzazione, roadmap e ogni documento di sviluppo; proporre soluzioni senza scrivere codice. Questo file raccoglie l'audit e un ordine operativo di interventi proposti, non autorizza la loro implementazione. L'analisi è statica e in sola lettura: nessun build, test, avvio dell'app o misura prestazionale eseguiti.

## Sintesi: dove investire prima
La base nativa è valida, ma affidabilità del flusso di lettura, parità delle interfacce, distribuzione e documentazione non sono ancora allineate. Non serve una riscrittura generale: serve completare il passaggio al nativo prima di moltiplicare feature e piattaforme.

| Priorità | Problema | Soluzione di maggior valore |
|---|---|---|
| Alta | Stop, skip e nuove catture possono ricevere risultati di sessioni obsolete | Task cancellabili e identità di sessione; un solo coordinatore |
| Alta | Velocità duplicata, fallback italiano e cache con voce precedente | Contratti unici di velocità/lingua/voce e invalidazione del preload |
| Alta | Bassa Visione/Notch non controllano l'intera pipeline; azione «Leggi» non legge | Tutte le superfici usano gli stessi comandi e dati reali |
| Alta | CI Tauri residua e bundle che non include motore neurale | Verifica Swift/Python reale e distribuzione dichiarata correttamente |
| Alta | Funzionalità storiche e target sono presentati come capacità attuali | Matrice implementato/parziale/legacy/pianificato con prove |
| Media | Cache/export/input senza budget coerenti; richieste duplicate | Limiti memoria e lavori, prefetch riusato, export progressivo |
| Media | App utile con mouse ma controlli hover-only e scorciatoie decorative | Tastiera, VoiceOver, feedback e testo regolabile prima degli effetti |
| Successiva | M4, multipiattaforma e tracking parola hanno dipendenze non chiuse | Benchmark e stabilità macOS come gate, non promessa di risparmio automatico |

**Da conservare:** direzione aciclica dei moduli SPM; `@Observable`; servizi AX/Vision actor e su richiesta; `LazyVStack`; AVAudioPlayer con metering già a 20 Hz e invalidazione nei normali stop; fallback Apple; cache backend LRU e inferenza serializzata. Nessun motivo riscontrato per introdurre microservizi, un framework plugin generale o tornare a Tauri.

## Evidenze già verificate
- `Package.swift`: Swift tools 6.0, macOS 14, cinque target applicativi/libreria e `LettoreCoreTests`; nessuna dipendenza Swift esterna dichiarata.
- `Sources/LettoreEngine/PlaybackCoordinator.swift`, `playCurrentChunk()` e `stop()`: la sintesi corrente parte con un `Task` senza handle conservato; `stop()` annulla soltanto `preloadTask`. Una risposta tardiva può quindi avviare audio dopo Stop. Conseguenza inferita dal flusso, non riprodotta a runtime.
- `Sources/LettoreEngine/SupertonicTTSPipeline.swift`, `synthesize(text:voice:speed:)`: invia velocità al backend, limita a 0.7–2.0, invia `steps: 8`; il coordinatore passa nuovamente la velocità al player. Semantica effettiva da incrociare con backend e `AudioEngineService` prima della conclusione.
- `Sources/LettoreApp/LettoreApp.swift`, `setupCaptureLogic(state:)`: una nuova cattura sostituisce la coda, ma avvia il nuovo chunk solo quando lo stato non è `.playing`; normalizzazione e segmentazione avvengono dentro `MainActor.run`.
- `Sources/LettoreCore/AppState.swift`: stato osservabile mutabile dichiarato `@unchecked Sendable`, senza isolamento globale esplicito; preferenze in memoria.
- Inventario root: oltre a Swift/Python sono presenti `website/`, `mockup-native-100/`, `backend_tests/`, `build-app.sh`, `.github/`, `ROADMAP.md` e `dev-docs/roadmap.md`. Tutti inclusi nel perimetro dei lettori delegati. Output generati, dipendenze vendorizzate, cache e binari verranno inventariati, non trattati come sorgente da revisionare riga per riga.

## Copertura dell'audit
Le letture delegate separano sorgenti Swift, backend Python, infrastruttura/test, documenti e sito/prototipi. Inventario finale e limiti di copertura sono riportati nella sezione conclusiva; le prove future non vanno confuse con esecuzioni effettuate in questa sessione.

## Riscontri incrociati: affidabilità, UI, infrastruttura
- **Priorità alta — Stop e sostituzione coda:** conservare e annullare il task della sintesi corrente e associare risultati/callback a una generazione di sessione. Non basta il booleano `isSynthesizing`: una risposta della vecchia sessione può modificare la nuova. Verifica futura: richiesta A pendente, Stop, nuova richiesta B, completamento A → nessun audio o avanzamento attribuito ad A.
- **Priorità alta — velocità:** `AudioEngineService.playWAVData` applica `player.rate` (0.5–2.0) a WAV richiesti con `speed` al backend. La UI Studio offre 0.5–2.5 e quella Bassa Visione fino a 3.0, mentre il client HTTP limita 0.7–2.0. Occorre un'unica semantica e un unico intervallo dichiarato, non clamp nascosti diversi.
- **Priorità alta — profilo accessibile:** `SuperAccessibleView` chiama direttamente `audioEngine.play/pause/stop` senza `PlaybackCoordinator`; mostra paragrafi dimostrativi fissi e scorciatoie testuali senza relativi binding nella vista. Riutilizzare i comandi del coordinatore e i chunk reali; distinguere etichetta di contrasto da certificazione dimostrata.
- **Priorità alta — azione principale:** in `LettoreStudioView.processNewInput()` il pulsante «Segmenta & Leggi» ferma, segmenta e imposta la coda ma non avvia la lettura. Rendere il comportamento conforme al nome; testo vuoto deve lasciare intatta la sessione.
- **Priorità alta — CI:** `.github/workflows/ci.yml` esegue test Python da `tests` anziché `backend_tests`, crea uno stub Tauri e tenta `cargo check` in `src-tauri`; non verifica Swift. Sostituire il job legacy con build/test macOS Swift e correggere discovery Python.
- **Priorità alta — distribuzione:** `build-app.sh` copia soltanto l'eseguibile Swift, firma ad-hoc e dichiara macOS 13.0, mentre `Package.swift` richiede 14.0. Non distribuisce backend/runtime/modelli; non equivale a pacchetto neurale autonomo.
- **Privacy e cattura:** `AXCaptureService.captureViaClipboardFallback` invia Cmd+C e legge il pasteboard senza conservarne/ripristinarne contenuti; ignora cancellazione durante attesa con `try?`. Un eventuale ripristino deve essere condizionato al `changeCount` per non cancellare copie utente intervenute nel frattempo.
- **Prestazioni dichiarate, non misurate:** lo Studio scrive «ANE», «RAM < 45 MB» e «First-Chunk < 60 ms» come testo fisso. Non sono risultati di questo audit; il percorso esaminato usa HTTP verso un processo Python. Occorre misurare processo Swift e backend separatamente e insieme, avvio freddo/caldo e latenza al primo audio.
- **Cache backend già presente:** `TTSManager.synthesize` usa una LRU di 64 elementi con chiave testo/lingua/voce/steps/speed. Migliorare limiti in byte e deduplicazione concorrente, non proporre una seconda cache equivalente.

## Direzione consigliata
Stabilizzare prima il prodotto macOS esistente. Conservare SwiftUI/AppKit, moduli SPM, AVAudioPlayer, fallback Apple e backend Supertonic; non riscrivere il progetto e non iniziare contemporaneamente ONNX in-process, port multipiattaforma e redesign. La modularità va completata usando `TTSPipelineProtocol` e `BaseTTSEngine`, già presenti, non creando un ulteriore framework plugin.

### Ordine degli interventi proposti
1. **Affidabilità e verifica:** ripristinare CI Swift/Python; correggere sessione audio, trasporti UI, velocità, input e fallback. Le correzioni CI e playback sono indipendenti; i test del coordinatore richiedono prima injection tramite `TTSPipelineProtocol` al posto del concreto `SupertonicTTSPipeline`.
2. **Prodotto comprensibile:** unificare comandi Studio/Pillola/Bassa Visione/Notch; distinguere sintesi, riproduzione, errore e motore effettivo; rendere la cattura sicura e l'interfaccia utilizzabile da tastiera.
3. **Backend sostenibile:** lifecycle, readiness, limiti memoria/lavori, precedenza configurazione, correttezza testo e persistenza. Non rimuovere `/queue` o `/blocks` soltanto perché il client Swift non li usa: sono endpoint pubblicati e testati parzialmente; mantenerli fino a una decisione esplicita di dismissione.
4. **Distribuzione coerente:** nell'immediato distinguere bundle client-only da motore neurale esterno; per una release consumer autonoma confezionare e gestire il sidecar prima di promettere installazione completa. Non presentare firma ad-hoc come notarizzazione.
5. **Ottimizzazioni misurate e roadmap:** baseline comparabile prima di migrare ONNX in Swift. Procedere alle feature DSA/cattura solo dopo aver reso attendibile il ciclo cattura → sintesi → ascolto.

## Soluzioni: interfaccia e accessibilità
- **Un solo trasporto.** In `SuperAccessibleView.headerBar`, `DynamicNotchView.body` e `FloatingPillView.handlePlayPause()` eliminare i percorsi diretti al player e usare `PlaybackCoordinator`. La Notch usa persino `rewindChunk()` dietro un'icona avanti: ricollegare avanti/indietro ai comandi di frase. I pulsanti «5s/15s» della pillola oggi saltano frasi: rinominarli «Frase precedente/successiva», senza inventare un seek temporale.
- **Flusso principale semplice.** Conservare Studio come spazio testo, Pillola come telecomando; Notch dichiarata anteprima finché resta una sheet. Un editor multilinea e un'azione «Leggi» sostituiscano l'ambiguità dell'input monoriga. Usare `processNewInput()` come punto UI e un'unica preparazione/commit nel coordinatore; cattura e incolla alimentano lo stesso percorso. Nessun risultato di una preparazione precedente deve sovrascrivere un testo più recente.
- **Bassa Visione reale.** `SuperAccessibleView.readingRunwayArea` deve mostrare precedente/corrente/successivo dalla coda reale, senza paragrafi fissi. Coda vuota → istruzioni per incollare/catturare e ritorno allo Studio. Aggiungere regolazione dimensione testo e spaziatura; non equiparare ambra su nero a conformità AAA dell'intera app.
- **Comandi raggiungibili.** `FloatingPillView` rivela controlli solo con hover o `isPillExpanded`, che non viene impostato nel codice applicativo letto. Aggiungere comando esplicito di espansione e supporto focus/tastiera; etichettare play, frase, lingua, velocità e progresso con nome, valore e stato. Le animazioni devono rispettare Reduce Motion; non applicare automaticamente regole touch iOS a una UI macOS.
- **Scorciatoie vere.** `GlobalShortcutManager.handleKeyEvent` implementa cattura ⌘⇧C e trasporto ⌥P; il banner Studio mostra ⌥C. Rendere descrizioni e binding un'unica fonte, fare di ⌥P Play/Pausa anziché Stop e collegare Spazio/Esc/⌥←/⌥→ ai comandi locali indicati nel profilo accessibile, senza intercettare la digitazione nell'editor.
- **Feedback onesto.** Usare gli stati `.synthesizing` e `.error` già presenti in `PlaybackState`, oggi non sfruttati dal coordinatore. Mostrare voce Apple quando viene usata davvero, backend in caricamento quando non pronto e risultato «nessun testo selezionato» quando AX restituisce nil. Eliminare claim statici ANE/RAM/latenza/certificazione; non sostituirli con nuove cifre non misurate.
- **Layout e preferenze.** Studio e Bassa Visione impongono dark mode, sidebar 320 pt e finestra minima 960×640; proporre sidebar comprimibile, colori semantici e dimensione testo persistente. Conservare l'identità visiva attuale senza rendere glow, monitor live e branding più importanti del testo. Persistenza solo preferenze, non testo catturato per default.
- **Finestre.** `FloatingPillPanelManager.hide()` rimuove il move observer ma `show()` sul panel esistente non lo ripristina: mantenerlo fino al rilascio del panel. Orientamento/docking vanno per finestra, non nello stato condiviso con la pillola incorporata. Applicare always-on-top al riferimento stabile della finestra, non cercandola per titolo.

## Soluzioni: architettura e correttezza
- **Sessione come unica autorità.** `AppState` concentra trasporto, preferenze, finestre, permessi e waveform; isolare stato UI/player su MainActor e lasciare al coordinatore mutazioni di coda/progresso. Togliere `@unchecked Sendable` solo dopo aver espresso l'isolamento corretto, non sostituirlo con lock indiscriminati.
- **Velocità senza doppia trasformazione.** Proposta conservativa per il percorso neurale corrente: sintetizzare a 1.0 e applicare la velocità al player nell'intervallo reale 0.5–2.0; stessa gamma esposta in tutte le viste. Il fallback Apple usa il proprio mapping e applica cambi durante parlato dal chunk successivo, comunicandolo: non interrompere una frase per simulare un controllo live inesistente. Cache/preload includono i soli parametri che cambiano il WAV; invalidazione immediata al cambio voce/lingua.
- **Errori audio distinti dal completamento.** `AudioEngineService.playWAVData` e delegate trattano anche errori/`play()==false` come successo. Propagare risultato distinto e mantenere il chunk fallito recuperabile; avanzare solo dopo completamento valido della sessione corrente. Pulire player/callback anche nel percorso di errore.
- **Fallback nella lingua richiesta.** `NativeSpeechService.speak` cerca un ID Supertonic fra le voci Apple e poi sceglie italiano. Risolvere voce Apple per `voice.language`, mantenendo la preferenza qualitativa già usata; indisponibilità della lingua → errore esplicito, non pronuncia italiana silenziosa. Progresso dei range Apple in UTF-16 diviso per `utf16.count`, non `String.count`.
- **Testo originale e parlato distinti.** Oggi normalizzazione Swift precede quella Python, con regole diverse. Per il client corrente, normalizzare una volta in Swift e inviare `normalize_text: false` a `/v1/tts`; conservare il testo originale destinato alla UI. Rendere le regole Swift dipendenti dalla lingua, applicando prima abbreviazioni specifiche (`Dott.ssa`, `Prof.ssa`) e poi generiche. API Python standalone mantiene la propria normalizzazione, con corpus di equivalenza per i casi condivisi.
- **Normalizzazione backend.** Rilevare lingua prima delle espansioni linguistiche; `auto` non deve attivare preventivamente italiano. In `_normalize_currencies` un decimale rappresenta decimi: `€1,5` deve essere pronunciato come un euro e cinquanta centesimi, non cinque. Esclusioni prima delle trasformazioni anche in `analyze_layout`, preservando indentazione fino alla classificazione codice.
- **Limite chunk effettivo.** `SentenceChunker.splitLongSentence` e `chunking._group_sentences` possono lasciare frasi sopra soglia. Conservare segmentazione semantica e introdurre taglio di emergenza ai confini di parola, poi di carattere quando un token da solo supera il limite. Testare testo senza punteggiatura e URL lunghi; non rompere Unicode. Distinguere chunk di lettura e aggregati export invece di pretendere identiche dimensioni.
- **Cattura affidabile.** Serializzare l'intera transazione clipboard, gestire cancellazione e preservare gli appunti senza sovrascrivere copie concorrenti. Conservare l'ultima applicazione esterna per il pulsante Studio: al click l'app focalizzata può essere Lettore stesso. AX e OCR devono distinguere permesso mancante, nessun testo e errore tecnico; niente tentativi silenziosi su una sorgente diversa.
- **OCR e blocchi non ancora end-to-end.** `VisionOCRService` ha un test, ma nessun callsite applicativo rilevato; i campi blocchi di `AppState` non alimentano un workflow reale. Collegare in un intervento separato cattura display/coordinate → Vision → blocchi ordinati → selezione → coda; preservare bounding box e colonne. Il backend ha già `blocks/`: riutilizzarne il contratto solo dopo aver normalizzato coordinate, perché OCR e AX non usano necessariamente le stesse unità.

## Soluzioni: backend, infrastruttura e risorse
- **Avvio corretto.** `backend/main.py` usa import relativi; comando dalla root: `python -m backend.main`, con ambiente già predisposto. `cd backend; python main.py` del README non fornisce il package context. Il client non avvia il backend: `loadModel()` controlla solo `/v1/status`.
- **Lifecycle.** In `main.lifespan` chiudere ordinatamente il motore con `unload` già disponibile. `TTSManager` deve pubblicare `_engine` solo dopo caricamento riuscito, rendere start/stop idempotenti e permettere un nuovo tentativo dopo errore; oggi mantiene l'istanza fallita e un singolo thread già usato. Readiness deve distinguere caricamento, pronto e fallito; la liveness non deve copiare l'intera coda.
- **Serializzazione, non concorrenza ONNX indiscriminata.** Gli handler FastAPI sono già sincroni `def`: non c'è evidenza di inferenza bloccante dentro `async def`. Conservare il lock di inferenza e dare capacità limitata ai lavori in attesa, con priorità alla lettura corrente rispetto al prefetch. Cancellare attese obsolete; non promettere che interrompere HTTP fermi un'inferenza ONNX già avviata. Health-check deve rimanere disponibile sotto carico.
- **Cache e memoria.** Riutilizzare LRU WAV esistente, aggiungendo un budget in byte e non soltanto 64 elementi; ricontrollare la chiave dopo acquisizione del lock per evitare doppia inferenza su miss concorrente. Nel client promuovere il task preload in corso invece di fare una seconda richiesta identica. Export: scrivere progressivamente su file temporaneo anziché conservare WAV + PCM decodificati + array concatenato; gestire cancellazione ed errori I/O prima di offrire il download.
- **API coerenti.** `QueueManager.remove` deve restituire se l'ID esisteva prima della mutazione: oggi può invertire successo/404. Configurazione: campo esplicito richiesta > runtime > default; `False` e `[]` sono override validi, non campo assente. Validare voci/lingue/velocità contro capacità reali, senza trasformare una voce sconosciuta in M1. `/v1` esiste già: non aggiungere versioning parallelo.
- **Persistenza voci.** `VoiceRegistry` ricarica/modifica/salva dati condivisi senza lock e usa un tmp fisso: serializzare la transazione completa, validare JSON e sostituire atomicamente con temporaneo univoco; errore I/O non deve cancellare catalogo precedente.
- **Privacy locale.** `main.create_app` abilita CORS `*`; API OCR accetta percorsi e gli input non hanno sempre budget dimensionali. Per distribuzione privata: loopback, origini strettamente necessarie e credenziale effimera condivisa con il client; validare risorse consentite e limiti prima di decodificare immagini. Nessuna riproduzione offensiva effettuata. Rimuovere testo utente dai log: Swift stampa il prefisso, backend l'intero testo in alcuni errori. Conservare `Cache-Control: no-store`.
- **Dipendenze riproducibili.** Quattro vincoli `>=` in requirements non sono un lock. Risoluzione verificata delle dipendenze runtime e test, dichiarando quelle dirette, incluso `httpx` per TestClient e `soundfile` per gli script; OCR PyObjC resta opzionale macOS. Non scegliere nuove versioni arbitrarie durante questo audit.
- **Provider e modularità.** `onnx_engine.py` sostituisce globalmente `ort.InferenceSession`; confinare adattamento nel motore e preservare associazione provider/opzioni. Il fatto che CoreML sia disponibile non dimostra esecuzione effettiva su ANE. Togliere import Supertonic eager dai livelli generici quando si completa l'intercambiabilità.
- **Misure prima di M4.** Misurare RSS Swift, RSS Python, picco totale, modello su disco, cold/warm startup, tempo al primo audio, gap fra chunk e CPU idle con waveform visibile/nascosta. Spostare preparazione testo fuori MainActor e ridurre aggiornamenti waveform a componenti piccoli/visibili; non introdurre Metal o riscrivere AVAudioPlayer per un vantaggio non misurato.

## Roadmap e documenti di sviluppo: cosa correggere nella strategia
La documentazione mescola tre stati: prodotto Tauri storico, rewrite Swift iniziale e client Swift attuale con sidecar Python. Una feature chiusa nel vecchio stack non è automaticamente portata nel nuovo. La raccomandazione è rendere `dev-docs/roadmap.md` fonte strategica unica, come previsto dalle regole del progetto, e usare `ROADMAP.md` radice soltanto come vista sintetica con rinvii e stessi identificativi; trasferire prima gli item esclusivi, non cancellarli.

| Documento letto | Riscontro | Soluzione proposta |
|---|---|---|
| `dev-docs/README.md` | Non cataloga tre documenti di piano/ricerca presenti nella cartella | Indice completo con tipo documento e stato; distinguere ricerca da requisiti approvati |
| `dev-docs/roadmap.md` | Settimane Tauri, M1–M5 native e port futuri convivono; feature contemporaneamente future e complete | Backlog nativo con stato per piattaforma e prova associata, preservando lo storico separato; correggere code fence aperto |
| `dev-docs/bug.md` | Cinque bug aperti; #6/#7 chiusi con fix Rust/JS | Mantenere i cinque aperti; segnalare #6/#7 risolti nel legacy, port Swift da verificare, senza riaprirli automaticamente |
| `dev-docs/decisions.md` | Otto ADR accettate; ADR-008 prescrive AVAudioEngine, ora sostituito da AVAudioPlayer | Successore esplicito dell'ADR audio; conservare privacy, inferenza serializzata, ordine normalizzazione e separazione cattura nativa |
| `dev-docs/FEATURES.md` | Percorsi `native/Lettore`, AVAudioEngine, 9 test e capacità legacy non rappresentano il prodotto corrente | Quattro categorie: disponibile nel client, disponibile solo backend, strumenti di test, pianificato; non chiamare il mock feature utente |
| `dev-docs/testing-checklist.md` | 12 scenari manuali, molti DOM/Tauri/Web Audio; nessun verbale di esecuzione | Riscrivere scenari osservabili macOS, mantenere ID; indicare build/OS/app/permessi/esito, senza promuovere checklist a test passati |
| `dev-docs/piano-ui-lettura.md` | Timeline/karaoke/seek descritti tramite JS eliminato; skip/progresso Swift già presenti | Portare requisiti sul modello di sessione attuale, non ricreare player web; evitare karaoke proporzionale presentato come allineamento reale |
| `dev-docs/progettazione-100-native.md` | Blueprint con C-API/PCM futuro; Studio indicato ancora da fare ma esiste | Distinguere architettura attuale e obiettivo M4; avanzamento basato su codice e benchmark |
| `dev-docs/identificare-blocchi-testuali.md` | Trascrizione esplorativa, alternative non chiuse | Conservare come ricerca; estrarre solo requisiti accettati: AX→clipboard→OCR, coordinate coerenti, selezione tastiera, niente LLM |
| `repo-docs/README.md` | Descrive bene Swift+Python, ma «Fase 3.0 completata» e target prestazionali superano le prove | Dichiarare client nativo completo nella forma UI, inferenza esterna transitoria e gate ancora non misurati |
| `repo-docs/change-log.md` | Include evoluzioni sito e target di latenza; non prova parità nativa | Separare aggiornamenti documentali/sito da feature applicative e misure |
| `ROADMAP.md` radice | Contiene AUDIO-MP3 P1 assente dalla tabella nativa dev-docs; DSA-7 non coincide fra riepiloghi | Riconciliare entrambi prima di scegliere il riepilogo canonico; nessuna perdita di item |

### Tutti i bug ancora aperti nel registro
1. **#1 — Pitch alterato cambiando velocità.** Non diagnosticato nel registro. Il doppio speed corrente è un difetto correlato, non prova della causa storica né di pitch preservato dopo la correzione. Verifica uditiva a 0.75×/1×/1.5×/2× su stesso testo e stessa voce.
2. **#2 — Cambio voce ignorato.** Verificare nuova lettura e chunk già precaricato; l'invalidazione della cache è necessaria nel client attuale. Non dichiarare chiuso dalla sola selezione visiva.
3. **#3 — Confusione fra lingue.** Correggere fallback Apple italiano e ordine rilevamento/normalizzazione; testare lingue alternate e testo misto nella stessa sessione.
4. **#4 — Pillola non trascinabile.** Descrive modalità compact Tauri. Non applicare il vecchio fix DOM al panel Swift; verificare drag, bordi, monitor e ciclo nascondi/mostra nativo.
5. **#5 — Lettura coda HTTP 400.** Replay storico riuscito, causa non confermata; preservare input/parametri solo in una fixture esplicitamente fornita o anonimizzata, non nei log di testi privati. Distinguere voce/lingua non valida da backend indisponibile; il corpo errore già raggiunge il client Swift, manca la restituzione utile all'utente.

### Priorità consigliate per tutto il backlog
| Ordine | Item esistenti | Decisione proposta |
|---|---|---|
| Prima delle nuove feature | Affidabilità playback, CI, parità controlli, accessibilità tastiera, startup/distribuzione | Base necessaria per qualsiasi funzionalità successiva |
| Prossimo ciclo prodotto | DSA-2 pause fra frasi, DSA-1 filtro accademico, DSA-4 tipografia comfort | Beneficio diretto sulla lettura; default espliciti e reversibili, corpus che eviti eliminazioni di testo utili |
| Dopo stabilità cattura | DSA-11 «Leggi da qui», DSA-3 area OCR, URLayer/megafono/hotkey rimappabili | Port nativo delle capacità legacy: selezione attuale non equivale a cursore→fine documento; bounding box e focus sono prerequisiti |
| Dopo baseline | PERF-2 prefetch N+2, PERF-1/M4 ONNX in Swift | Prima deduplicare preload e misurare starvation; aumentare profondità solo entro budget memoria. M4 resta prototipo comparativo prima della sostituzione del sidecar |
| Distribuzione utile | M5 packaging, SYS-UPDATE, AUDIO-MP3/M4A | Export già P1 nella roadmap root: preservarlo; update soltanto con canale release attendibile e confronto versioni, non priorità sopra l'avvio affidabile |
| Integrazione macOS successiva | UX-1 doppio modificatore/media keys, UX-2 smart clipboard, UX-3 Services/drag-drop, UX-4 selection bubble | Riutilizzare comando centrale cattura/lettura e rispettare focus, consenso e appunti |
| Ottimizzazione con costo privacy | PERF-3 cache persistente | Non duplicare LRU RAM; eventuale disco opt-in e cancellabile perché contiene audio dei testi personali |
| Funzioni specialistiche | DSA-5 proofreading, DSA-8 matematica, DSA-9 PDF multicolonna | Corpus e ordine di lettura prima di euristiche nuove; tenere matematica separata dalle sostituzioni regex generiche |
| Ultimo livello di sincronizzazione | DSA-6 karaoke, DSA-7 reading ruler, DSA-10 word tracking esterno; timeline/seek/ticker | Allineamento parola-tempo e coordinate prima di promettere precisione; non dedurlo dalla waveform decorativa |
| Espansione | Resume/anchor, traduzione locale, Listen-Repeat-Score, iOS/iPadOS, Windows/Linux, Android | Conservare backlog ma non aprire port multipli prima di macOS affidabile, benchmark e feedback utenti |

Mantenere i gate di reclutamento e prove con persone reali previsti nella roadmap: tastiera/VoiceOver e leggibilità non sono dimostrati da un tema ad alto contrasto. La shortlist sopra è una proposta di priorità, non una cancellazione degli item esistenti.

## Verifica futura: criteri di successo, non esecuzioni di questo audit
Per una futura implementazione, dalla root del repository e con toolchain Swift 6/macOS 14+ e ambiente Python già predisposti: `swift build`, `swift test`, `swift build -c release`, `python -m unittest discover -s backend_tests`. Il server neurale, solo nell'ambiente di esecuzione autorizzato: `python -m backend.main`; client: `swift run LettoreApp`. I test unitari non devono scaricare modelli o richiedere permessi di sistema; il test hardware usa modelli installati e permessi AX/Screen Recording quando necessari. Nessuno di questi comandi è stato eseguito qui.

| Comportamento | Input/scenario | Risultato osservabile richiesto |
|---|---|---|
| Stop affidabile | Sintesi A pendente → Stop → completa A con successo e, separatamente, errore | Nessun audio/fallback, nessun avanzamento, stato idle |
| Sostituzione sessione | Audio A attivo → cattura testo B di tre frasi → completion A tardiva | Parte la prima frase B, nessun salto o sovrapposizione |
| Pausa durante sintesi | Richiesta pendente → Pausa → WAV pronto → Riprendi | Nessun avvio durante pausa; singolo avvio del chunk corrente alla ripresa |
| Cache e voce | Preload con voce M1 → scegli F2 prima del chunk successivo | Audio successivo F2; nessun risultato M1 obsoleto consumato |
| Velocità | Stesso WAV a 1× e 1.5× | Durata riproduzione circa D e D/1.5; non D/2.25. Pitch valutato separatamente, non presunto |
| Input principale | Incolla «Prima frase. Seconda frase.» → Segmenta & Leggi | Parte prima frase, poi seconda; input vuoto non interrompe la sessione |
| Parità superfici | Play/Pausa/Stop da Studio, Pillola, Bassa Visione e Notch | Stesse transizioni, incluse sintesi pendente e fallback Apple |
| Fallback multilingua | Backend spento, lingua inglese, testo inglese | Voce Apple inglese o errore esplicito se indisponibile; UI dichiara fallback |
| Errori audio | WAV invalido o errore player | Non salta la frase come fosse completata; recupero possibile |
| Coda API | Elimina solo job corrente; elimina ID inesistente con job corrente presente | Primo successo, secondo 404; stato coda corretto |
| Configurazione | Runtime con esclusioni, richiesta con `text_exclusions: []` e `normalize_text: false` | Nessuna esclusione/normalizzazione imposta dal runtime |
| Testo | `Dott.ssa Rossi`, `€1,5`, emoji, frase molto lunga senza punteggiatura, lingua auto non italiana | Abbreviazione integra, cinquanta centesimi, progresso ≤1, chunk limitati, nessuna espansione italiana impropria |
| Appunti/focus | Cattura da TextEdit; durante attesa utente copia altro testo | Testo sorgente corretto; nuova copia utente non sovrascritta dal ripristino |
| Accessibilità | Solo tastiera e VoiceOver, da apertura a cattura/ascolto/stop | Nessun comando disponibile solo con hover; etichette/stato annunciati; focus recuperabile |
| Panel/OCR | Nascondi/mostra e drag su due monitor; OCR con permesso negato/vuoto/PDF a due colonne | Docking ancora attivo; errori distinti; ordine lettura per colonna, non alternato |
| Release | Mac pulito senza Python/modelli, poi ambiente neurale predisposto | Bundle dichiara chiaramente capacità disponibili; niente silenzioso «neurale» se usa Apple |
| Risorse | Lettura lunga con prefetch/export e chiamate stato concorrenti | Budget memoria rispettato, health disponibile, nessuna sintesi identica duplicata; misure annotate per hardware/cold/warm |

## Assunzioni e limiti
- Nessuna modifica al codice o ai documenti del repository autorizzata: questo è un rapporto di analisi con soluzioni. Un'eventuale esecuzione successiva non deve interpretare la consegna come ordine di implementare tutti gli interventi.
- Priorità proposta: consolidare macOS prima di espansione e riscrittura motore. L'utente può cambiare questa priorità; nessuna preferenza estetica nuova viene imposta.
- Evidenza statica non equivale a riproduzione: condizioni di race, latenza, pitch, consumo e contrasto complessivo richiedono le prove elencate. Non sono assegnati punteggi UX numerici senza osservazione della superficie reale.
- Conservare AVAudioPlayer per il vincolo CLI documentato. Se il pitch non soddisfa il requisito dopo la correzione della doppia velocità, aprire una scelta tecnica separata su time-stretch supportato: non reintrodurre AVAudioEngine contro il vincolo corrente né dichiarare chiuso il bug.
- L'audit distingue codice applicativo e materiali progettuali da dipendenze, cache, build output e strumenti degli agenti: questi ultimi non sono componenti del prodotto da revisionare riga per riga.

## Copertura finale e ultime evidenze
**Inventario effettivamente letto:** tutti i 18 file Swift di `Sources/` (3268 righe); tutti i 25 file Python di `backend/`; tutti e 7 i `backend_tests/*.py`; `Package.swift`, `build-app.sh`, `pyproject.toml`, `package.json`, `backend/requirements.txt`, `.gitignore`, CI e issue template; tutti e 9 i dev-docs, i 3 repo-docs, `README.md` e `ROADMAP.md` radice integrali; tutti i 25 file testuali del sito e i 3 file HTML/README dei mockup, oltre alla licenza. Inventariati 99 MP3 e 12 immagini senza ascolto o analisi visiva. Test: 36 metodi definiti (10 XCTest + 26 unittest), nessuno eseguito.

### Aggiunte dai test Python
- Copertura reale su normalizzatore (8 test, incluso pipeline combinata), chunking (5), blocchi (5, TestClient in-process), lingua (6 lingue latine + 5 alfabeti), engine (factory + DummyEngine a zeri), preview (in-process, non E2E), `concat_wav_bytes` (solo durata/sample rate, non campioni).
- **Nessun test motore/preview esegue inferenza ONNX reale** (Dummy/MockEngine restituiscono zeri) e **la CI non individua questi test con il percorso configurato** (`tests` anziché `backend_tests`). Correggere la discovery rende utile la copertura già presente; non equivale a provare che la suite passi.
- Gap trasversali: niente test su enabled=False/non-italiano, lingue miste, conservazione ordine/testo nei chunk lunghi, campioni audio concatenati. Test "instantiation" di blocchi ricontrolla campi forniti: non difendono contratto.

### Aggiunte dai documenti integrali (root)
- **Fase 6.0 solo in ROADMAP radice** (dizionario fonetico cross-device, correttore SLM 1–2B, Zotero): da classificare visione, non impegno.
- **Export root più ampio** (MP3 P1, M4A, batch/capitoli/cover) vs dev-docs (quick win MP3/OGG FFmpeg): riconciliare codec/priorità/contratto in unica fonte.
- **Root omette** DSA-7 reading ruler e gate utenti/VoiceOver del Track 1: item attivi da non perdere in fusione.
- **README radice:** shortcut ⌥+C non coincide né con ⌘⇧C implementato né con ⌘⇧Space checklist; terza incoerenza scorciatoie oltre a banner/pillola. Dichiarata correttamente distribuzione non autenticata e Python transitorio.
- **Licenza:** roadmap parla di open-source/software libero; README dichiara CC BY-NC-SA (non commerciale). Riconciliare terminologia prima di campagne community.
- **Link `file:///Users/...`** assoluti in ROADMAP radice: sostituire con relativi.
- **Claim senza prove da trattare come target:** ritenzione raddoppiata, fedeltà FP16 perfetta, cache 0 ms, export 30 min in 60–90 s, autonomia iOS >10 h. Stessa regola dei target prestazionali: etichetta, non fatto.

### Limiti residui
Sito e prototipi sono inclusi nel rapporto seguente. Misure prestazionali, pitch e contrasti richiedono esecuzione autorizzata: nessun benchmark o ascolto è stato effettuato in sessione.

### Sito e prototipi (audit completato)
Tutti i 25 sorgenti `website/` integrali, 99 MP3 inventariati (90 `{doc}_{voce}_{n}` + 9 fallback, provenienza: generatore 16 step), 3 file mockup, licenze. Nessuna valutazione visiva runtime. La vetrina non è il prodotto, ma ha gli stessi difetti dell'app — e due in comune.
- **Doppia velocità anche nel sito:** `AudioPlayerContext.jsx` invia `speed` a `/v1/tts` e applica anche `playbackRate`. Allineare la semantica con Swift, mantenendo implementazioni separate per le due piattaforme; verificarle entrambe senza aggiungere un runtime condiviso.
- **Stesso difetto di Stop/lifecycle:** timer `setTimeout` e fetch non cancellati; una risposta tardiva avvia audio di un vecchio testo o riprende dopo pausa. Stessa terapia: sessione/generazione e possesso di task, già previsti per il coordinatore Swift.
- **Stato motore non dichiarato:** il fallback Web Speech silent, senza `utterance.voice`, mentre la UI continua a promettere Supertonic 16 step. Mostrare la sorgente vocale reale, come già previsto per l'app.
- **Priorità sito 1:** lifecycle audio unico cancellabile; pausa/ripresa reale; impostazioni applicate ai confini frase.
- **Priorità sito 2:** accessibilità senza redesign: frasi come azioni semantiche, pillola non solo hover, dialog con focus/nome, tema chiaro con colori hard-coded incompatibili (drawer quasi nero, testo bianco su tinte leggere), `prefers-reduced-motion` assente, griglie con `minmax(320px,1fr)` che traboccano a 320px.
- **Priorità sito 3:** verità di prodotto: qualificare claim non dimostrati (<15 ms, RAM <80MB, CPU <0.1%, riduzione cognitiva 40%) e distinguere cuffie pianificate da disponibili. I 10 ID della demo non verificano né smentiscono il catalogo 20+ dell'app. Il voto sulla roadmap non ha meccanismo; distinguere licenza progetto CC BY-NC-SA da licenze upstream e residui MIT non renderizzati. Identificare i prototipi come concept.
- **Priorità sito 4:** performance dopo le funzioni: ownership dei blob (object URL mai revocati), waveform isolata (context ricreato a ogni rAF), font self-hosted se misurati; metadata social/noscript prima di pubblicare.

## Conclusione
La separazione nativa dei moduli è valida; affidabilità, comandi UI, distribuzione e documentazione devono ancora essere allineati. App e sito condividono difetti concettuali di sessione audio e velocità, ma richiedono correzioni specifiche nei rispettivi runtime. Prima consolidare questi contratti, CI e accessibilità; poi misurare e scegliere le prossime feature. Nessuna implementazione è autorizzata da questo rapporto.
