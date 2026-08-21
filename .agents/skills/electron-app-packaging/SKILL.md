---
name: electron-app-packaging
description: >-
  Workflow e configurazioni per il packaging multipiattaforma di applicazioni Electron
  con backend Python / ONNX integrato (.dmg, .exe, .AppImage).
---

# Electron App Packaging Skill

Questa skill definisce la procedura per distribuire l'applicazione Lettore come eseguibile nativo completo per macOS, Windows e Linux.

---

## 1. Architettura di Distribuzione

L'applicazione è composta da due runtime:
1. **Frontend**: Electron (Node.js/Chromium).
2. **Backend**: Python 3 con FastAPI, Uvicorn, ONNX Runtime e Supertonic.

---

## 2. Bundling del Backend Python (PyInstaller)

Per evitare che l'utente finale debba installare Python o dipendenze via pip:

```bash
# Esempio di build backend standalone
pyinstaller --name lettore-backend \
  --onedir \
  --collect-all supertonic \
  --collect-all onnxruntime \
  --add-data "backend:backend" \
  backend/main.py
```

L'eseguibile risultante viene posizionato nella cartella delle risorse di Electron (`extraResources` in `electron-builder.json`).

---

## 3. Configurazione `electron-builder`

Nel file `package.json` o `electron-builder.yml`:

```json
{
  "build": {
    "appId": "com.lettore.app",
    "productName": "Lettore",
    "mac": {
      "category": "public.app-category.utilities",
      "hardenedRuntime": true,
      "entitlements": "build/entitlements.mac.plist",
      "entitlementsInherit": "build/entitlements.mac.plist",
      "target": ["dmg", "zip"]
    },
    "extraResources": [
      {
        "from": "dist/lettore-backend",
        "to": "backend",
        "filter": ["**/*"]
      }
    ]
  }
}
```

---

## 4. Permessi macOS (Entitlements)

Per consentire l'accesso all'Accessibilità e alla Clipboard senza blocchi:
* `com.apple.security.automation.apple-events`: per Apple Events.
* Permesso Accessibilità concesso dall'utente finale all'app firmata.
