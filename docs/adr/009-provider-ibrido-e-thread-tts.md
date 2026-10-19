# Provider TTS ibrido e configurazione thread

**Stato**: Accettata  
**Data**: 2026-10-19

## Contesto & Problema

La pipeline TTS locale usava CoreML per tutte le sessioni ONNX. La scelta
privilegiava la latenza, ma su un MacBook con 16 GB di RAM il picco del processo
arrivava a circa 6,1 GB e il costo CPU restava alto. Il solo CPU
(`CPUExecutionProvider`) riduceva la RAM a circa 0,75 GB, ma risultava più lento
della baseline sui testi brevi e medi.

Il benchmark riproducibile `scripts/tts_benchmark.py` è stato eseguito su
M5 10-core / 16 GB con lo stesso corpus italiano di 28 testi, voce M1,
8 step e velocità 1.0. I valori sono mediane cold; CPU e RAM sono campionati
sul processo backend.

| Configurazione | Latenza cold | RTF | CPU server | RAM picco |
| --- | ---: | ---: | ---: | ---: |
| CoreML su tutte le sessioni (baseline) | 1.690 ms | 6,15x | 8.295 ms | 6.111 MB |
| CPU, 4 thread | 1.933 ms | 5,58x | 7.715 ms | 745 MB |
| Ibrido, CoreML solo `vector_estimator` | 1.328 ms | 8,13x | 5.290 ms | 4.084 MB |

Sui testi lunghi l'ibrido è risultato circa il 40% più rapido della baseline;
sui testi brevi circa il 25% più rapido. Il controllo ASR con whisper.cpp
(`small`, italiano) non ha mostrato regressioni su nessun profilo:

| Profilo | WER medio | CER medio |
| --- | ---: | ---: |
| CoreML completo (baseline) | 16,6% | 14,5% |
| Ibrido `vector_estimator` | 15,8% | 12,9% |
| CPU 4 thread | 13,8% | 11,8% |

Le differenze sono in parte dovute alla natura stocastica della sintesi; il
dato rilevante è l'assenza di un peggioramento sistematico.

Sono stati provati anche 6 e 8 thread CPU: entrambi peggiorano rispetto a 4
thread. `ModelFormat=MLProgram` fallisce la compilazione CoreML su questo
modello; `MLComputeUnits=CPUAndGPU`/`ALL` non migliorano la RAM in modo
significativo. INT8 resta escluso dal default per il rischio qualità.

## Decisione Presa

- Il provider predefinito è **ibrido**: CoreML solo per `vector_estimator`,
  CPU per `duration_predictor`, `text_encoder` e `vocoder`.
- Il comportamento è controllato da:
  - `LETTORE_TTS_PROVIDER=hybrid|cpu|coreml|auto` (default `hybrid`);
  - `LETTORE_TTS_COREML_SESSIONS` (default `vector_estimator`);
  - `LETTORE_TTS_INTRA_THREADS` (default 4);
  - `LETTORE_TTS_INTER_THREADS` (default 1).
- `LETTORE_TTS_PROVIDER=cpu` è il profilo a minima RAM (circa 0,75 GB).
- La patch `_AcceleratedSession` di ADR-004 resta obbligatoria: `supertonic`
  verifica `isinstance(session, ort.InferenceSession)`.
- La velocità di ascolto è applicata una sola volta dal player; il backend
  sintetizza a velocità neutra 1.0. Questo evita la doppia velocizzazione e
  rende la cache indipendente dalla velocità scelta.

## Alternative Scartate

- **CoreML su tutte le sessioni**: più RAM e, con questo modello, più lenta
  dell'ibrido.
- **Solo CPU**: RAM eccellente, ma latenza peggiore della baseline.
- **6/8 thread CPU**: più CPU e latenza peggiore.
- **INT8**: guadagno di velocità ma correlazione spettrale bassa e rischio
  qualità non verificato sull'italiano.
- **MLProgram CoreML**: errore di compilazione del modello.

## Conseguenze & Vincoli

- Il default sfrutta CoreML quando disponibile; su macchine senza CoreML il
  provider cade automaticamente su CPU.
- La RAM resta più alta del profilo CPU: per ambienti con poca memoria usare
  `LETTORE_TTS_PROVIDER=cpu`.
- I numeri sono specifici di M5 / ONNX Runtime 1.29 / Supertonic 1.3.1 e vanno
  riverificati dopo aggiornamenti del runtime o del modello.
- La cache di primo chunk usa gli step effettivi (5 con boost) nella chiave,
  quindi non riusa audio a 8 step come se fosse a 5.
