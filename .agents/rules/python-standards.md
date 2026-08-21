# Standard di Sviluppo Python per Lettore

Questo documento stabilisce le linee guida architetturali e di stile per il backend Python (FastAPI + Supertonic TTS).

---

## 1. Versione e Tipizzazione

* **Target**: Python ≥ 3.10.
* Includere sempre all'inizio di ogni modulo:
  ```python
  from __future__ import annotations
  ```
* Usare la sintassi di tipizzazione moderna di Python:
  * `list[str]`, `dict[str, Any]`, `tuple[int, ...]`
  * Unioni native: `str | None`, `int | float` (evitare `Optional` e `Union` da `typing`).

---

## 2. Modelli Dati & Pydantic v2

* Ereditare da `pydantic.BaseModel`.
* Per creare copie modificate di un modello, utilizzare:
  ```python
  updated_obj = obj.model_copy(update={"status": "done"})
  ```
* Validare i campi con `@field_validator` per garantire payload puliti.

---

## 3. Concorrenza & Thread Safety

* **CPU-bound vs Async I/O**:
  * L'inferenza ONNX TTS è CPU-bound. Non eseguire blocchi ONNX direttamente dentro coroutine `async def` senza delegare al threadpool.
  * Usare funzioni endpoint sincrone `def endpoint(...)` (che FastAPI gestisce automaticamente in un worker thread dedicato) oppure `starlette.concurrency.run_in_threadpool`.
* **Lock e Coda FIFO**:
  * Utilizzare `threading.Lock()` per proteggere lo stato interno di `QueueManager` da letture e scritture concorrenti.

---

## 4. Error Handling & Risposte HTTP

* Non sollevare eccezioni generiche (`Exception`); utilizzare `ValueError`, `RuntimeError` o eccezioni custom.
* Nei router FastAPI, mappare sempre le eccezioni su `HTTPException` con status code appropriati (es. `400` per parametri non validi, `404` per risorse assenti, `503` se il motore TTS è non disponibile).

---

## 5. Tooling & Formattazione

* Utilizzare **Ruff** per il linting e la formattazione automatica (`ruff check` e `ruff format`).
