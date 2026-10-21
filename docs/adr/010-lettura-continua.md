# Lettura continua da selezione o cursore (DSA-11)

- **Stato**: Accettata e validata empiricamente su TextEdit, Safari e VS Code; Word non disponibile, Preview/PDF best effort
- **Data**: 2026-10-20
- **Riferimenti**: [DSA-11 nella roadmap](../../ROADMAP.md), [ADR-007](007-universal-reading-layer-fallback-3-livelli.md), [ADR-008](008-rewrite-100-nativo-macos-swift.md)

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
   completo).
2. **Text marker** del documento (`AXStartTextMarker`/`AXEndTextMarker`,
   `AXSelectedTextMarkerRange` e attributi parametrici) per le web area di
   Safari e gli engine che espongono solo marker. Questo ramo viene valutato
   prima del valore degli antenati: in Safari il value parziale di un
   contenitore non deve oscurare il documento completo.
3. Valore di un antenato che contiene la selezione.
4. DFS del contenitore scorrevole per ricostruire la viewport visibile, con
   ricerca della selezione o del valore focalizzato per mappare l'ancora.
5. Fallback al solo elemento focalizzato, con avviso esplicito, se l'ancora
   non è mappabile.

L'ancora è un offset UTF-16 nel testo catturato. Se la selezione compare più
volte nella viewport, la mappatura resta best effort. Nel ramo marker il testo
restituito è già ancorato alla selezione (`anchorUTF16 = 0`); se la selezione
marker manca, si ripiega sul `selectedText` e sulla sua posizione nel
documento.

La cattura è uno **snapshot al momento del Play**: le modifiche successive del
documento non vengono inseguite.

### 2. Sorgente e orchestrazione

- `ContinuousTextSource` in `LettoreCore` espone `startContinuousCapture()`,
  `nextContinuousPage()` e `endContinuousCapture()`; i valori di scambio sono
  `Sendable` e contengono solo testo, flag e avvisi.
- `TargetedContinuousTextSource` estende il contratto per avviare la cattura
  da un PID esplicito. Serve al pulsante "Leggi da qui" dello Studio, che è
  per definizione in primo piano e altrimenti catturerebbe se stesso.
- `AXCaptureService` implementa le sorgenti in `LettoreSystem`. Gli
  `AXUIElement` restano confinati all'attore.
- `ContinuousReadingController` in `LettoreEngine` orchestra cattura,
  preparazione, chunking, richieste di pagina e pulizia. Ogni sessione ha una
  `sessionGeneration`; i task asincroni la verificano dopo ogni `await` e le
  scritture avvengono su una copia locale, committata solo alla fine. Una
  sessione fermata non può più accodare testo o lasciare avvisi.
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

Se una pagina non produce alcuna frase (solo numeri, testo filtrato o coda
senza terminatori), il controller non chiude la sessione: richiede la pagina
successiva, fino a un massimo di 32 richieste per singola chiamata. A fine
documento, o al raggiungimento del cap, il carry residuo viene forzato in
chunk, così il testo trattenuto non resta invisibile.

### 4. Paging e focus

Ordine di paging:

1. azioni AX sulla scroll area o sulla scroll bar
   (`AXScrollDownByPage`, `AXScrollDown`, `AXPageDown`);
2. impostazione del valore della scroll bar con passo stimato da
   `AXValueIncrement`, quando disponibile;
3. `CGEvent` PageDown **solo** se l'app di origine è già in primo piano.

Non si attiva mai l'app di origine e non si sposta il focus. L'app resta nella
posizione raggiunta.

La fine dello scroll è uno stato a tre valori:

- `atEnd`: la scroll bar espone un range valido e `value >= max`;
- `notAtEnd`: il range è valido e c'è ancora spazio;
- `unknown`: range assente, nullo o `max == min` (per esempio Safari e alcune
  scroll bar che non pubblicano min/max). In questo caso si tenta comunque lo
  scroll; la sessione termina solo quando lo scroll non produce testo nuovo.

La nuova viewport viene deduplicata con `DocumentPageOverlap`: il più lungo
suffisso della viewport precedente che coincide con un prefisso della nuova
viene rimosso. L'algoritmo è KMP, con limite dinamico
`min(old.count, new.count)` e confronto per `Character`, non un cap fisso a
4.000 caratteri.

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
dal pulsante "Leggi da qui" nello Studio. La scorciatoia globale legge l'app
davvero in primo piano. Le richieste che partono dalla UI di Lettore (pulsante
dello Studio e Play della pillola incorporata, o della pillola flottante
quando lo Studio è attivo) usano invece il PID dell'ultima applicazione
esterna attivata, perché al momento del clic l'app in primo piano è Lettore
stesso. Se il PID non è più valido, la cattura non legge l'interfaccia di
Lettore: il Play riprende la coda già pronta oppure mostra un avviso. Anche
una cattura continua fallita (nessun testo nel punto di partenza) ripiega
sulla coda esistente invece di lasciare il player muto. Lo Studio mostra il
testo catturato/preparato e la coda contiene tutto il testo.

Alcune app — tipicamente editor PDF e applicazioni Electron — non espongono
via AX né l'applicazione focalizzata né l'elemento focalizzato. In quel caso,
se la lettura riguarda l'app davvero in primo piano, la modalità continua
ripiega su `Cmd+C` per leggere la selezione corrente. È una sessione
sola-selezione: non c'è paging e lo Studio mostra l'avviso "Continuazione non
disponibile in questa app: letta solo la selezione." Il fallback clipboard
non viene usato quando la cattura è targetizzata a un PID esplicito, perché
`Cmd+C` finirebbe nell'app in primo piano (Lettore) invece che nell'app di
origine.

### 7. Limite di sicurezza

Una sessione continua si ferma a 200.000 caratteri, con avviso. Il limite
evita catture accidentali di documenti enormi e mantiene il footprint di
memoria sotto controllo.

Nel ramo marker il cap viene verificato con gli attributi parametrici
(`AXIndexForTextMarker`, `AXLengthForTextMarkerRange`, `AXTextMarkerForIndex`)
prima di materializzare il documento: quando supportati, si costruisce
direttamente il range troncato. Se non lo sono, si ripiega sulla
materializzazione completa e sul taglio successivo, con la stessa semantica.

## Conseguenze

**Positive**

- Nessuna selezione manuale estesa; la lettura prosegue oltre la viewport.
- Il primo chunk parte subito e rispetta il confine di frase.
- Focus e posizione dell'app di origine sono preservati.
- Il comportamento è testabile: la sorgente è un protocollo e il controller
  non dipende dalle API AX.
- Le sessioni sono isolate: stop, toggle e nuove catture non mescolano testo
  vecchio e nuovo.
- Safari non richiede più una copia integrale del documento prima del taglio.

**Negative / limiti**

- Word non è installato nell'ambiente di validazione: la matrice non è
  coperta.
- Preview/PDF non espone un'ancora AX utilizzabile: la lettura continua resta
  best effort e può richiedere OCR o una strategia dedicata.
- Safari non ha mostrato una pagina realmente virtualizzata nel documento di
  prova: il percorso marker è validato sul documento completo, non sul paging
  reale.
- VS Code con `AXValue` troncato (`numberOfCharacters > value`) non è ancora
  stato provato; il resolver lo tratta come valore incompleto e prosegue nella
  cascata.
- Il paging può richiedere un fallback PageDown, che funziona solo con l'app
  di origine in primo piano.
- La mappatura dell'ancora è ambigua se la selezione compare più volte nella
  viewport.
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
- **Leggere l'app in primo piano dal pulsante dello Studio**: lo Studio è
  inevitabilmente in primo piano al clic; servirebbe attivare l'app di origine,
  rubando il focus.

## Verifica

- `swift build` e `swift test` verdi: **66 test, 0 fallimenti** (46 iniziali,
  9 `DocumentPageOverlap`, 9 `ContinuousReadingController`, 2 cattura
  targetizzata).
- Matrice manuale:
  - **TextEdit**: `AXValue` completo, 17.212 caratteri, ancora 1.488.
  - **Safari**: text marker, 17.509 caratteri, ancora 1.785.
  - **VS Code**: `AXValue` completo, 17.212 caratteri, ancora 1.488.
  - **Preview/PDF**: nessuna ancora; il fallback clipboard legge 17.130
    caratteri ma non abilita la continuazione.
  - **Word**: non installato, test non eseguibile.
- La sonda AX e i report della matrice vivono in
  `.scratch/dsa-11-lettura-continua/probe/`.
- La code review ha prodotto i fix `B1` (race di sessione), `B2` (pulsante
  Studio che catturava Lettore), `B3` (fine scroll con scroll bar senza range),
  `I4` (pagina senza frasi), `I5` (cap prima della materializzazione), `I6`
  (fallback selezione), `I7` (overlap KMP), `I8` (ordine marker/antenati) e
  `N10` (mutazioni premature), tutti coperti da test o verifiche mirate.
