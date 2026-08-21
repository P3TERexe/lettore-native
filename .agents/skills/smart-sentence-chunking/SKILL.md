---
name: smart-sentence-chunking
description: >-
  Guida e procedure per la segmentazione intelligente del testo e disambiguazione dei
  confini di frase con pySBD per la riproduzione fluida con modelli TTS.
---

# Smart Sentence Chunking Skill

Questa skill descrive l'approccio alla segmentazione del testo per alimentare la coda di sintesi vocale (TTS) in maniera naturale e priva di artefatti.

---

## 1. Perché la segmentazione intelligente è necessaria

I metodi tradizionali di split del testo (`text.split('.')` o regex ingenue) falliscono frequentemente su:
* **Titoli e abbreviazioni**: *Dott.*, *Prof.*, *es.*, *p. 55*, *Inc.*, *vs.*
* **Numeri decimali e valute**: *12.50 €*, *$3.14*, *v1.2.0*
* **Punti di sospensione e citazioni**: *"...disse."*
* **Elenchi puntati / numerati**: *1. Primo punto 2. Secondo punto*

Spezzare su questi punti fa sì che il modello TTS sintetizzi frammenti incompleti (es. "Dott" come parola isolata), causando pause innaturali ed errori di prosodia.

---

## 2. Utilizzo di `pySBD` (Python Sentence Boundary Disambiguation)

`pySBD` implementa le *Golden Rules* di segmentazione per oltre 22 lingue senza richiedere pesanti modelli neurali.

### Esempio di utilizzo
```python
import pysbd

def split_into_sentences(text: str, lang: str = "it") -> list[str]:
    # pySBD supporta codici ISO come 'it', 'en', 'es', 'fr', 'de', ecc.
    supported_langs = {"en", "it", "es", "fr", "de", "pt", "ru", "ja", "zh", "nl", "pl", "ro", "da", "el", "sk"}
    target_lang = lang if lang in supported_langs else "en"
    
    segmenter = pysbd.Segmenter(language=target_lang, clean=False)
    sentences = segmenter.segment(text)
    return [s.strip() for s in sentences if s.strip()]
```

---

## 3. Strategia di Raggruppamento per il TTS

* **Frasi singole**: Ideale per chunk in streaming (massima reattività).
* **Paragrafi coesi**: Raggruppare 2–3 frasi correlate se ciascuna è molto breve (< 40 caratteri) per garantire un ritmo vocale continuo.
* **Preservazione Lingua**: Quando la lingua è `Auto`, `langdetect` deve valutare preferibilmente l'intero testo o il primo paragrafo prima di procedere allo split, evitando che frasi troppo brevi (< 10 caratteri) causino falsi positivi nel rilevamento linguistico.
