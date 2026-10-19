# Universal Reading Layer con Fallback a 3 Livelli (AX -> Clipboard -> Vision OCR) e Layout Analysis Deterministica

**Stato**: Accettata  
**Data**: 2026-09-05

## Contesto & Problema

Per utenti con dislessia, cecità, ipovisione o ridotta alfabetizzazione, il semplice paradigma "seleziona, copia e ascolta" è insufficiente. Le applicazioni esterne possono esporre il testo tramite Accessibility API, solo tramite clipboard, oppure non esporlo affatto (canvas, PDF scansionati, grafici o app non accessibili). Inoltre, una stringa di testo continua priva di struttura impedisce la navigazione semantica (saltare ai titoli, elenchi, paragrafi o citazioni).

## Decisione Presa

  1. Implementare una pipeline di acquisizione a 3 livelli ordinata per affidabilità e velocità:
     - **Livello 1**: macOS Accessibility (`AXUIElement` in Rust) per estrarre l'albero visivo della finestra target (ruoli `AXHeading`, `AXParagraph`, `AXStaticText`, ecc., testo e coordinate a schermo).
     - **Livello 2**: Fallback su selezione/clipboard per app senza albero AX completo.
     - **Livello 3**: Fallback su screenshot finestra (`screencapture -l`) e riconoscimento OCR offline tramite il framework nativo di macOS **Apple Vision** (`VNRecognizeTextRequest`).
  2. Incapsulare l'analisi del layout in `backend/blocks/layout_analyzer.py`: un algoritmo deterministico locale (100% offline, zero dipendenze LLM pesanti) che raggruppa linee contigue e classifica i blocchi in `heading`, `paragraph`, `list_item`, `quote`, `code`, normalizzandoli con `TextNormalizer`.
  3. Esporre il comando Tauri `capture_universal_blocks` e gli endpoint REST `/v1/blocks/analyze` e `/v1/blocks/ocr`.
  4. Riprogettare l'interfaccia in un **Universal Reading Layer** a schede semantiche navigabili da tastiera (`ArrowDown`/`ArrowUp`, `Cmd+T` per i titoli, `Invio`/`Spazio` per ascoltare) con supporto completo screen reader via live region ARIA e stili calibrati per i 4 profili di accessibilità.

## Alternative Scartate

Affidarsi esclusivamente all'OCR (lento ed energivoro se l'app è già accessibile via AX), usare modelli LLM per il layout (latenza di secondi e dipendenze enormi), o limitarsi alla sola visualizzazione interna del testo locale.
