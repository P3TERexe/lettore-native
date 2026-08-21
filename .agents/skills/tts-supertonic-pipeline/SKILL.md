---
name: tts-supertonic-pipeline
description: >-
  Guida e procedure per l'ottimizzazione del runtime TTS Supertonic 3 via ONNX Runtime,
  calibrazione della sintesi (steps, speed, quality), gestione delle voci personalizzate
  e streaming chunk-by-chunk.
---

# Supertonic TTS Pipeline Skill

Questa skill fornisce le linee guida architetturali e operative per gestire e ottimizzare il motore **Supertonic 3** nel progetto Lettore.

---

## 1. Caratteristiche del Modello

* **Architettura**: Modello ONNX Runtime on-device (~99M parametri, ~400MB scaricato automaticamente da Hugging Face).
* **Lingue**: 31 lingue supportate nativamente con codici ISO (`it`, `en`, `es`, `fr`, `de`, `ja`, `zh`, ecc.) + fallback `na` per lingue non identificate.
* **Voci built-in**: 10 stili predefiniti (5 maschili `M1`–`M5`, 5 femminili `F1`–`F5`).

---

## 2. Best Practices di Configurazione e Performance

### Calibrazione `total_steps` (Qualità vs Latenza)
* **Default consigliato**: `8` (ottimo bilanciamento tra naturalezza e velocità).
* **Lettura veloce in tempo reale**: `5` o `6` (riduce del 30-40% il tempo di sintesi per chunk lunghi).
* **Massima fedeltà audio / Export WAV**: `10`–`12`.

### Calibrazione `speed`
* Range supportato: `0.7` – `2.0` (default: `1.05`).

### Singola Istanza (Singleton Pattern)
Il modello deve essere caricato una sola volta all'avvio del backend e mantenuto in RAM (`TTSManager` singleton in `backend/tts_manager.py`). Non re-istanziare mai `TTS(auto_download=True)` durante le richieste HTTP.

---

## 3. Gestione Voci Personalizzate (Voice Builder)

* **Directory custom styles**: `~/.cache/supertonic3/custom_styles/<nome>.json`.
* Le voci personalizzate esportate dal Supertone Voice Builder possono essere caricate direttamente passando il file JSON o registrandole in `voices.json`.
* Se una voce custom non definisce una lingua specifica, deve essere considerata multilingue con fallback `na`.

---

## 4. Pipeline di Streaming e Chunking

Per documenti lunghi:
1. Suddividere il testo in chunk di 1–3 frasi con `backend.chunking.smart_chunk_text`.
2. Inviare il **Chunk 0** per la sintesi immediata (ottenendo riproduzione in <300ms).
3. Pre-sintetizzare il **Chunk 1** in background mentre il Chunk 0 è in riproduzione nel Web Audio player.
