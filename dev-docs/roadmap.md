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
- **Config unificata & Astrazione Motore TTS**: architettura pluggabile a provider/driver (`BaseTTSEngine`). L'app non si accoppia rigidamente a una singola libreria/runtime: runtime attuale isolato come provider (Supertonic/ONNX), pronto per swap futuro a nuove librerie/modelli TTS senza riscrivere API o frontend.
- **Rilevamento acceleratori**: `BackendConfig` rileva provider disponibili (`CoreMLExecutionProvider`, `DmlExecutionProvider`, `CPUExecutionProvider`) → auto-seleziona il migliore, fallback silenzioso a CPU.
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
├── engines/                 // NUOVO: Astrazione modulare TTS
│   ├── base.py              // Interfaccia BaseTTSEngine (load, synthesize, stream, unload)
│   ├── onnx_engine.py       // Implementazione attuale Supertonic ONNX
│   └── factory.py           // Selezione dinamica del motore da config
├── textnorm/                // NUOVO modulo Python
│   ├── rules_it.yaml
│   └── normalizer.py
└── tts_manager.py           // Orchestra il motore tramite BaseTTSEngine + normalizzatore

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
2. **Media keys + scorciatoie globali personalizzabili** — configurazione tasti da UI (Play, Pausa, Stop) con raccomandati per Mac (`Fn + F` Play, `Fn + J` Pausa, `Fn + JJ` Stop/doppio tap); supporto media keys hardware (Next salta frase, Previous ripeti frase).
3. **Esportazione MP3 + metadati** — FFmpeg nel sidecar, tag ID3, `Content-Disposition: attachment`.
4. **Megafono Widget Funzionante (Tray & Titlebar)** — non una semplice icona passiva, ma un widget interattivo presente sia nella tray/menubar di sistema che nella titlebar dell'app. Al click apre un menu popover con Play/Pausa e avvia all'occorrenza la modalità minimale (floating pill); alla fine della riproduzione o all'interruzione manuale, la pillola sfuma verso la trasparenza.
5. **Player minimale a barra singola (Floating Pill)** — modalità ultra-compatta con sola barra di avanzamento, onde vocali animate (waveform lines), controlli play/pausa ed effetto dissolvenza/trasparenza al termine della riproduzione.
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
5. **Studio di Fattibilità: Auto-identificazione del testo principale & Cattura Assistita (Visual Block Reading)** 🔬 — tutto da pianificare/valutare tecnicamente:
   - *Modalità Automatica*: se è attiva un'app di lettura o browser in primo piano, il motore rileva ed estrae in autonomia il corpo del testo principale (main article/content extraction via accessibility tree AX/UIA, heuristics DOM o Readability locale) saltando barre laterali, pubblicità e menu.
   - *Modalità Assistita (Overlay a riquadri)*: overlay trasparente a schermo intero che traccia bounding box rettangolari attorno ai singoli blocchi/paragrafi di testo rilevati; l'utente clicca su un riquadro per avviare subito la lettura o metterlo in coda.
6. **"Modalità Studio Lingue"** (Listen-Repeat-Score) — la più rischiosa, per ultima: TTS → utente ripete al microfono → ASR locale (whisper.cpp tiny) → feedback pronuncia + score, loop automatico (~150MB sidecar).

---

## Miglioramenti UX prioritari (impact/effort)

1. **First-run wizard** (alto impatto, medio sforzo) — onboarding 3 step: permessi, test voce, hotkey reminder. *(Settimane 1–3)*
2. **Anteprima voce istantanea** (alto impatto, basso sforzo) — pulsante ▶️ accanto a ogni voce. *(Settimana 6)*
3. **Gestione coda visibile e manipolabile** (alto impatto, medio) — drag-handle riordino, rimozione singola, svuota tutto; endpoint `DELETE /v1/queue/{id}`, `PATCH /v1/queue/reorder`. *(Settimane 1–3)*
4. **Feedback backend visibile** (medio impatto, basso) — toast/banner: "Avvio motore TTS…" → "Download modello (400 MB)… 23%" → "Pronto". *(Settimane 1–3)*
5. **Scorciatoie globali personalizzabili & Media keys** (medio impatto, medio sforzo) — pannello impostazioni per rimappare Play, Pausa e Stop (default raccomandati Mac: `Fn + F` Play, `Fn + J` Pausa, `Fn + JJ` Stop). *(Settimana 6)*
6. **Esportazione MP3/OGG + metadati** (basso impatto, basso) — FFmpeg nel sidecar, tag ID3. *(Settimana 6)*
7. **Megafono Widget Funzionante (Tray & Titlebar)** (alto impatto, medio sforzo) — widget interattivo con menu comandi rapidi (Play/Pausa), trigger della floating pill e transizione di dissolvenza/trasparenza al completamento della lettura. *(Settimana 6)*
8. **"Leggi da qui" / Cursor-based reading** (alto impatto, medio sforzo) — riproduzione dal cursore attivo in poi senza selezione manuale estesa. *(Settimane 4–5)*
9. **Player minimale a barra singola con onde vocali (Floating Pill)** (alto impatto, medio sforzo) — floating pill/player ultra-compatto con barra di durata, linee vocali animate, play/pausa e fade-out trasparente al termine. *(Settimana 6)*
10. **Filtro esclusione testo** (medio impatto, basso sforzo) — esclusione di stringhe configurate prima della sintesi vocale. *(Settimane 4–5)*
11. **Pannello rimappatura scorciatoie da tastiera** (medio impatto, basso-medio sforzo) — interfaccia utente per configurare hotkey globali/locali con rilevamento conflitti e profili raccomandati per OS. *(Settimana 6)*


---

## Focus Feature Utente — UI, Controllo & Cattura 🎙️

Specifiche operative per le feature utente approvate:

| Feature | Descrizione & Comportamento | Collocazione & Impatto |
|---|---|---|
| 📣 **Megafono Widget Funzionante (Tray & Titlebar)** | Widget interattivo presente nella system tray/menubar e nella barra superiore dell'app (titlebar). Al click apre un menu/popover rapido con controlli Play/Pausa e richiama/attiva la visualizzazione minimale (floating pill della sintesi vocale) se non già visibile. Quando la lettura termina (fine testo o stop manuale), la pillola attiva una transizione animata verso la trasparenza (dissolvenza continua/fade-out). | *Settimana 6 (UI Polish & Widget Interattivo)* — Gestione eventi Tray/Menu Tauri + integrazione IPC con la floating pill e gestione transizioni di opacità/trasparenza CSS/Tauri. |
| 📍 **"Leggi da qui" (Cursor-based reading)** | Consente all'utente di posizionare il cursore in un punto arbitrario del testo e avviare la lettura da lì fino alla fine del contesto/paragrafo, superando il vincolo della selezione manuale estesa. | *Settimane 4–5 (Cattura)* — Integrazione con provider AX/UIA per rilevare text offset o selezione automatica da cursore. |
| 🎚️ **Player Minimale a Barra Singola (Floating Pill)** | Modalità compatta ridisegnata: una barra sottile e discreta (pillola fluttuante) con barra di avanzamento temporale, piccole linee vocali animate (waveform indicator) reattive alla riproduzione, controlli play/pausa essenziali e dissolvenza trasparente al termine. Minimo ingombro visivo. | *Settimana 6 (Player UI)* — CSS/Canvas leggero, zero overhead CPU, transizione fluida tra player esteso e mini-bar/pillola con gestione fadeout trasparente. |
| 🚫 **Esclusione di Testo (Filtro Stringhe)** | Configurazione utente per escludere stringhe esatte, pattern ricorrenti o disclaimer (es. "Inviato da iPhone", header ripetitivi, note legali) prima del chunking e della sintesi TTS. | *Settimane 4–5 (Smart Pipeline)* — Pre-elaborazione nel normalizzatore Python/JS con matching rapido e lista personalizzabile. |
| ⌨️ **Scorciatoie Personalizzabili (Play / Pausa / Stop)** | Impostazione dedicata nelle preferenze che consente all'utente di registrare e rimappare le scorciatoie da tastiera globali per Play, Pausa e Stop. Include set raccomandato per macOS: **Play: `Fn + F`**, **Pausa: `Fn + J`**, **Stop: `Fn + JJ`** (doppio tap rapido o combinazione dedicata). | *Settimana 6 (Controllo & Accessibilità)* — Plugin shortcut globali Tauri / handler eventi nativo con persistenza in config e prevenzione conflitti OS. |
| 🔍 **Auto-identificazione Testo & Cattura Assistita a Riquadri (R&D / Fattibilità)** | **(Da pianificare & validare)** Due modalità di cattura intelligente senza selezione manuale: <br>1. *Automatica*: rilevamento automatico del blocco di testo principale dell'app/browser in primo piano (tramite traversing dell'albero AX/UIA o Readability engine locale). <br>2. *Assistita*: overlay su schermo con box visivi attorno alle sezioni di testo rilevate; con un click l'utente sceglie se avviare la riproduzione immediata del blocco o aggiungerlo alla coda di lettura. | *TRACK 2 — Visione v2 (R&D / Prototipazione)* — Studio fattibilità tecnica: performance traversing AX/UIA su alberi complessi di browser, precisione coordinate bounding box per overlay trasparente in Tauri. |
| 🧩 **Modularità Motore Vocale (Plug-and-Play TTS)** | Disaccoppiamento del runtime TTS tramite interfaccia/adattatore unificato (`BaseTTSEngine`). Permette di sostituire o affiancare l'engine attuale con librerie o modelli emergenti più performanti/naturali senza impattare frontend, API FastAPI o IPC Tauri. | *Settimane 1–3 (Architettura Core)* — Refactor modulare backend Python (`engines/base.py`, driver factory e compatibilità streaming). |
---

## Rischi & Mitigazioni

| Rischio | Probabilità | Impatto | Mitigazione |
|---|---|---|---|
| Reclutamento utenti test (settimana 0) fallisce | Medio | Alto (tutto il piano perde validazione) | Contattare associazioni/UICI/community fin da subito; piano B: test remoti via videochiamata |
| UIA instabile / sviluppato alla cieca | Medio | Alto (cattura rotta Win) | Macchina Windows fisica/VM obbligatoria; fallback clipboard robusto |
| DirectML lento/buggato | Medio | Medio (fallback CPU ok) | CI testa provider; default CPU se init fallisce |
| Sidecar size > 100MB (DirectML + modelli) | Alto | Medio (download utente) | Compressione UPX + `--strip` PyInstaller; split modelli opzionali |
| Normalizzatore: scope creep sulle regole | Alto | Medio (settimane 4–5 slittano) | Hard cap ~30 regole ad alta frequenza; tutto il resto in backlog v2 |
| Fattibilità auto-identificazione testo & overlay a riquadri | Alto | Basso (R&D Track 2, non impatta MVP) | Prototipazione preliminare separata; timebox R&D su AX/UIA tree vs browser DOM |
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
