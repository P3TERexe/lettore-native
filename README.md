# Lettore Native — Finestra Flottante TTS Supertonic (Tauri 2 + Rust)

Lettore è un'applicazione desktop nativa e ultraleggera (costruita con **Tauri 2** e **Rust**) per la sintesi vocale locale ad alta fedeltà con **Supertonic 3** (ONNX Runtime, 31 lingue, 100% on-device).

Seleziona un testo in qualsiasi applicazione e ascoltalo istantaneamente con controlli player flottanti, evidenziazione parola-per-parola, supporto multi-voce e lettura continua.

---

## 🚀 Architettura Nativa

```
┌─────────────────────────────────────────────────────────────┐
│ Tauri 2 (Rust Host Core)                                    │
│  ├── Window Manager (Frameless, Always-On-Top, Resizable)   │
│  ├── System Tray & Context Menus                            │
│  ├── Global Hotkeys (Cmd+Shift+S / Cmd+Shift+L)             │
│  ├── Native Accessibility Plugin (macOS AX, Windows UIA)    │
│  └── Sidecar Process Manager (FastAPI + Supertonic 3)       │
└──────────────────────┬──────────────────────────────────────┘
                       │ Local Webview (WebKit / WebView2)
┌──────────────────────▼──────────────────────────────────────┐
│ Frontend UI (HTML5 / Vanilla CSS / ES Modules)              │
│  ├── Dynamic Floating Player (Play, Pause, Stop, Speed)     │
│  ├── Multi-paragraph Queue Management                      │
│  ├── Word-by-word Reading Synchronizer                      │
│  └── Accessible Themes (Dark, Light, Contrast, Dyslexia)    │
└─────────────────────────────────────────────────────────────┘
```

### Vantaggi rispetto alla versione Electron:
* ⚡ **Footprint RAM**: ~50–70 MB (vs ~300 MB)
* 📦 **Dimensione pacchetto**: ~15–25 MB (vs ~200 MB)
* ⏱️ **Tempo di avvio**: < 200 ms (istantaneo)
* 🔒 **Sicurezza**: Architettura a permessi granulari (Tauri Capabilities)

---

## 🛠️ Prerequisiti

* **Rust**: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
* **Node.js**: ≥ 20 (LTS)
* **Python**: ≥ 3.10 (consigliato 3.11)

---

## 📦 Setup e Sviluppo Locale

1. **Installazione dipendenze**:
   ```bash
   # Configura ambiente Python
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -r backend/requirements.txt
   pip install -r backend/requirements-macos.txt # o windows/linux

   # Configura frontend
   cd ui && npm install && cd ..
   ```

2. **Avvio in modalità sviluppo**:
   ```bash
   cd src-tauri && cargo tauri dev
   ```

3. **Compilazione pacchetto di produzione**:
   ```bash
   bash scripts/build.sh
   ```

---

## ⌨️ Controlli e Hotkey

| Azione | Tasto / Controllo | Note |
|---|---|---|
| **Cattura e Leggi selezione** | `Cmd+Shift+S` (o `Cmd+Shift+L`) | Legge clipboard o cattura via Accessibility API |
| **Play / Pausa** | `Spazio` (nella finestra) / Tray | Controllo player immediato |
| **Stop** | `Esc` / Tray | Ferma la riproduzione e resetta |
| **Cambio Modalità Finestra** | Tasto vista laterale | Compatta (Player), Standard, Estesa (Coda + Impostazioni) |
| **Esporta Audio** | Bottone "WAV" | Salva l'audio sintetizzato tramite dialog nativo |

---

## 📄 Licenza

Proprietario / Private Repository.
