## Lettore Native v0.3.3 (Native macOS Edition)

Release di ottimizzazione software: hot path audio, preparazione del testo, cache e backend. Nessun cambio di interfaccia visibile. Lo zip contiene solo l'app macOS; il backend Supertonic resta nel repository e va avviato localmente sulla porta `7788`.

### Cosa cambia

- **Skip e jump senza doppia sintesi:** la cancellazione della riproduzione conserva il prefetch, quindi un chunk non viene più sintetizzato due volte.
- **Onda e metering:** la waveform è isolata in una view dedicata, le barre restano a 20 Hz e il progresso scende a 5 Hz; l'aggiornamento dell'onda non ricostruisce più Studio, Pillola e Notch.
- **Testo più leggero:** regex precompilate in `TextNormalizer`, `DocumentNoiseFilter` e `ViewportTextCollector`; mappatura tra testo filtrato e originale con ricerca binaria, quindi O(log n) invece di lineare.
- **Cache L2 più prevedibile:** budget di spazio garantito anche con scritture concorrenti, meno I/O sul percorso di lettura (la scrittura avviene fuori dal lock) ed eviction su coda in background.
- **Paging AX:** meno attraversamenti DFS, polling economico della scrollbar e stato di fine scroll calcolato una volta sola.
- **Backend:** cap della richiesta a 1000 caratteri; oltre soglia arriva un 422, anche quando il testo normalizzato supera il cap o quando una singola frase supera 900 caratteri (300 per il coreano), con lo stesso errore di validazione della richiesta. Errori ONNX/CoreML mappati a 503, rimossi warmup e override del silenzio tra chunk.

### Requisiti

- **Mac Apple Silicon (arm64):** il binario non è universale, la build è `arm64` thin (`lipo -archs` riporta solo `arm64`). Su Intel occorre compilare dal sorgente.
- macOS 14 Sonoma o successivo.
- Python 3.10+ (solo per il backend TTS).
- Backend Supertonic locale sulla porta `7788`: **non incluso nello zip**, va avviato dal repository.
- Se il backend non è attivo, l'app usa la voce di sistema come fallback.
- Circa 3–5 GB liberi su disco: il primo avvio del backend scarica il modello (~400 MB) e servono spazio per l'ambiente Python e la cache audio.

### Backend (primo avvio)

Su un Mac senza l'ambiente già pronto, dalla root del repository:

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cd ..
python -m backend.main
```

Alla prima esecuzione il backend scarica il modello Supertonic (~400 MB) e resta in ascolto su `127.0.0.1:7788`; le volte successive il download non viene ripetuto.

### Installazione

1. Decomprimi lo zip e sposta **`LettoreNative.app` nella cartella `/Applications`**.
2. Apri l'app e, se macOS blocca il primo tentativo, vai in **Impostazioni di Sistema -> Privacy e Sicurezza**, scorri fino alla sezione **Sicurezza** e clicca **"Apri Comunque"** (su macOS 15 e successivi è il percorso da usare dopo il primo tentativo; sulle versioni precedenti funziona anche **Click Destro** sull'app -> **Apri**).
3. Al primo avvio l'app chiede l'autorizzazione **Accessibilità**: concedila in **Impostazioni di Sistema -> Privacy e Sicurezza -> Accessibilità**.
4. Per provare subito la lettura, seleziona un testo in qualsiasi app e premi **Opzione (⌥) + C**.
5. Se i permessi risultano già attivi ma l'app non legge, elimina `Lettore Native` dalla lista con `-` e riaggiungila con `+`, oppure esegui:
   ```bash
   tccutil reset Accessibility com.p3ter.lettorenative
   ```

### Verifiche

- `swift test`: 256/256.
- `swift test` con Thread Sanitizer: 256/256.
- Test backend: 60/60.
- `ruff check` e `validate_repo_docs` puliti.
- Bundle firmato ad-hoc, `codesign`, `plutil` e `lipo` verificati.
- SHA-256 dello zip: `d820a9a9a2a3d227af73e01fdd75a5250e7760ab8e6b72e95c4382e1b2bc8394`
