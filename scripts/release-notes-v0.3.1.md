## Lettore Native v0.3.1 (Native macOS Edition)

Aggiornamento di correzione dedicato alla pillola fluttuante e alla lettura della selezione. Nessun cambiamento al formato dei dati: basta sostituire l'app in `/Applications`.

### Cosa c'è di nuovo

- **Lettura della selezione ripristinata:** il pulsante Play in idle cattura sempre il testo selezionato nell'app in primo piano (Accessibility API, con fallback agli appunti via `Cmd+C`). Se non c'è testo, riprende la coda sospesa invece di restare muto.
- **Sintesi senza blocchi:** una nuova richiesta di lettura annulla la sintesi ancora in volo, invece di essere ignorata.
- **Click più tollerante:** la soglia tap/pausa è passata da 3 a 8 px, così il tremolio della mano non trasforma un click in un trascinamento.
- **Nessun furto di focus:** la pillola non diventa più key window; la cattura resta puntata sull'app da cui hai selezionato il testo.
- **Morphing live pulito ai bordi:** il docking ora segue la posizione del cursore e non il bordo della finestra. La pillola espansa non viene più agganciata con ~265 px di anticipo, il cambio orizzontale ↔ verticale durante il drag è istantaneo (niente forme sovrapposte) e il bordo superiore resta fermo (eliminata la deriva di 6 px a ogni morph).
- **Drag più prevedibile:** trascinamento manuale 1:1 con il cursore, isteresi di aggancio 60/130 px e sgancio che riporta la capsula sotto il puntatore.
- **Qualità:** 35 test automatici, 0 failure, più verifiche end-to-end su TextEdit e Brave con sintesi Supertonic.

### Requisiti

- macOS 14 Sonoma o successivo.
- Backend Supertonic locale sulla porta `7788` per la sintesi neurale; in assenza, l'app usa la voce di sistema come fallback.

### ⚠️ Installazione e Permessi di Accessibilità

1. Decomprimi lo zip e sposta **`LettoreNative.app` nella cartella `/Applications`** (Applicazioni).
2. Se macOS blocca l'apertura: fai **Click Destro** sull'app -> **Apri** (oppure da Impostazioni -> Privacy e Sicurezza -> "Apri Comunque").
3. Concedi i permessi in **Impostazioni di Sistema -> Privacy e Sicurezza -> Accessibilità**.
4. **Se i permessi risultano già attivi ma l'app non legge:** elimina `Lettore Native` dalla lista con il tasto **`-` (meno)** e riaggiungila con **`+`**, oppure esegui nel Terminale:
   ```bash
   tccutil reset Accessibility com.p3ter.lettorenative
   ```
