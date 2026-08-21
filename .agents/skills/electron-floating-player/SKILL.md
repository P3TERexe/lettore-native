---
name: electron-floating-player
description: >-
  Architettura e pattern per finestre Electron frameless always-on-top, sincronizzazione audio
  tramite Web Audio API, gestione sicura della coda di riproduzione ed eventi IPC.
---

# Electron Floating Player Skill

Questa skill racchiude le best practice architetturali per l'interfaccia Electron del progetto Lettore.

---

## 1. Finestra Flottante Frameless Always-on-Top

### Configurazione `BrowserWindow`
```javascript
const win = new BrowserWindow({
  width: 480,
  height: 260,
  frame: false,
  alwaysOnTop: true,
  transparent: false,
  resizable: true,
  webPreferences: {
    preload: path.join(__dirname, 'preload.js'),
    contextIsolation: true,
    nodeIntegration: false,
  },
});
```

### Regole per il Dragging
* Usare `-webkit-app-region: drag` sull'header / barra superiore.
* Disabilitare esplicitamente il drag su tutti gli elementi interattivi (pulsanti, slider, input, link) con `-webkit-app-region: no-drag`.

---

## 2. Web Audio API e Prevenzione Race Conditions

### Gestione Corretta dell'evento `onended`
* Quando si ferma la riproduzione manualmente tramite `source.stop()`, Web Audio scatena asincronamente `source.onended`.
* **Regola**: Rimuovere o azzerare l'handler `source.onended = null` prima di invocare `source.stop()` per evitare che scatti un avanzamento accidentale della coda.

```javascript
stopCurrentPlayback() {
  if (this.currentSource) {
    this.currentSource.onended = null;
    try {
      this.currentSource.stop();
    } catch (_) {}
    this.currentSource.disconnect();
    this.currentSource = null;
  }
}
```

### Locking dell'Avanzamento Coda
* Usare un flag di avanzamento (`_isAdvancing = true`) per impedire che richieste multiple in arrivo da timer di polling o selezioni rapide creino chiamate sovrapposte a `advance()`.
