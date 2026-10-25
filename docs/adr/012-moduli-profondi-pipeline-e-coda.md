# Moduli profondi: una sola pipeline testo, una sola coda

- **Stato**: Accettata
- **Data**: 2026-10-25
- **Riferimenti**: [ADR-006](006-normalizzazione-fonetica-italiana-esclusioni-pre-sintesi.md), [ADR-008](008-rewrite-100-nativo-macos-swift.md), [ADR-010](010-lettura-continua.md)

## Contesto & Problema

L'ingestione del testo era replicata in quattro punti (testo manuale,
selezione, prefisso della lettura continua, pagine successive), ognuno con la
propria sequenza di filtro, split, chunking, mappatura UTF-16 e
normalizzazione. L'ordine era identico per caso e non per contratto: una
modifica al chunking poteva produrre confini diversi a seconda dell'ingresso.

Lo stesso problema si presentava su tre assi vicini:

- gli invarianti della coda (indice corrente, append durante il play, fine
  coda, progresso) erano scritti in parte in `AppState` e in parte in
  `PlaybackCoordinator`, che assegnava `currentChunk` direttamente;
- le decisioni della cattura AX (fine scroll, ruoli ammessi, deduplica della
  viewport) vivevano dentro l'adapter `AXUIElement`, quindi erano verificabili
  solo con un'app reale;
- il backend esponeva `/v1/queue` e `/v1/blocks` senza consumatori e
  normalizzava di nuovo un testo già normalizzato dal client, con il rischio di
  cambiare i confini di frase e la mappa verso l'app di origine.

## Decisione

### 1. `ReadingTextPreparer` possiede l'ordine

`ReadingTextPreparer` in `LettoreCore` è l'unico tipo che conosce la sequenza
**filtro → split → chunk → mappa → normalizzazione**. Espone tre ingressi —
`prepareInitial`, `prepareRemainder`, `preparePage` — e restituisce
`PreparedReading` con testo di presentazione e chunk. Il remainder è opaco:
solo il preparer sa ricostruirlo, i chiamanti non possono duplicare l'ordine.

Il testo manuale e la selezione usano `mode: .off` e nessuno split; la lettura
continua usa il filtro configurato e uno split sul confine di frase entro il
limite di riproduzione immediata; il paging non ha mappa perché la pagina non è
un intervallo contiguo del documento.

Normalizzare **dopo** il chunking è parte della decisione: normalizzare prima
sposterebbe i confini di frase e renderebbe inutilizzabile la mappa UTF-16
verso l'app di origine. Per questo le pagine mostrano testo filtrato non
normalizzato e i loro chunk vengono normalizzati singolarmente.

### 2. `ReadingQueue` possiede gli invarianti della coda

`ReadingQueue` è un value type che detiene chunk, indice corrente e progresso
a granularità di chunk. Offre `replace`, `append`, `advance`, `rewind`,
`select(id:)` e `select(index:)` con i controlli di bounds al proprio interno;
l'append ricalcola gli indici preservando l'identità dei chunk e, se la coda
era terminata, riprende dal primo chunk nuovo.

`AppState` espone `readingQueue` e `currentChunk` in sola lettura e delega i
comandi. `PlaybackCoordinator` seleziona per identità (`selectChunk(id:)`) e non
scrive più `currentChunk`. `playbackProgress` resta in `AppState` perché contiene
anche la frazione dentro il chunk, che è di pertinenza del playback: la coda
fornisce solo la parte indice/totale.

### 3. Le decisioni AX pure vivono in `LettoreCore`

- `ScrollEndClassifier` classifica la scroll bar in `atEnd`, `notAtEnd`,
  `unknown`, con la tolleranza proporzionale storica. `unknown` non è prova di
  fine documento e impone un tentativo di scroll.
- `ViewportTextCollector` possiede ruoli ammessi ed esclusi, deduplica per
  chiave normalizzata, scarto di URL e marker di lista, formato dei blocchi e
  cap a 200.000 caratteri.

L'adapter `AXCaptureService+Continuous` conserva il DFS, la profondità, l'ordine
delle chiamate AX e le firme pubbliche: traduce solo `AXUIElement` in
`(role, value)` e applica le decisioni dei tipi puri.

### 4. Il backend è un sidecar con un contratto di sintesi

- Il client invia `normalize_text: false` in `/v1/tts` tramite un payload
  `Codable` puro: la normalizzazione avviene una sola volta, in `LettoreCore`.
- Il default del backend resta `normalize_text: true` per i client esterni come
  il sito.
- Il contratto dei chunk è esplicito: il client produce chunk entro 240
  caratteri e il backend non richunka un testo che rispetta il contratto.
- Le superfici senza consumatori (`/v1/queue`, `/v1/blocks`, `QueueManager`,
  `backend/blocks`) sono state rimosse invece di essere mantenute come
  architettura simulata.

## Alternative scartate

- **Normalizzare prima del chunking**: uniforma il testo mostrato ma sposta i
  confini di frase e invalida la mappa UTF-16 verso l'app di origine.
- **Tenere gli invarianti della coda nel coordinator**: due sorgenti di verità
  sull'indice, già causa di jump incoerenti dopo un append.
- **Un protocollo per ogni helper AX**: un solo adapter; l'astrazione avrebbe
  aggiunto cerimonia senza possibilità di sostituzione.
- **Mantenere `/v1/queue` e `/v1/blocks` "per il futuro"**: nessun consumatore,
  costo di test e superficie di contratto da mantenere.
- **Introdurre un protocollo per `ReadingTextPreparer`**: è un value type
  deterministico senza dipendenze di sistema; i test lo usano direttamente.

## Conseguenze & Vincoli

- Nei percorsi di ingestione non si chiamano `TextNormalizer` o
  `SentenceChunker` fuori da `LettoreCore`: ogni nuovo ingresso passa da
  `ReadingTextPreparer`.
- I nuovi tipi di `LettoreCore` non importano AppKit, Accessibility o SwiftUI.
- Le decisioni consolidate restano intatte: `AVAudioPlayer` (bug `-10868`),
  Swift 6 `@Observable`, offline-first, backend sidecar fino a M4.
- `SpeechOutput` possiede sintesi, cache L1/L2, prefetch, fallback alla voce
  di sistema e metering; `PlaybackCoordinator` resta coda, sessione e paging e
  consuma eventi con `requestID`. La lettura disco della cache avviene fuori dal
  MainActor e i completamenti di player/utterance sostituiti vengono ignorati.
- `ReadingCaptureController` è l'unica policy di cattura e `PillGeometry`
  possiede la geometria della pillola; le view comandano il playback tramite
  `PlaybackCoordinator` e non conoscono `AudioEngineService`.
- Restano aperti, perché richiedono GUI o ascolto umano, il paging dietro seam
  e la sessione di evidenziazione unica; lo smoke audio reale (riproduzione,
  pausa, skip, fallback di sistema) è manuale.
