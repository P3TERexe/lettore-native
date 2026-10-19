# Patch Dinamica Hardware Acceleration CoreML

**Stato**: Accettata  
**Data**: 2026-09-03

## Contesto & Problema

La libreria `supertonic` istanzia internamente `ort.InferenceSession` richiedendo che sia un tipo (`isinstance(session, ort.InferenceSession)`). Sostituire l'istanza con una funzione wrapper fallisce i controlli di tipo.

## Decisione Presa

Creare una sottoclasse formale `_AcceleratedSession(ort.InferenceSession)` che inietta i provider rilevati (`CoreMLExecutionProvider`, poi `CPUExecutionProvider`) prima di passare gli argomenti al costruttore genitore, assegnandola a `ort.InferenceSession`.

## Alternative Scartate

Monkey-patching con funzione (fallisce l'istanziazione in `supertonic`) o fork della libreria esterna (overhead di manutenzione).

## Conseguenze & Vincoli Intoccabili

Se si aggiorna o si fa refactor dell'import di `onnxruntime`, preservare l'ereditarietà di classe per non disabilitare CoreML.
