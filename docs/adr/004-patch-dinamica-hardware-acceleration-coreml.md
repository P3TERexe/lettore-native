# Patch Dinamica Hardware Acceleration CoreML

**Stato**: Accettata  
**Data**: 2026-09-03

## Contesto & Problema

La libreria `supertonic` istanzia internamente `ort.InferenceSession` richiedendo che sia un tipo (`isinstance(session, ort.InferenceSession)`). Sostituire l'istanza con una funzione wrapper fallisce i controlli di tipo.

## Decisione Presa

Creare una sottoclasse formale `_AcceleratedSession(ort.InferenceSession)` che inietta i provider selezionati prima di passare gli argomenti al costruttore genitore, assegnandola a `ort.InferenceSession`. Dal 2026-10-19 il default è ibrido (CoreML solo per `vector_estimator`, CPU per le altre sessioni); vedi [ADR-009](009-provider-ibrido-e-thread-tts.md).

## Alternative Scartate

Monkey-patching con funzione (fallisce l'istanziazione in `supertonic`) o fork della libreria esterna (overhead di manutenzione).

## Conseguenze & Vincoli Intoccabili

Se si aggiorna o si fa refactor dell'import di `onnxruntime`, preservare l'ereditarietà di classe: `supertonic` esegue `isinstance(session, ort.InferenceSession)` e una funzione wrapper fallisce. La selezione dei provider può cambiare tramite `LETTORE_TTS_PROVIDER`, ma la sottoclasse deve restare.
