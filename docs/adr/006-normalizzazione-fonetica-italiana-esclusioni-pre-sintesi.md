# Pipeline di Normalizzazione Fonetica Italiana ed Esclusioni Pre-Sintesi

**Stato**: Accettata  
**Data**: 2026-09-04

## Contesto & Problema

Il modello neurale TTS pronuncia i testi in modo letterale. Sigle, abbreviazioni frequenti (`Dott.`, `Prof.`, `Art.`), importi con valuta (`12.50€`), orari (`14:30`), link (`http://...`) e firme o disclaimer di posta ("Inviato da iPhone") generano un ascolto frammentato, sgradevole o incomprensibile per utenti con disabilità visiva o cognitiva.

## Decisione Presa

Implementare `TextNormalizer` in `backend/textnorm/normalizer.py` con una pipeline a due fasi:
  1. `filter_exclusions`: rimozione pulita di stringhe esatte/pattern blacklistati configurati dall'utente, normalizzando punteggiatura orfana o doppi punti.
  2. `normalize_italian`: catena di espansione fonetica deterministica (30 regole ad alta frequenza per la lingua italiana).
  Applicare la normalizzazione a monte della segmentazione (`smart_chunk_text`) e della sintesi vocale su `/v1/queue` e `/v1/tts`.

## Alternative Scartate

Normalizzazione demandata al frontend (risulterebbe disallineata rispetto ad esportazioni WAV o chiamate dirette API) oppure affidata a modelli LLM pesanti (latenza e consumo CPU incompatibili con TTS in tempo reale).

## Conseguenze & Vincoli Intoccabili

La normalizzazione deve avvenire prima dello smart chunking, affinché le frasi espanse non vengano spezzate erroneamente a metà di un numero o di una valuta.
