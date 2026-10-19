# Serializzazione dell'Inferenza ONNX con Lock Sincrono

**Stato**: Accettata  
**Data**: 2026-09-03

## Contesto & Problema

`onnxruntime` non è thread-safe per sessioni di inferenza condivise su CPU o CoreML quando chiamato simultaneamente da coroutine asincrone o thread multipli.

## Decisione Presa

Mantenere `TTSManager` come singleton in `backend/tts_manager.py` con una singola istanza caricata in RAM e proteggere ogni invocazione di `synthesize()` con `threading.Lock()` sincrono.

## Alternative Scartate

Sessioni multiple di ONNX Runtime in parallelo (consumo insostenibile di RAM, ~400MB per istanza) o chiamate async non protette (crash di memoria o segfault C++).

## Conseguenze & Vincoli Intoccabili

Non rimuovere mai `with self._lock:` nel metodo di sintesi e non istanziare il modello dentro route async di FastAPI.
