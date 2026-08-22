# Piano UI — Il pannello di lettura come protagonista

Piano di evoluzione dell'interfaccia: trasformare Lettore da "box incolla → ascolta" a **reading companion**, con la riproduzione (e il testo che la accompagna) al centro dell'esperienza.

Due aree di lavoro, strettamente collegate:

1. **Il pannello di lettura come protagonista** — vista karaoke, modalità ticker, waveform reale.
2. **Player strip → vero controllo** — seek, skip per frase, velocità continua, coda inline.

---

## 0. Fondazione condivisa: la Timeline

### Stato attuale

La riproduzione è **a chunk discreti**: ogni job in coda = una chiamata `POST /v1/tts` = un WAV intero giocato con `player.playBytes()`. Non esiste una timeline globale: quando un chunk finisce (`onended` → `queue.next()`), si passa al successivo. La progress bar mostra solo il progresso del *chunk corrente*, non della lettura intera.

L'evidenziazione parole (`app.js`: `showReading()`, `highlightWord()`, `readingIndexAt()`) è limitata al job corrente e si resetta a ogni chunk.

### Proposta: modello Timeline

```
Timeline {
  items: [ { jobId,
             text,
             charStart, charEnd,      // offset assoluti nel testo completo
             audioDuration,           // secondi del chunk
             tStart, tEnd,            // posizione temporale assoluta
             words: [{text, start}] } // offset caratteri relativi al chunk
  ]
}
```

- Quando `queue.advance()` sintetizza (o decodifica dal preload) un chunk, si conoscono `buffer.duration` e il testo del job → si calcola la posizione temporale assoluta del chunk nella lettura.
- La mappa parola→tempo resta proporzionale ai caratteri (come l'attuale `readingIndexAt()`), ma **cumulata sui chunk precedenti** invece di resettare. I chunk sono frasi brevi (pySBD già presente), quindi l'errore si accumula poco.
- Peso dell'interpunzione: assegnare alle virgole/punti un peso in caratteri extra (es. virgola +3) per far "fermare" l'highlight nei punti in cui anche la sintesi pausa.
- Evoluzione futura (non bloccante): il backend Supertonic potrebbe restituire i tempi reali dei fonemi per chunk; la struttura Timeline è pronta ad accoglierli.

Con questa struttura, tutte le feature seguenti diventano estensioni naturali.

---

## 1. Vista karaoke

### Cosa cambia rispetto a oggi

Oggi `showReading()` crea uno span per ogni parola dell'*intero* testo dentro un pannello laterale; `highlightWord()` cicla su tutti gli span a ogni frame di `onProgress` (O(n) per rAF) e usa `scrollTo({behavior:"smooth"})` che salta a ogni cambio indice.

### Design

- Frasi come unità di layout: frase corrente centrata verticalmente, ~1 riga sopra/sotto visibile.
- Sfumatura sopra/sotto con `mask-image: linear-gradient(transparent, black 30%, black 70%, transparent)`.
- Parola corrente evidenziata con background accent dentro la frase.
- Zero scroll continuo: si scorre solo al cambio di frase, con `transform: translateY()` sul contenitore (GPU), transizione ~300ms con `--ease-spring`.
- Finestra di rendering ±3 frasi intorno alla corrente, rigenerata al cambio (necessario per testi lunghi).

### Implementazione

- Nuovo attributo `data-mode="focus"` (accanto a compact/standard/full), stesso pattern CSS esistente.
- Rifattorizzazione obbligatoria di `showReading()` / `highlightWord()`: tenere puntatore `currentIdx` e togliere la classe solo allo span precedente (O(1)).
- Click su parola futura → seek (vedi §3): il mapping Timeline lo rende banale.

---

## 2. Modalità ticker

Concept: la finestra collassa a una barra alta ~28px (l'attuale titlebar) — testo corrente + play/pausa. L'estremo opposto del karaoke: stessa Timeline, due skin.

### Design

- Nuovo valore `data-mode="ticker"`: CSS nasconde sidebar, player strip e panels; la titlebar diventa il display.
- Testo con effetto "lead": niente marquee infinito — la frase corrente con offset animato così la parola evidenziata resta sempre al centro (stessa logica di centramento del karaoke, ma orizzontale).
- Indicatore di stato legato allo stato reale: verde = playing, pulsante = sintesi in corso.
- Click sulla riga → espansione a standard (stesso meccanismo dell'attuale `btn-expand-compact`).

### Attenzione lato Rust

- Verificare le size minime in `tauri.conf.json`: serve estendere il comando `set_window_mode` (`src-tauri/src/commands.rs`) perché ridimensioni anche la finestra quando si entra/esce da ticker.

Valore strategico: per l'uso "leggo un articolo mentre lavoro", Lettore scompare e basta.

---

## 3. Waveform cliccabile + seek

Unisce la waveform del pannello lettura e il seek del player strip: sono la stessa feature.

### Dati

I WAV dei chunk sono già in memoria (`player._lastWav`, ArrayBuffer PCM). Basta:

1. Prendere il canale 0 e downsample a ~500 colonne (min/max per colonna → barre simmetriche) su `<canvas>`.
2. Renderizzare la waveform dell'intera lettura: i chunk non ancora sintetizzati appaiono come zona tratteggiata/piatta ("non ancora generato") — informativo e mostra il preload in tempo reale mentre `preloadNext()` lavora.

### Seek — opzioni

| | Client-only (fase 1) | Con backend (fase futura) |
|---|---|---|
| Come | `source.start(0, offsetSeconds)` sul buffer già decodificato | Endpoint `/v1/tts?from_char=&to_char=` |
| Pro | Zero modifiche backend, immediato | Funziona anche su chunk non ancora sintetizzati |
| Contro | Solo dentro il chunk corrente | Lavoro Python + lock inferenza |

Via pragmatica: **seek client-side nel chunk corrente + skip frase per uscire**. Se il target è oltre la fine del chunk corrente:

- marcare come done i chunk intermedi (esiste già `POST /v1/queue/current/done`);
- lasciare che `advance()` sintetizzi il chunk target — la cache preload (`_preloadedBuffers`) rende quasi istantanei i chunk vicini.

### Interazione

- Hover: linea verticale + tooltip `m:ss` e anteprima frase target (via Timeline).
- Drag: scrubbing con aggiornamento live di highlight e time label; riparte solo al rilascio (`pointerdown/move/up` + `setPointerCapture`). Pausa implicita durante il drag.
- Tacche delle frasi sopra la waveform: navigazione + senso di posizione.

---

## 4. Skip ±1 frase

Metodo sulla Timeline:

```js
skipSentence(dir) {
  const t = timeline.positionAt(player.elapsed());
  const target = timeline.sentenceAfter(t, dir);
  if (target.jobId === currentJobId) {
    player.seekTo(target.tStart);              // client-side
  } else {
    queue.skipToJob(target.jobId);             // done intermedi + advance()
  }
}
```

UI: frecce ‹ › ai lati del play (nascoste in compatto), shortcut `Cmd+←/→`.

Edge case:
- skip indietro oltre l'inizio del primo chunk → riparte da capo;
- skip avanti sull'ultimo chunk → stop pulito.

---

## 5. Velocità continua

Slider sottile (0.5–2.5x, step 0.05) al posto del select, valore in tabular nums accanto.

- `player.setSpeed()` aggiorna già `playbackRate` live → lo slider suona in tempo reale durante la riproduzione.
- ⚠️ Coerenza con il backend: `queue.add()` invia `speed` alla sintesi; i chunk vecchi restano a velocità diverse se si cambia a metà (mismatch esiste già ed è mascherato da `advance()` che forza `player.speed = currentJob.speed`). Soluzione: lo slider setta solo `playbackRate` client-side e persiste nei settings per le prossime sintesi — elimina anche il salto di timbro tra chunk.

---

## 6. Coda inline nello strip

Chip accanto al time label: `› N`.

- Tooltip: primi ~60 caratteri del prossimo job.
- Hover: popover con i prossimi 2–3 job.
- Click: apre il pannello coda.
- Dati già disponibili in `queue.render(state)` — solo presentazione, zero backend. Badge sidebar resta come contatore.

---

## Ordine di attuazione

| # | Step | Note |
|---|---|---|
| 1 | Timeline (modello dati) | ~100 righe, sblocca tutto il resto |
| 2 | Waveform + seek nel chunk corrente | Impatto immediato, zero backend |
| 3 | Skip ±1 frase | Riusa il seek |
| 4 | Vista karaoke | Comprende rifattorizzazione `showReading`/`highlightWord` |
| 5 | Ticker mode | Richiede tocco a Rust (resize finestra) |
| 6 | Slider velocità + chip coda | Chiusura, poco lavoro |

## Rischi e regole

- ⚠️ `player.js` è zona di bug storici sulla gestione della coda (vedi AGENTS.md). Ogni modifica al flusso start/stop/seek deve rispettare le regole esistenti:
  - azzerare `source.onended` prima di `source.stop()`;
  - chiamare sempre `disconnect()` sui nodi;
  - mantenere la guard anti-reentrancy su `advance()` / `next()`;
  - rileggere i fix recenti prima di toccare il flusso di playback.
- Stima parola→tempo proporzionale: accettare un errore residuo; non promettere allineamento perfetto finché il backend non espone tempi reali.
- Ogni nuova modalità finestra (`focus`, `ticker`) deve essere testata nelle transizioni compact ↔ standard ↔ full esistenti (`setWindowMode()` in `app.js`).
