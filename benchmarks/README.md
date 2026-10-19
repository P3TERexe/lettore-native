# Benchmark TTS — qualità e velocità

Kit riproducibile per confrontare due versioni, due configurazioni o due modelli
della pipeline TTS locale. Le misure oggettive non sostituiscono l'ascolto: il
protocollo combina latenza, CPU/RAM, metriche audio, WER/CER e una scheda di
ascolto cieco.

## Cosa c'è

| File | Scopo |
| --- | --- |
| `tts_corpus_it.jsonl` | 28 testi italiani divisi per categoria e difficoltà |
| `tts_corpus_it.md` | Vista leggibile dello stesso corpus, senza JSON |
| `../scripts/tts_benchmark.py` | Esegue il corpus via HTTP e confronta due run |
| `../scripts/tts_asr_eval.py` | Trascrive gli audio con whisper.cpp e calcola WER/CER |
| `../scripts/tts_listening_sheet.py` | Crea una scheda A/B cieca con audio neutrali |

Il corpus copre frasi brevi, paragrafi lunghi, numeri, abbreviazioni,
punteggiatura, nomi stranieri, emoji e dialoghi. Ogni riga ha `id`, `category`,
`text` e, dove serve, `asr_reference` con la forma parlata attesa.

## Avvio rapido

### 1. Backend

Dalla root del repository:

```bash
# Baseline sulla porta 7788
.venv/bin/python -m backend.main
```

Per una seconda configurazione, usa un'altra porta e una directory di configurazione
separata:

```bash
LETTORE_PORT=7789 LETTORE_CONFIG_DIR=/tmp/lettore-candidate \
  .venv/bin/python -m backend.main
```

Poi esegui lo stesso comando `run` con `--label candidate` e
`--base-url http://127.0.0.1:7789`.

Il backend parte con il provider **ibrido**: CoreML solo per
`vector_estimator`, CPU per le altre sessioni. I profili disponibili sono:

| Profilo | Comando | Uso consigliato |
| --- | --- | --- |
| `hybrid` (default) | `LETTORE_TTS_PROVIDER=hybrid` | Miglior compromesso latenza/CPU/RAM |
| `cpu` | `LETTORE_TTS_PROVIDER=cpu` | Massimo risparmio RAM (~0,75 GB) |
| `coreml` | `LETTORE_TTS_PROVIDER=coreml` | CoreML su tutte le sessioni |
| `auto` | `LETTORE_TTS_PROVIDER=auto` | CoreML/CUDA se disponibili |

I thread si regolano con `LETTORE_TTS_INTRA_THREADS` (default 4) e
`LETTORE_TTS_INTER_THREADS` (default 1). Per personalizzare le sessioni CoreML
usare `LETTORE_TTS_COREML_SESSIONS` (default `vector_estimator`). Il profilo
`cpu` con `LETTORE_TTS_ALLOW_SPINNING=0` riduce ancora il CPU a costo di
maggiore latenza.

### 2. Esegui il corpus

```bash
.venv/bin/python scripts/tts_benchmark.py run \
  --label baseline \
  --base-url http://127.0.0.1:7788 \
  --output benchmarks/results/baseline.json \
  --passes 1 --runs 3 \
  --save-audio-dir benchmarks/audio
```

- `--runs 3`: la prima richiesta per testo è **cold**, le altre sono **warm**
  (e possono arrivare dalla cache del backend).
- `--passes 2 --runs 1`: due misure cold per testo. Per essere davvero cold, il
  server deve essere riavviato tra le passate.

Per far gestire il ciclo di vita del server al runner:

```bash
.venv/bin/python scripts/tts_benchmark.py run \
  --label baseline \
  --base-url http://127.0.0.1:7790 \
  --server-cmd ".venv/bin/python -m backend.main" \
  --server-env LETTORE_PORT=7790 \
  --server-env LETTORE_CONFIG_DIR=/tmp/lettore-baseline \
  --passes 2 --runs 1 \
  --output benchmarks/results/baseline-cold.json \
  --save-audio-dir benchmarks/audio
```

`--server-cmd` avvia il processo, attende `/v1/status` con `ready: true`, esegue
la passata e lo arresta. Fra una passata e l'altra il server viene riavviato
(`--restart-between-passes`, attivo di default). Usa `--server-log` per
conservare l'output del backend.

### 3. Confronta

```bash
.venv/bin/python scripts/tts_benchmark.py compare \
  --baseline benchmarks/results/baseline.json \
  --candidate benchmarks/results/candidate.json \
  --output benchmarks/results/confronto.md
```

Il report contiene sintesi, dettaglio per categoria, dettaglio per testo e
segnali automatici su livello, clipping e silenzi. La modalità predefinita è
`cold`; usa `--mode warm` o `--mode all` per le altre viste.

## Risultati di riferimento

Misura del 2026-10-19 su M5 10-core / 16 GB, macOS, ONNX Runtime 1.29,
Supertonic 1.3.1, corpus completo, voce M1, 8 step, velocità 1.0. I file JSON
sono in `benchmarks/results/` (ignorati da git).

| Configurazione | Latenza cold | RTF | CPU server | RAM picco |
| --- | ---: | ---: | ---: | ---: |
| CoreML completo (baseline) | 1.690 ms | 6,15x | 8.295 ms | 6.111 MB |
| CPU 4 thread | 1.933 ms | 5,58x | 7.715 ms | 745 MB |
| Ibrido `vector_estimator` | 1.328 ms | 8,13x | 5.290 ms | 4.084 MB |

L'ASR con whisper.cpp `small` in italiano ha misurato WER/CER medi del 15,8%/12,9%
per l'ibrido e del 13,8%/11,8% per il profilo CPU, contro 16,6%/14,5% della
baseline. È un'indicazione di intelligibilità, non una prova di naturalezza:
la scheda di ascolto cieco resta necessaria.

## Qualità

### WER/CER con whisper.cpp

Serve un modello GGML di whisper.cpp e l'eseguibile `whisper-cli`:

```bash
.venv/bin/python scripts/tts_asr_eval.py \
  --results benchmarks/results/candidate.json \
  --whisper-model ~/models/ggml-large-v3.bin \
  --output benchmarks/results/candidate-asr.json
```

Scarica un modello `ggml-*.bin` dalle release di whisper.cpp e indica il percorso
con `--whisper-model`; se l'eseguibile non è nel `PATH`, usa `--whisper-bin`.

WER e CER misurano l'intelligibilità, non la naturalezza. I numeri sono
indicativi: nomi propri, sigle e date possono essere trascritti in forme diverse
anche da un ascoltatore umano. Per i testi con cifre il corpus fornisce una
`asr_reference` in lettere.

### Ascolto cieco A/B

```bash
.venv/bin/python scripts/tts_listening_sheet.py \
  --baseline benchmarks/results/baseline.json \
  --candidate benchmarks/results/candidate.json
```

Lo script copia un campione cold per ogni testo in
`benchmarks/results/listening_audio/` con nomi neutri (`01_A.wav`, `01_B.wav`),
randomizza l'ordine e produce `listening_sheet.csv`. La chiave A/B è in
`listening_key.csv`: aprirla solo alla fine.

Compila le colonne con una scala 1–5 (1 scarso, 5 eccellente):

| Dimensione | Cosa valutare |
| --- | --- |
| Naturalezza | La voce suona umana o sintetica? |
| Intelligibilità | Ogni parola è comprensibile senza sforzo? |
| Prosodia | Ritmo, pause e intonazione sono credibili? |
| Artefatti | Ronzii, click, parole troncate, respiri innaturali? |
| Preferenza | `A`, `B` o `pari` |

Ascolta con gli stessi cuffie/volume, in ordine casuale, senza sapere quale
versione sia A o B. Per un risultato minimamente affidabile servono almeno
10–15 valutazioni per configurazione.

## Che cosa confrontare

- **Release app v0.3.0 vs v0.3.1:** il backend è identico fra i due tag; per la
  sintesi non aspettarti differenze. Usa la telemetria dell'app per primo chunk,
  playback e cache, non questo runner HTTP.
- **Baseline attuale vs branch ottimizzato:** è il caso d'uso principale del kit.
  Avvia i due backend su porte diverse e confronta cold/warm.
- **FP32 vs INT8/FP16, CPU vs CoreML:** usa lo stesso corpus e cambia solo il
  modello/provider nel backend. Verifica sempre la qualità con ASR e ascolto:
  un guadagno di velocità non è accettabile se peggiora la pronuncia.
- **Supertonic 2 vs Supertonic 3:** Supertonic 2 non supporta l'italiano. Per un
  confronto usare testi inglesi (`--lang en`), non questo corpus italiano.

### Confronto con un commit o tag precedente

Per avviare il backend di una versione precedente senza toccare il checkout
corrente:

```bash
git worktree add /tmp/lettore-previous v0.3.0
cd /tmp/lettore-previous
python3 -m venv .venv
.venv/bin/pip install -r backend/requirements.txt
LETTORE_PORT=7789 LETTORE_CONFIG_DIR=/tmp/lettore-previous-config \
  .venv/bin/python -m backend.main
```

Poi esegui il runner con `--base-url http://127.0.0.1:7789`. Se la versione
precedente usa dipendenze diverse, crea un venv separato come sopra invece di
riutilizzare quello del checkout corrente.

## Matrice consigliata

Parti da una configurazione singola, poi allarga solo se serve:

| Variabile | Valori iniziali |
| --- | --- |
| Versione | baseline, candidato |
| Step | 5, 8, 12 |
| Velocità | 1.0, 1.5 |
| Voce | M1, F1 |
| Modalità | cold (2 passate) + warm (3 run) |

La matrice completa è 2 versioni × 3 step × 2 velocità × 2 voci × 28 testi:
troppe richieste per un primo giro. Un buon compromesso è:

1. `steps=8`, `speed=1.0`, `voice=M1`, 2 passate cold.
2. Se il candidato è più veloce, ripeti a `steps=5` e `steps=12`.
3. Solo dopo, verifica `speed=1.5` e la seconda voce.

## Metriche

| Metrica | Significato |
| --- | --- |
| `wall_ms` | Tempo HTTP completo: normalizzazione, coda, sintesi e serializzazione WAV |
| `rtf` | `audio_ms / wall_ms`; sopra 1× la sintesi è più veloce del realtime |
| `server_cpu_ms` | Tempo CPU cumulativo del server, campionato con `ps` |
| `server_peak_rss_mb` | Picco RSS del server, campionato ogni 50 ms |
| `rms_dbfs`, `peak_dbfs` | Livello medio e di picco dell'audio |
| `clipping_pct` | Percentuale di campioni a fondo scala |
| `silence_pct` | Percentuale di campioni sotto −50 dBFS |
| `WER`, `CER` | Errori di parole/caratteri nella trascrizione ASR |

CPU e RAM richiedono `--server-pid` oppure `--server-cmd`; senza PID il report
mostra `n/d`. Su macOS il campionamento usa `ps -o rss=,time=`.

## Note e limiti

- La cache del backend restituisce lo stesso WAV per `(testo, lingua, voce,
  step, velocità)`. La run 0 è cold solo se il server è appena stato avviato.
- La generazione è stocastica: due run possono produrre audio diverso. Confronta
  mediane e distribuzioni, non un singolo campione.
- CoreML compila il grafo alla prima inferenza: il warmup aiuta, ma una misura
  cold dopo il riavvio include ancora quel costo. È corretto misurarlo, ma non
  confonderlo con il costo per frase.
- Il client Swift sintetizza a velocità neutra 1.0 e applica la velocità una
  sola volta al player. Questo runner misura il backend a `--speed`; per la
  velocità percepita nell'app usare la telemetria del primo chunk e della
  riproduzione, non confrontare direttamente run a velocità diverse.
- I risultati e gli audio generati sono ignorati da git
  (`benchmarks/results/` e `*.wav`): non committare artefatti rigenerabili.
- Per un smoke test veloce: `--limit 3 --runs 1`.
