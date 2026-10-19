## Lettore Native v0.3.2 (Native macOS Edition)

Aggiornamento dedicato alle prestazioni del motore TTS e ai requisiti hardware. La build macOS include le ottimizzazioni lato app; il backend Supertonic ottimizzato è nel repository e va avviato localmente sulla porta `7788`.

### Prestazioni TTS

- **Provider ibrido predefinito:** CoreML solo per `vector_estimator`, CPU per `duration_predictor`, `text_encoder` e `vocoder`. Rispetto al profilo CoreML completo, sul corpus di 28 testi italiani: **latenza mediana -21,4%**, **CPU -36,2%**, **RAM di picco -33,2%**.
- **Profilo CPU per Mac da 8 GB:** circa **745 MB** di RAM per il motore TTS, con latenza mediana di 1,93 s sul corpus (M5). È più lento del profilo CoreML completo, ma molto più leggero.
- **Cache e prefetch:** eliminata la sintesi duplicata della frase corrente, invalidati i prefetch quando cambiano voce o step, corretta la chiave cache del primo chunk e pubblicata la cache dentro il lock di inferenza.
- **Velocità applicata una sola volta:** il backend sintetizza sempre a `1.0x`; la velocità viene applicata dal player (`0,5x–2,0x`), senza doppia accelerazione.
- **Thread CPU configurabili:** default 4 thread intra-op e 1 inter-op; `LETTORE_TTS_ALLOW_SPINNING=0` riduce il consumo CPU a costo di un po' di latenza.

### Requisiti hardware

| Profilo | Mac consigliato | RAM TTS | Prima frase | Note |
| --- | --- | --- | --- | --- |
| **Minimo consigliato** | MacBook Air M1 · 8 GB | ~0,75 GB | 2–4 s (stima) | Avvia il backend con `LETTORE_TTS_PROVIDER=cpu` |
| **Ideale** | Apple Silicon · 16 GB | ~4,1 GB | ~1,3 s (misurato su M5) | Profilo ibrido, predefinito |
| **Solo compatibilità** | Intel i5 8ª gen · 8 GB | ~0,75 GB | 5–10 s (stima) | Non consigliato per nuovi acquisti |

- macOS 14 Sonoma o successivo.
- Almeno 3 GB liberi, meglio 5 GB (modello ~400 MB, ambiente Python e cache audio).
- 4 GB di RAM non sono consigliati.
- **Windows/Linux:** non ancora supportati. Per un eventuale port del solo motore TTS: CPU 4 core/8 thread con AVX2, 8 GB di RAM (16 GB consigliati su Windows) e 5 GB liberi; una GPU dedicata è opzionale.

### Installazione

1. Decomprimi lo zip e sposta **`LettoreNative.app` nella cartella `/Applications`**.
2. Se macOS blocca l'apertura: **Click Destro** sull'app -> **Apri** (oppure da Impostazioni -> Privacy e Sicurezza -> "Apri Comunque").
3. Avvia il backend Supertonic locale (`backend/`, porta `7788`). La release contiene l'app macOS compilata, non il runtime Python.
4. Concedi i permessi in **Impostazioni di Sistema -> Privacy e Sicurezza -> Accessibilità**.
5. Se i permessi risultano già attivi ma l'app non legge, elimina `Lettore Native` dalla lista con `-` e riaggiungila con `+`, oppure esegui:
   ```bash
   tccutil reset Accessibility com.p3ter.lettorenative
   ```

### Verifiche

- `ruff check` e `ruff format --check`.
- 38 test backend e 36 test Swift.
- Validatore repo-docs.
- Bundle firmato ad-hoc, `codesign --verify --deep --strict`, `plutil` e `lipo -archs` verificati.
