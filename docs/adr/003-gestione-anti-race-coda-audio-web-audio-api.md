# Gestione Anti-Race della Coda Audio Web Audio API

**Stato**: Accettata  
**Data**: 2026-09-03

## Contesto & Problema

La riproduzione sequenziale a chunk su Web Audio API soffre di race conditions: chiamare `.stop()` su un `AudioBufferSourceNode` scatena l'evento `.onended`, che a sua volta chiama `queue.next()`, provocando doppi avanzamenti, sovrapposizioni audio o salti di chunk.

## Decisione Presa

In `ui/src/renderer/player.js`:
  1. Azzerare sempre `source.onended = null` prima di invocare `source.stop()`.
  2. Disconnettere esplicitamente i nodi audio con `source.disconnect()`.
  3. Mantenere una guardia booleana anti-rientranza (`isAdvancing`) su `advance()` e `next()`.

## Alternative Scartate

Affidarsi alla sola gestione automatica del garbage collector o all'evento nativo `ended` senza rimozione preventiva del listener.

## Conseguenze & Vincoli Intoccabili

Non semplificare il ciclo di vita del player audio rimuovendo l'azzeramento del callback prima di fermare la sorgente.
