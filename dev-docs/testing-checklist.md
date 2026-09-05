# Checklist di Test Manuale & Pre-Release

Protocollo di smoke testing rapido (~5 minuti) da eseguire prima di ogni release, commit architetturale o verifica manuale su hardware reale (macOS / Windows).

---

## Regole di Formattazione per Nuove Voci

Ogni scenario deve seguire tassativamente questa struttura:

```markdown
### [TC-CODICE] Nome Scenario Diretto
- **Prerequisiti**: Stato dell'app o permessi necessari.
- **Passaggi (Step-by-step)**: Azioni fisiche da compiere (scorciatoia, click, selezione).
- **Esito Atteso**: Comportamento esatto osservabile (audio, visivo, focus).
- **Esito Fallito (Segnale di Allarme)**: Sintomo immediato di regressione.
```

---

## Scenari di Validazione Manuale

### [TC-001] Cattura Testo Nativo macOS con Scorciatoia Globale
- **Prerequisiti**: Permessi di Accessibilità concessi all'app in Preferenze di Sistema.
- **Passaggi**:
  1. Aprire TextEdit o Safari ed evidenziare un paragrafo di testo.
  2. Premere la scorciatoia globale (default `Cmd+Shift+Space` o configurata).
- **Esito Atteso**: La finestra di Lettore compare in primo piano, il testo selezionato viene caricato nell'editor/coda e la sintesi vocale parte in <500ms.
- **Esito Fallito**: Nessuna reazione, oppure compare banner "Abilita Accessibilità" pur avendo i permessi, o testo vuoto.

---

### [TC-002] Fallback Cattura via Clipboard Simulata
- **Prerequisiti**: Applicazione che non espone l'albero di accessibilità AX standard (es. finestra Terminale o viewer PDF protetto).
- **Passaggi**:
  1. Selezionare una riga di testo nel Terminale.
  2. Premere la scorciatoia globale di lettura.
- **Esito Atteso**: Lettore rileva l'assenza di testo AX, attiva la copia trasparente simulata (`Cmd+C`), cattura il contenuto dagli appunti e avvia la lettura senza errori.
- **Esito Fallito**: Lettore segnala "Nessun testo selezionato".

---

### [TC-003] Riproduzione Continua a Coda & Anti-Race Web Audio
- **Prerequisiti**: Testo lungo con almeno 3 frasi distinte.
- **Passaggi**:
  1. Incollare il testo e premere Play.
  2. Ascoltare la transizione tra il Chunk 0 e il Chunk 1.
  3. Premere Pausa a metà frase e riprendere con Play.
  4. Premere Stop bruscamente durante la lettura.
- **Esito Atteso**: L'audio passa da un chunk all'altro in modo impercettibile e senza clic o sovrapposizioni; Pausa/Play non riavviano da capo; Stop interrompe l'audio istantaneamente senza far scattare la frase successiva.
- **Esito Fallito**: Salto di chunk, sovrapposizione di due voci contemporaneamente o riproduzione che non si ferma allo Stop.

---

### [TC-004] Cambio Parametri Live (Velocità & Voce)
- **Prerequisiti**: Riproduzione vocale in corso.
- **Passaggi**:
  1. Durante la lettura, modificare lo slider della velocità da 1.0x a 1.5x.
  2. Verificare il pitch (tono) della voce.
  3. Cambiare voce attiva nelle Impostazioni (es. da Marco M1 a Giulia F1) per il testo successivo.
- **Esito Atteso**: La velocità aumenta in tempo reale mantenendo il pitch naturale (nessuna voce robotica/acuta da chipmunk); il chunk o testo successivo adotta la nuova voce selezionata.
- **Esito Fallito**: Voce distorta o cambio voce ignorato (il motore continua con la voce precedente).

---

### [TC-005] Finestra Nano Pill / Drag Region & Always-on-Top
- **Prerequisiti**: Finestra in modalità compatta (pillola fluttuante).
- **Passaggi**:
  1. Cliccare sull'area vuota della pillola e trascinarla sullo schermo.
  2. Cliccare su un'altra finestra (es. browser o editor di codice).
- **Esito Atteso**: La pillola si sposta fluidamente seguendo il cursore (`data-tauri-drag-region`) e rimane visibile sopra tutte le altre finestre (`alwaysOnTop`).
- **Esito Fallito**: Il trascinamento non risponde (finestra bloccata) o la finestra finisce dietro l'applicazione attiva.

---

### [TC-006] Lettura da Cursore e Parola Evidenziata ("Leggi da qui")
- **Prerequisiti**: Testo presente nella box di testo di Lettore, o in un'applicazione esterna (es. TextEdit o Safari).
- **Passaggi**:
  1. Nel testo presente nella box di Lettore, cliccare con il mouse o evidenziare una parola a metà del testo.
  2. Cliccare su "📍 Leggi da qui" (o premere `Cmd+Shift+C`).
  3. Ripetere il test posizionando il cursore all'interno di un'applicazione esterna.
- **Esito Atteso**: La lettura parte esattamente dalla parola/frase in cui si trova il cursore e prosegue fino al termine di tutto il testo presente nella box, senza troncare parole a metà.
- **Esito Fallito**: La lettura parte dall'inizio del testo ignorando il cursore, oppure tronca la parola iniziale a metà carattere.
---

### [TC-007] Widget Megafono (Titlebar e System Tray)
- **Prerequisiti**: Finestra di Lettore avviata e visibile.
- **Passaggi**:
  1. Cliccare sull'icona a forma di megafono nella barra superiore (titlebar).
  2. Verificare l'apertura del popover rapido con i pulsanti di azione.
  3. Cliccare su "Leggi da Cursore" o "Modalità Pillola" dal popover.
  4. Cliccare con il tasto destro sull'icona di Lettore nella menubar/tray di sistema e verificare le voci "Pillola Fluttuante" e "Leggi da qui (Cursore)".
- **Esito Atteso**: Il popover si apre e si chiude al click esterno o su un comando; le azioni corrispondenti si attivano istantaneamente sia dalla titlebar che dal menu tray.
- **Esito Fallito**: Il click sul megafono non produce alcun effetto visivo o il popover rimane aperto senza rispondere ai bottoni.

---

### [TC-008] Floating Pill Player con Dissolvenza Automatica a Trasparenza
- **Prerequisiti**: Riproduzione di una frase in corso.
- **Passaggi**:
  1. Passare alla modalità compatta ("Pillola") dal toggle o dal popover megafono.
  2. Osservare la barra singola arrotondata con le onde vocali animate in riproduzione (opacità piena 1.0).
  3. Attendere il termine della riproduzione vocale (o premere Stop).
  4. Non muovere il mouse per 2.5 secondi e osservare la finestra.
  5. Muovere il puntatore del mouse sopra la pillola o cliccare.
- **Esito Atteso**: Al termine della lettura, dopo 2.5s di inattività, la finestra pillola sfuma dolcemente verso la trasparenza (`opacity: 0.28`); al passaggio del mouse o al click, torna istantaneamente a opacità 1.0.
- **Esito Fallito**: La finestra rimane opaca indefinitamente dopo la fine della lettura, oppure non torna visibile al passaggio del mouse.

---

### [TC-009] Anteprima Voci Istantanea nelle Impostazioni
- **Prerequisiti**: Backend avviato e pronto.
- **Passaggi**:
  1. Aprire il pannello Impostazioni e scorrere al selettore "Voce".
  2. Cliccare sul pulsante ▶️ accanto al menu a tendina.
  3. Aprire "Gestisci nomi e lingue voci" e cliccare sul tasto ▶️ di una voce qualsiasi (es. F1 o M2).
- **Esito Atteso**: Viene riprodotta la frase di test ("Ciao! Questa è un'anteprima vocale di Lettore.") in meno di 200ms, senza interrompere né sovrascrivere la coda di lettura principale.
- **Esito Fallito**: Nessun audio riprodotto o errore visualizzato in console.

---

### [TC-010] Normalizzazione Testo Italiano e Filtro Esclusioni
- **Prerequisiti**: Opzione "Normalizza testo" attiva nelle Impostazioni.
- **Passaggi**:
  1. Nelle Impostazioni, inserire nella textarea delle esclusioni la riga `Inviato da iPhone`.
  2. Incollare nell'editor il testo: `"Il Dott. Rossi ha pagato 12.50€ su http://example.com alle 14:30. Inviato da iPhone"`.
  3. Premere "Leggi" e ascoltare la pronuncia.
- **Esito Atteso**: La voce pronuncia "Il Dottore Rossi ha pagato 12 euro e 50 centesimi su link example punto com alle 14 e mezza"; la frase "Inviato da iPhone" viene completamente omessa senza esitazioni o doppi punti.
- **Esito Fallito**: La voce legge letteralmente "Dott punto" o "12 punto 50 euro", oppure pronuncia la frase blacklistata.

---

### [TC-011] Identificazione a Riquadri (Text Block Peaker)
- **Prerequisiti**: Testo con almeno 2 paragrafi inserito nella box di testo di Lettore (o copiato negli appunti).
- **Passaggi**:
  1. Cliccare sul pulsante "Riquadri" nella toolbar di cattura (oppure sulla tessera "Identifica Testo" nel menu del megafono).
  2. Osservare l'overlay semi-trasparente a tutto schermo che inquadra i singoli paragrafi con rettangoli tratteggiati luminosi e badge "Riquadro N • X parole".
  3. Passare il mouse sopra uno dei rettangoli e osservare l'evidenziazione e il badge "Ascolta questo riquadro".
  4. Cliccare sul rettangolo prescelto.
- **Esito Atteso**: L'overlay si chiude con animazione fluida, il contenuto del riquadro selezionato viene caricato nel player e la sintesi vocale di quel blocco specifico parte istantaneamente.
- **Esito Fallito**: Nessun riquadro visualizzato, overlay bloccato o click che non avvia la riproduzione.
