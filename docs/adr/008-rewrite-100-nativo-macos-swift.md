# Rewrite 100% Nativo macOS in Swift, AppKit, SwiftUI e AVAudioEngine

**Stato**: Accettata (Branch `rewrite/100-native`)  
**Data**: 2026-09-09

## Contesto & Problema

L'architettura ibrida Tauri 2 + Rust + Python FastAPI sidecar + WebKit JS comporta ~450 MB di consumo RAM, 2.5s di avvio, overhead di serializzazione HTTP/IPC e impossibilità di sfruttare nativamente l'Apple Neural Engine (ANE) e le interazioni pixel-perfect di sistema come il Dynamic Notch hardware e le finestre `.nonactivatingPanel`.

## Decisione Presa

Avviare sul branch dedicato `rewrite/100-native` la riprogettazione e riscrittura completa in un'applicazione **100% nativa macOS**:
  1. **Linguaggio & UI**: Swift 6, SwiftUI e AppKit per finestre native (`NotchWindowController`, `FloatingPillController` a molla elastica e `StudioWindowController`).
  2. **Pipeline Audio**: `AVAudioEngine` e `AVAudioPlayerNode` per streaming di campioni PCM a 24 kHz gapless con `AVAudioUnitTimePitch` per velocità a formanti preservate.
  3. **TTS & Inferenza**: Esecuzione locale diretta di Supertonic 3 tramite binding Swift di ONNX Runtime C-API con accelerazione CoreML/Metal (e futuro CoreML puro).
  4. **NLP & Chunking**: `NaturalLanguage.framework` nativo per la segmentazione frasi in sostituzione di `pySBD`.
  5. **Accessibilità di Sistema**: Integrazione diretta con `AXUIElement` e Apple `Vision.framework` senza intermediari.
  Specifiche tecniche dettagliate in [`dev-docs/progettazione-100-native.md`](../../dev-docs/progettazione-100-native.md).

## Alternative Scartate

Mantenere l'architettura ibrida (troppo pesante per un'utility di lettura continua in background); usare Electron o Flutter (ancora più pesanti e privi di integrazione hardware con la tacca).

## Conseguenze & Vincoli Intoccabili

Il rewrite si sviluppa nel branch dedicato `rewrite/100-native` senza rompere il branch principale `main` fino al raggiungimento della parità di feature e dei benchmark di stabilità.
