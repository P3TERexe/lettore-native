# Lettura continua da selezione o cursore (DSA-11)

**Stato**: Accettata, con validazione empirica AX in corso  
**Data**: 2026-10-20  
**Riferimenti**: [DSA-11 nella roadmap](../../ROADMAP.md), [ADR-007](007-universal-reading-layer-fallback-3-livelli.md), [ADR-008](008-rewrite-100-nativo-macos-swift.md)

## Contesto & Problema

I lettori vocali tradizionali chiedono di selezionare manualmente l'intero
blocco da leggere. Su documenti lunghi (tesi, contratti, libri, pagine web)
trascinare il mouse per decine di schermate è faticoso, provoca deselezioni
accidentali e interrompe la memoria di lavoro. Gli utenti con dislessia
tendono a selezionare blocchi troppo corti e a doversi fermare ogni minuto.

Serve una modalità in cui la selezione — o, in assenza di selezione, il
cursore — sia **solo il punto di partenza**. La lettura deve proseguire fino
alla fine del documento, anche quando l'applicazione espone a macOS soltanto
la viewport visibile e virtualizza il resto.

## Decisione

### 1. Ancora e risoluzione del testo

La posizione iniziale viene risolta a cascata:

1. `AXValue` dell'elemento focalizzato combinato con
   `AXSelectedTextRange` (campi di testo ed editor che espongono il documento
   completo);
2. valore di un antenato che contiene la selezione (contenitori web);
3. DFS del contenitore scorrevole per ricostruire la viewport visibile, con
   ricerca della selezione o del valore focalizzato per mappare l'ancora;
4. fallback al solo elemento focalizzato, con avviso esplicito, se l'ancora
   non è mappabile.

L'ancora è un offset UTF-16 nel testo catturato. Se la selezione compare più
volte nella viewport, la mappatura resta best effort.

La cattura è uno **snapshot al momento del Play**: le modifiche successive del
documento non vengono inseguite.

### 2. Sorgente e orchestrazione

- `ContinuousTextSource` in `LettoreCore` espone `startContinuousCapture()`,
  `nextContinuousPage()` e `endContinuousCapture()`; i valori di scambio sono
  `Sendable` e contengono solo testo, flag e avvisi.
- `AXCaptureService` implementa la sorgente in `LettoreSystem`. Gli
  `AXUIElement` restano confinati all'attore.
- `ContinuousReadingController` in `LettoreEngine` orchestra cattura,
  preparazione, chunking, richieste di pagina e pulizia.
- `PlaybackCoordinator` segnala `onQueueLow` quando restano al massimo 3 chunk
  e `onSessionEnded` a fine sessione. Se la coda finisce mentre una pagina è
  in arrivo, attende la pagina prima di dichiarare conclusa la sessione.
- `stop(endingSession: false)` è usato da skip e jump interni: non chiudono la
  sessione continua. Solo lo stop esplicito la chiude.

### 3. Primo chunk e continuità delle frasi

I primi ~8.000 caratteri vengono preparati e accodati immediatamente, così
l'ascolto parte senza attendere l'intero documento. Il taglio avviene
sull'ultimo confine di frase completo prima del limite; se non esiste, si
ripiega sull'ultimo spazio.

Il resto del documento già catturato viene chunkato in background e accodato
**prima** delle nuove pagine. `SentenceCarryBuffer` trattiene la coda
incompleta di ogni pagina e la unisce alla successiva, evitando che una frase
venga spezzata al confine di pagina.

### 4. Paging e focus

Ordine di paging:

1. azioni AX sulla scroll area o sulla scroll bar
   (`AXScrollDownByPage`, `AXScrollDown`, `AXPageDown`);
2. impostazione del valore della scroll bar con passo stimato da
   `AXValueIncrement`, quando disponibile;
3. `CGEvent` PageDown **solo** se l'app di origine è già in primo piano.

Non si attiva mai l'app di origine e non si sposta il focus. L'app resta nella
posizione raggiunta. La nuova viewport viene deduplicata cercando il più lungo
suffisso della viewport precedente che coincide con un prefisso della nuova.

Se lo scroll non produce testo nuovo, la sessione si ferma con un avviso
persistente fino alla prossima cattura. Se l'app perde il primo piano e lo
scroll AX non è sufficiente, non viene inviato PageDown: si ferma con un
avviso che invita a tornare sull'app.

### 5. Preferenze e filtro

- Modalità disattivata di default.
- Sotto-toggle "Carica le pagine successive" attivo di default.
- Filtro rumore leggero attivo di default, applicato solo alle catture
  documentali continue. Rimuove numeri di pagina, intestazioni/piè di pagina
  ripetuti e unisce le parole spezzate a fine riga; note e citazioni restano.
- Toggle, sotto-toggle e filtro sono persistiti in `UserDefaults`.
- Disattivare la modalità o il sotto-toggle ferma **solo** le nuove pagine: la
  coda già catturata continua a essere riprodotta.

### 6. Ingressi e UI

La modalità è attivabile da:

- scorciatoia globale `Cmd+Shift+L`;
- toggle nello Studio e nella menu bar;
- card nello Studio con sotto-toggle e picker del filtro.

La cattura continua parte da `Cmd+Shift+C`, dal Play della pillola in idle e
dal pulsante "Leggi da qui" nello Studio. Lo Studio mostra il testo
catturato/preparato e la coda contiene tutto il testo.

### 7. Limite di sicurezza

Una sessione continua si ferma a 200.000 caratteri, con avviso. Il limite
evita catture accidentali di documenti enormi e mantiene il footprint di
memoria sotto controllo.

## Conseguenze

**Positive**

- Nessuna selezione manuale estesa; la lettura prosegue oltre la viewport.
- Il primo chunk parte subito e rispetta il confine di frase.
- Focus e posizione dell'app di origine sono preservati.
- Il comportamento è testabile: la sorgente è un protocollo e il controller
  non dipende dalle API AX.

**Negative / limiti**

- Safari, Word e Preview possono esporre attributi AX diversi; il resolver è
  best effort finché la sonda empirica non è completata.
- Il paging può richiedere un fallback PageDown, che funziona solo con l'app
  di origine in primo piano.
- La mappatura dell'ancora è ambigua se la selezione compare più volte nella
  viewport.
- I PDF in Preview possono richiedere OCR o una strategia dedicata.
- Il testo mostrato nello Studio è una copia dello snapshot: non riflette
  modifiche successive del documento.

## Alternative scartate

- **Leggere solo la selezione**: non risolve il problema dei blocchi corti e
  delle selezioni manuali ripetute.
- **Copiare l'intero documento negli appunti**: richiede `Cmd+A`/`Cmd+C`,
  altera gli appunti, non funziona con documenti virtualizzati e può essere
  bloccato dalle app.
- **Inviare sempre PageDown**: sposta il focus o attiva l'app sbagliata se
  l'app di origine non è in primo piano; viola il requisito di non rubare il
  focus.
- **Usare l'azione AXScrollToVisible sull'ultima selezione**: porta a schermo
  l'elemento selezionato, non avanza di una viewport e può cambiare la
  selezione.
- **Attendere la cattura completa prima di parlare**: aumenta la latenza
  percepita e rende inutile l'ascolto immediato.

## Verifica

- `swift build` e `swift test` verdi; 46 test totali, di cui 10 nuovi su
  filtro, carry buffer, split point, append e preferenze.
- Matrice manuale TextEdit / Safari / VS Code / Word / Preview ancora da
  eseguire. I ticket di sonda e validazione sono in
  `.scratch/dsa-11-lettura-continua/`.
- La validazione empirica può portare a correzioni del resolver e del pager
  senza cambiare il contratto tra le sorgenti e il controller.
