# Bug Report 1

## Description
C'è un problema con il pitch (tono) della voce in relazione alla velocità di riproduzione.

## Steps to Reproduce
1. Avviare la riproduzione vocale.
2. Modificare la velocità di riproduzione.
3. Ascoltare l'effetto sulla voce.

## Expected Behavior
Il pitch della voce dovrebbe rimanere naturale e costante, senza subire distorsioni quando si modifica la velocità di lettura.

## Actual Behavior
Il pitch della voce risulta alterato in modo anomalo o innaturale quando si varia la velocità.

---

# Bug Report 2

## Description
Non funziona il cambio della voce dalle impostazioni: la sintesi continua a usare la voce precedente.

## Steps to Reproduce
1. Aprire Impostazioni → Voce.
2. Selezionare una voce diversa da quella attiva.
3. Avviare la lettura di un testo.

## Expected Behavior
La voce selezionata viene usata per la sintesi del testo.

## Actual Behavior
La lettura continua con la voce precedente; il cambio non ha alcun effetto.

---

# Bug Report 3

## Description
Il motore spesso confonde le lingue: la pronuncia non corrisponde alla lingua del testo.

## Steps to Reproduce
1. Inserire un testo in una lingua (es. italiano) e avviare la lettura.
2. Ripetere con testi in lingue diverse o miste nella stessa sessione.

## Expected Behavior
La lingua rilevata/selezionata corrisponde al testo e la pronuncia è corretta.

## Actual Behavior
Il testo viene sintetizzato con pronuncia/accento della lingua sbagliata, soprattutto alternando testi in lingue diverse.

---

# Bug Report 4

## Description
La finestra in modalità pillola (compact) non si può spostare trascinandola.

## Steps to Reproduce
1. Attivare la modalità compact/pillola (bottone "Cambia visualizzazione" nella sidebar).
2. Provare a spostare la finestra trascinando la player strip.

## Expected Behavior
Trascinando lo strip la finestra si sposta (drag region attiva).

## Actual Behavior
La finestra non si sposta: il drag non parte.

---

# Bug Report 5

## Description
La lettura dalla coda fallisce con il messaggio "Errore: sintesi fallita (HTTP 400)".

## Steps to Reproduce
1. Aggiungere un testo alla coda e avviare la riproduzione.
2. La sintesi del job risponde HTTP 400 e il toast mostra l'errore (origine UI: `queue.js:105`).

## Expected Behavior
Il job in coda viene sintetizzato e riprodotto.

## Actual Behavior
`POST /v1/tts` risponde 400. Il backend mappa ValueError → 400; le fonti note sono "voce sconosciuta: {voice}" (`tts_manager.py:239`) o errori sollevati dal motore su text/lang non validi.

## Diagnosi raccolte (2026-08-24)
- Replay con i settaggi attuali (voice F2, lang auto, steps 12, speed 1.5) contro `/v1/tts`: **HTTP 200**, sintesi corretta.
- Coda attualmente vuota: il job fallito non è più ispezionabile.
- Sospetto: job accodato con parametri vecchi (voce/lang salvati all'enqueue) non più validi, o ValueError del motore su quel testo specifico.
- Da fare al prossimo verificarsi: loggare il `detail` JSON della risposta 400 (oggi il toast lo scarta) e ispezionare il job prima che venga rimosso.

---

# Bug Report 6

## Description
La funzione "Leggi da qui" (cattura da cursore / selezione) cattura solo la singola parola evidenziata o solo il paragrafo corrente anziché tutto il testo successivo fino al termine del documento.

## Steps to Reproduce
1. Aprire un'applicazione esterna (es. Safari, Chrome, TextEdit, Notes).
2. Evidenziare una parola/frase o posizionare il cursore in un punto intermedio del testo.
3. Premere la scorciatoia globale `Shift+Command+C` o cliccare "Leggi da Cursore" dal menu di sistema o popover.

## Expected Behavior
La lettura sintetizza il testo a partire dalla parola o punto del cursore fino alla fine del documento o della pagina web attiva.

## Actual Behavior
Veniva letta solo la parola/frase evidenziata, oppure la selezione si fermava al termine del paragrafo corrente ignorando il resto del testo.

## Diagnosi e Risoluzione (2026-09-04)
1. **Prioritizzazione scorretta di `AXSelectedText` e mancata estrazione Web**:
   - `read_from_cursor_from_pid` in `macos.rs` restituiva prematuramente la singola parola/selezione di `AXSelectedText`, leggendo solo il frammento evidenziato.
   - Nei browser web (Chromium/Brave/Chrome/Safari), `Shift+Cmd+Down` viene ignorato o catturato per lo scrolling del viewport, impedendo l'estensione della selezione da tastiera e lasciando solo la parola iniziale evidenziata. Inoltre, le pagine web non espongono l'intero testo in `AXValue`.
2. **Implementazione runtime nativa Web AX TextMarker**:
   - Aggiunte le chiamate alle API C native macOS Accessibility: `AXTextMarkerRangeCopyStartMarker`, `AXUIElementCopyParameterizedAttributeValue` e `CFArrayCreate`.
   - Implementato `extract_web_selection_to_end`: interroga `AXSelectedTextMarkerRange` sull'elemento web, estrae lo start marker con `AXTextMarkerRangeCopyStartMarker`, lo abbina ad `AXEndTextMarker` tramite `AXTextMarkerRangeForUnorderedTextMarkers`, ed estrae nativamente tutto il testo da quel punto esatto fino alla fine della pagina (`AXStringForTextMarkerRange`).
   - Implementato `extract_web_full_text` e `find_in_full_text` con tolleranza (esatta, case-insensitive, prefisso e parole chiave) per allineare qualsiasi selezione parziale iniziale all'intero corpo della pagina web.
3. **Flusso unificato in `capture_from_cursor_internal` e Focus UI**:
   - La funzione cattura la porzione iniziale evidenziata dall'utente e la passa come àncora a `read_from_cursor_from_pid`.
   - `handleCursorRead` in `app.js` ora dà priorità alla textarea locale solo se ha il focus attivo (`document.activeElement === input`), prevenendo letture spurie di testo residuo quando l'utente attiva la funzione da applicazioni esterne.
   - Tutti i test Rust e Python passano al 100%.
