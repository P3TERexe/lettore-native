## Lettore Native (Fase 3: Native macOS Edition)

Applicazione 100% nativa macOS riscritta in Swift 6 e SwiftUI.

### Novità e Funzionalità
- **Nessuna dipendenza JS/Tauri:** interfaccia leggerissima (<80MB di RAM) e ultra fluida integrata nativamente con AppKit e CoreAudio.
- **Dynamic Island Responsive:**
  - **Al centro dello schermo:** pillola orizzontale compatta (120px) con espansione su hover a 356px.
  - **Ai lati dello schermo (Docking):** morphing automatico in pillola verticale compatta (56x48px) con espansione verso il basso (56x188px).
  - **Progress Bar ad alta precisione:** campionamento a 20Hz sincronizzato in tempo reale con la lettura vocale.
- **Miglioramenti Interfaccia & Docking (v0.3.0):**
  - **Docking verticale fluido:** transizione naturale e continua agganciando la pillola ai bordi dello schermo con isteresi ergonomica.
  - **Trascinamento nativo a 120 FPS:** integrazione con `DraggablePillHostingView` e `performDrag` per un dragging istantaneo senza scatti.
  - **Feedback motore vocale trasparente:** banner di avviso chiaro con motivazione dettagliata in caso di fallback alla voce di sistema Apple Speech.
- **Supporto Multilingua:** selezione dinamica di 5 lingue (Italiano, Inglese, Spagnolo, Francese, Tedesco) con profili vocali dedicati.
- **Accessibility API native:** cattura il testo in millisecondi in background con la scorciatoia globale `⌥ + C` o premendo Play sulla pillola.
- **Firma e Requisiti TCC Stabili:** risolto il bug di macOS che invalidava i permessi di accessibilità dopo gli aggiornamenti.

### ⚠️ Installazione e Permessi di Accessibilità
1. Decomprimi lo zip e sposta **`LettoreNative.app` nella cartella `/Applications`** (Applicazioni).
2. Se macOS blocca l'apertura: fai **Click Destro** sull'app -> **Apri** (oppure da Impostazioni -> Privacy e Sicurezza -> "Apri Comunque").
3. Concedi i permessi in **Impostazioni di Sistema -> Privacy e Sicurezza -> Accessibilità**.
4. **Se i permessi risultano già attivi ma l'app non legge:** elimina `Lettore Native` dalla lista con il tasto **`-` (meno)** e riaggiungila con **`+`**, oppure esegui nel Terminale:
   ```bash
   tccutil reset Accessibility com.p3ter.lettorenative
   ```
