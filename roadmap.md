# Roadmap — Lettore: Accessibilità & Cross-Platform

**Piano v2** — MVP 7 settimane + visione post-release. Target #1: **accessibilità / inclusione**. Strategia: **2 piattaforme eccellenti (macOS + Windows), Linux best-effort**. Struttura a 2 track invece di fasi sequenziali monolitiche, con **gate di uscita misurabili** per ogni fase.

---

# TRACK 1 — MVP (Settimane 0–7)

## Settimana 0 — Gate di definizione 🆕

Mezza settimana, prima di scrivere codice.

| Task | Output |
|---|---|
| 3–4 sessioni di test con utenti reali (screen reader / dislessia): cosa odiano delle app TTS esistenti? Perché le hanno abbandonate? | Lista prioritizzata di "accessibility pain points" che valida o rimescola le settimane successive |
| Definizione metriche di successo misurabili | Es. "task completato al 100% con VoiceOver solo tastiera", "LCP pannello < 200ms" |

> ⚠️ Se non si riesce a reclutare utenti, questo gate diventa il collo di bottiglia: va pianificato per primo (associazioni, UICI, community dyslexia).

---

## Settimane 1–3 — Accessibilità + Windows ⚡

Tutto l'accessibility core, con **test aXe-core in CI dal giorno 1** (non a fine fase).

| Task | Dettagli | Verifica |
|---|---|---|
| Screen reader support completo | `role="button"`, `aria-label`, `aria-live="polite"` su stato coda/player; `aria-pressed` su toggle; focus visible (`:focus-visible`); skip link | Test VoiceOver (macOS), NVDA/Narrator (Win) |
| Navigazione solo tastiera | Tab order logico; Esc chiude pannelli; ←/→ naviga frasi; ↑/↓ velocità/volume; Home/End primo/ultimo | Tastiera-only: zero mouse |
| Tema Alto Contrasto + Font Dyslexia | CSS custom properties per `--font-family: 'OpenDyslexic', system-ui`; `--contrast: high`; media query `prefers-contrast: more` | `prefers-reduced-motion` disabilita animazioni |
| Annunci di stato (Live Regions) | `aria-live="assertive"` per "Pronto", "Caricamento modello 45%", "Errore backend" | Non interrompere lettura in corso |
| First-run wizard accessibile | Step 1: permessi AX/UIA con link diretti; Step 2: test voce + scorciatoie; Step 3: scegli tema/contrasto | Completabile solo tastiera + screen reader |

### Cross-platform (ridotto a 2 piattaforme eccellenti)

| Piattaforma | Cattura testo | Accelerazione HW | Sidecar build |
|---|---|---|---|
| macOS | AX (già fatto) | CoreML (già fatto) | PyInstaller `--onefile` arm64/x64 |
| Windows | UIA (`tauri-plugin-windows-ui-automation` o `uia-client` Rust) | DirectML (`onnxruntime-directml`) | PyInstaller x64 + NSIS installer |
| Linux | ⚠️ Solo fallback clipboard, documentato come noto limite | CPU (`onnxruntime`) | AppImage "best effort", non promessa |

- **CI/CD**: GitHub Actions matrix (macOS-latest, windows-latest; ubuntu solo build check).
- **Config unificata**: `BackendConfig` rileva provider disponibili (`CoreMLExecutionProvider`, `DmlExecutionProvider`, `CPUExecutionProvider`) → auto-seleziona il migliore, fallback silenzioso a CPU.
- **Prerequisito Windows**: macchina fisica o VM usabile per testare UIA interattivamente — sviluppare UIA "alla cieca" su CI è quasi garantito che fallisca.

### Architettura

```
src-tauri/
├── src/
│   ├── capture/
│   │   ├── macos_ax.rs      // esistente
│   │   ├── windows_uia.rs   // NUOVO
│   │   └── mod.rs           // trait CaptureProvider + factory per OS
│   └── sidecar.rs           // rileva OS → provider cattura + provider ONNX
backend/
├── textnorm/                // NUOVO modulo Python
│   ├── rules_it.yaml
│   └── normalizer.py
└── tts_manager.py           // usa normalizer se config.enabled
```

### ✅ Gate di uscita Settimana 3
Un utente VoiceOver completa il flusso cattura→lettura senza mouse e senza aiuto.

---

## Settimane 4–5 — Smart Capture Pipeline (solo italiano) 🎯

Normalizza il testo prima del TTS: l'utente non deve ascoltare "Dott. Rossi pagò 12.50€ su http://site.com" → sente "Dottore Rossi ha pagato dodici euro e cinquanta centesimi su link".

| Componente | Implementazione |
|---|---|
| Normalizzatore IT | **Partire dalle ~30 regole che coprono il 90% dei casi reali** (frequenza misurata su testo italiano reale), non da 100 casi teorici: abbreviazioni, valute, date, numeri, URL/email, ordinali |
| Integrazione pipeline | `capture_selection → normalize(text, lang) → smart_chunk_text → queue` |
| Config utente | Toggle "Normalizza testo" + dizionario personale (es. "Dr." → "Dottore") |
| Esclusione di testo | Filtro configurabile di stringhe o pattern esatti da eliminare/ignorare prima della sintesi (es. disclaimer, boilerplate, firme) |
| "Leggi da qui" (Cattura da cursore) | Cattura a partire dalla posizione del cursore nel documento attivo in avanti, senza obbligo di selezione estesa manuale |
| Test regression | Suite frasi ambigue IT-specifiche: decimali con virgola, "1°", "n. 12/2024", orari, valute |

**Perché accessibilità**: utenti screen reader sentono testo "pulito" → meno carico cognitivo, niente "http due punti slash slash…".

### ✅ Gate di uscita Settimana 5
Ascolto cieco A/B — 5 frasi "difficili" normalizzate vs raw: l'utente preferisce la normalizzata.

---

## Settimana 6 — Quick win + validazione 🆕

Le feature a basso sforzo / alto impatto rimaste fuori dalle settimane precedenti:

1. **Anteprima voce istantanea** — pulsante ▶️ accanto a ogni voce; endpoint `/v1/tts/preview?voice=M1&lang=it` con step bassi.
2. **Media keys + controlli globali** — Play/Pause toggle, Next salta frase, Previous ripeti frase.
3. **Esportazione MP3 + metadati** — FFmpeg nel sidecar, tag ID3, `Content-Disposition: attachment`.
4. **Icona Megafono (Tray & Titlebar)** — icona menubar/tray e barra superiore sostituita con megafono dedicato e riconoscibile.
5. **Player minimale a barra singola** — modalità ultra-compatta con sola barra di avanzamento, onde vocali animate (waveform lines) e controlli play/pausa.
Poi: **secondo round di test utenti** (stessi 3–4 soggetti della settimana 0) sulle novità delle settimane 4–5.

---

## Settimana 7 — Polish & release MVP ✨

- Installer firmati: macOS notarization + firma Windows. Linux: AppImage best-effort.
- Documentazione accessibile (HTML semantico).
- **Telemetria: default OFF**, consenso esplicito e granulare (solo crash report vs usage) — coerente col posizionamento privacy del progetto.
- Release note in italiano + inglese.

---

# TRACK 2 — Visione v2 (post-release)

Priorità ridefinita dal feedback reale degli utenti MVP:

1. **Linux nativo** (AT-SPI + OpenVINO) — solo se i dati mostrano domanda reale
2. **Navigazione strutturata + resume** — schema robusto: anchor basato su posizione frase nel chunk + fingerprint fuzzy (non hash fragile che rompe al minimo cambio di selezione). Navigazione per unità semantiche: Ctrl+Freccia = paragrafo, Alt+Freccia = frase, Shift+Freccia = parola. Esportazione capitoli da heading Markdown/HTML.
3. **Smart Capture multilingua** (EN, poi ES/FR/DE)
4. **"Leggi e Traduci"** (Live Translation TTS) — killer feature rimandata ma tenuta calda: selezioni testo EN → senti IT con stessa voce, zero cloud. Serve language detect + traduzione locale (argostranslate / MarianMT ~300MB).
5. **"Modalità Studio Lingue"** (Listen-Repeat-Score) — la più rischiosa, per ultima: TTS → utente ripete al microfono → ASR locale (whisper.cpp tiny) → feedback pronuncia + score, loop automatico (~150MB sidecar).

---

## Miglioramenti UX prioritari (impact/effort)

1. **First-run wizard** (alto impatto, medio sforzo) — onboarding 3 step: permessi, test voce, hotkey reminder. *(Settimane 1–3)*
2. **Anteprima voce istantanea** (alto impatto, basso sforzo) — pulsante ▶️ accanto a ogni voce. *(Settimana 6)*
3. **Gestione coda visibile e manipolabile** (alto impatto, medio) — drag-handle riordino, rimozione singola, svuota tutto; endpoint `DELETE /v1/queue/{id}`, `PATCH /v1/queue/reorder`. *(Settimane 1–3)*
4. **Feedback backend visibile** (medio impatto, basso) — toast/banner: "Avvio motore TTS…" → "Download modello (400 MB)… 23%" → "Pronto". *(Settimane 1–3)*
5. **Media keys + controlli globali** (medio impatto, medio) — Play/Pause toggle, Next salta frase, Previous ripeti frase. *(Settimana 6)*
6. **Esportazione MP3/OGG + metadati** (basso impatto, basso) — FFmpeg nel sidecar, tag ID3. *(Settimana 6)*
7. **Icona Megafono nella barra superiore / Tray** (basso impatto, bassissimo sforzo) — icona a megafono ad alta visibilità per menubar/tray e titlebar. *(Settimana 6)*
8. **"Leggi da qui" / Cursor-based reading** (alto impatto, medio sforzo) — riproduzione dal cursore attivo in poi senza selezione manuale estesa. *(Settimane 4–5)*
9. **Player minimale a barra singola con onde vocali** (alto impatto, medio sforzo) — floating player ultra-compatto con barra di durata, linee vocali animate e play/pausa. *(Settimana 6)*
10. **Filtro esclusione testo** (medio impatto, basso sforzo) — esclusione di stringhe configurate prima della sintesi vocale. *(Settimane 4–5)*


---

## Focus Feature Utente — UI, Controllo & Cattura 🎙️

Specifiche operative per le 4 feature utente approvate:

| Feature | Descrizione & Comportamento | Collocazione & Impatto |
|---|---|---|
| 📣 **Icona Megafono (Tray & Titlebar)** | Sostituzione delle icone menubar/tray e titlebar con una silhouette vettoriale a megafono, migliorando la riconoscibilità del lettore in background e nella barra superiore. | *Settimana 6 (UI Polish)* — Rapida implementazione asset SVG/multipiattaforma. |
| 📍 **"Leggi da qui" (Cursor-based reading)** | Consente all'utente di posizionare il cursore in un punto arbitrario del testo e avviare la lettura da lì fino alla fine del contesto/paragrafo, superando il vincolo della selezione manuale estesa. | *Settimane 4–5 (Cattura)* — Integrazione con provider AX/UIA per rilevare text offset o selezione automatica da cursore. |
| 🎚️ **Player Minimale a Barra Singola** | Modalità compatta ridisegnata: una barra sottile e discreta con barra di avanzamento temporale, piccole linee vocali animate (waveform indicator) reattive alla riproduzione e controlli play/pausa essenziali. Minimo ingombro visivo. | *Settimana 6 (Player UI)* — CSS/Canvas leggero, zero overhead CPU, transizione fluida tra player esteso e mini-bar. |
| 🚫 **Esclusione di Testo (Filtro Stringhe)** | Configurazione utente per escludere stringhe esatte, pattern ricorrenti o disclaimer (es. "Inviato da iPhone", header ripetitivi, note legali) prima del chunking e della sintesi TTS. | *Settimane 4–5 (Smart Pipeline)* — Pre-elaborazione nel normalizzatore Python/JS con matching rapido e lista personalizzabile. |
---

## Rischi & Mitigazioni

| Rischio | Probabilità | Impatto | Mitigazione |
|---|---|---|---|
| Reclutamento utenti test (settimana 0) fallisce | Medio | Alto (tutto il piano perde validazione) | Contattare associazioni/UICI/community fin da subito; piano B: test remoti via videochiamata |
| UIA instabile / sviluppato alla cieca | Medio | Alto (cattura rotta Win) | Macchina Windows fisica/VM obbligatoria; fallback clipboard robusto |
| DirectML lento/buggato | Medio | Medio (fallback CPU ok) | CI testa provider; default CPU se init fallisce |
| Sidecar size > 100MB (DirectML + modelli) | Alto | Medio (download utente) | Compressione UPX + `--strip` PyInstaller; split modelli opzionali |
| Normalizzatore: scope creep sulle regole | Alto | Medio (settimane 4–5 slittano) | Hard cap ~30 regole ad alta frequenza; tutto il resto in backlog v2 |
| Accessibilità regressa in refactor | Medio | Critico | Test automatizzati aXe-core in CI dal giorno 1 + test manuali settimanali |

---

## Confronto v1 → v2

| Problema v1 | Soluzione v2 |
|---|---|
| Fasi 1+2 in parallelo = irreale per 1 dev | Sequenziale con gate di uscita misurabili per fase |
| 3 piattaforme contemporaneo | 2 piattaforme eccellenti, Linux best-effort |
| Nessuna validazione utente | Settimana 0 + test a fine settimane 5 e 6 |
| Normalizzatore 5 lingue subito | Solo IT, regole per frequenza reale, hard cap 30 |
| Telemetria generica | Default OFF, granulare, coerente con privacy |
| Fase 4 vaga (hash fragile) | Rimandata a v2 con schema fuzzy definito |
| Nessuna metrica di successo | Gate quantificati per ogni fase |
