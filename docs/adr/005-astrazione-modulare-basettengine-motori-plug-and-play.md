# Astrazione Modulare BaseTTSEngine per Motori Vocali Plug-and-Play

**Stato**: Accettata  
**Data**: 2026-09-04

## Contesto & Problema

L'accoppiamento diretto di `TTSManager` con l'implementazione interna della libreria `supertonic` impediva la sostituzione o l'affiancamento trasparente di runtime alternativi (es. Piper, Kokoro, Coqui, PyTorch o provider cloud) senza riscrivere router, API o logica applicativa.

## Decisione Presa

Definire l'interfaccia astratta `BaseTTSEngine` in `backend/engines/base.py` con contratto uniforme (`sample_rate`, `voice_names`, `supported_languages`, `load()`, `unload()`, `synthesize()`, `discover_custom_voices()`). Incapsulare il runtime Supertonic ONNX in `SupertonicONNXEngine` (`backend/engines/onnx_engine.py`) e istanziarlo tramite il factory `create_engine` guidato da configurazione (`LETTORE_ENGINE`).

## Alternative Scartate

Mantenere il codice ONNX direttamente in `TTSManager` con `if/else` per ogni nuovo motore (debito tecnico e violazione Open/Closed Principle).

## Conseguenze & Vincoli Intoccabili

L'applicazione e i router devono dipendere unicamente dall'interfaccia `BaseTTSEngine` e da `TTSManager`. Il lock di serializzazione (ADR-002) e la patch CoreML (ADR-004) devono restare rigorosamente attivi all'interno dell'engine ONNX.
