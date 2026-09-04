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
