# Lettore Native 🎙️🍏

> **Lettore Native** è un'applicazione macOS nativa progettata per l'accessibilità e l'inclusione. Legge ad alta voce i tuoi testi selezionati ovunque nel sistema usando il motore vocale neurale Supertonic 3 (basato su ONNX Runtime).

![macOS Support](https://img.shields.io/badge/macOS-14.0%2B-silver?style=flat-square&logo=apple)
![Swift Version](https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/license-CC_BY--NC--SA_4.0-blue?style=flat-square)

### 📥 [Scarica l'Ultima Versione (v3.0.0)](https://github.com/P3TERexe/lettore-native/releases/latest)

## 🚀 Funzionalità Chiave

*   **100% Nativa SwiftUI/AppKit**: Leggerissima sulla memoria (<80 MB) con tempi di avvio istantanei. Zero Electron, zero WebKit.
*   **Accessibilità Integrata (AX)**: Si aggancia nativamente a macOS tramite le Accessibility API per leggere il testo selezionato in qualsiasi applicazione attiva (Browser, PDF Reader, Word).
*   **Motore Audio Gapless**: Architettura `AVAudioPlayer` ad altissime prestazioni per una riproduzione senza interruzioni e un *waveform tap* real-time fluido e leggero.
*   **Normalizzazione Intelligente**: Espande automaticamente abbreviazioni italiane ("Dott.", "Sig.ra"), date, valute e URL *prima* della sintesi vocale.
*   **Interfaccia Minimalista e Accessibile**: Include un *Floating Pill* stile Dynamic Island, widget per la Menubar, e un profilo WCAG AAA per la lettura immersiva (High Contrast, font OpenDyslexic).

## 🏗️ Architettura Ibrida (Fase 3.0)

Attualmente il progetto si trova nella **Fase 3.0** (Transizione al Nativo). 
L'interfaccia utente, la gestione audio, la cattura del testo e la logica di normalizzazione sono **100% in Swift**.
Il motore neurale di sintesi vocale (Supertonic) risiede ancora in un backend locale in Python (`backend/`) gestito come sidecar.

*Roadmap futura (M4):* Integrazione del modello ONNX direttamente in Swift tramite C-API per eliminare definitivamente il processo Python.

## 🛠️ Requisiti di Sistema

*   **OS**: macOS 14.0 (Sonoma) o superiore.
*   **Sviluppo**: Xcode 16.0+ o Swift 6.0 Toolchain.
*   **Python**: Python 3.10+ (necessario solo per eseguire il backend TTS in modalità sviluppo).

## 💻 Compilazione ed Esecuzione (Sviluppo)

Per sviluppare Lettore Native, devi avviare sia il backend Python che l'applicazione Swift.

### 1. Avvia il Motore Vocale (Backend Python)
```bash
# Entra nella cartella backend e crea un virtual environment
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Avvia il server locale su 127.0.0.1:7788
python main.py
```

### 2. Avvia l'Applicazione macOS (Swift)
Apri una nuova finestra del terminale:
```bash
# Dalla root della repository
swift run LettoreApp
```
In alternativa, puoi aprire il file `Package.swift` direttamente con **Xcode** e premere `Cmd+R`.

## ⚙️ Configurazione Accessibilità (AX)

Affinché l'app possa leggere il testo che evidenzi (premendo Play sulla Pillola o usando le scorciatoie da tastiera), deve poter "vedere" le altre app aperte sul Mac. 

Al primo avvio, l'applicazione ti chiederà automaticamente i permessi. Per autorizzarla:
1. Apri le **Impostazioni di Sistema** del Mac.
2. Vai su **Privacy e Sicurezza** -> **Accessibilità**.
3. Cerca `Lettore Native` nell'elenco.
4. **Attiva l'interruttore** (se non c'è, puoi aggiungerlo trascinando l'app dentro la finestra o cliccando sul tasto `+`).
5. Chiudi e riapri l'app. Da ora in poi il lettore funzionerà su qualsiasi applicazione!

## 🚨 Risoluzione Problemi: "Apple non è in grado di verificare l'app" (Gatekeeper)

Poiché l'app scaricata da GitHub (o compilata manualmente) non è autenticata con un certificato Apple Developer a pagamento, macOS per sicurezza la bloccherà mostrando il messaggio: *"Apple non è in grado di verificare che LettoreNative non contenga malware"*.

Per aprirla, puoi usare uno dei due metodi seguenti:

### Metodo 1: Click Destro (Consigliato)
1. Tieni premuto **Control (`^`)** e fai **Click** sull'app `LettoreNative.app` (oppure fai **Click destro**).
2. Scegli **Apri** dal menu a tendina.
3. macOS ti mostrerà lo stesso avviso, ma questa volta ci sarà un pulsante **"Apri"**. Cliccalo per autorizzare l'app per sempre.

### Metodo 2: Terminale (Se il Metodo 1 non funziona)
Se il Mac è impostato in modo molto restrittivo e nasconde il pulsante Apri, rimuovi la "quarantena" di macOS aprendo il Terminale e scrivendo:
```bash
xattr -cr /Percorso/Dove/Hai/Salvato/LettoreNative.app
```
### Metodo 3: Impostazioni di Sistema (Infallibile su macOS Sonoma)
Se il Click Destro non mostra il pulsante "Apri" e il Terminale non funziona (succede spesso nelle nuove versioni di macOS a causa di un tag invisibile chiamato *Provenance*):
1. Apri le **Impostazioni di Sistema** (System Settings) del tuo Mac.
2. Vai su **Privacy e Sicurezza** (Privacy & Security).
3. Scorri verso il basso fino alla sezione **Sicurezza**.
4. Vedrai un avviso che dice che `LettoreNative.app` è stata bloccata perché proviene da uno sviluppatore non identificato. Accanto troverai il pulsante **"Apri Comunque"** (Open Anyway).
5. Cliccalo, inserisci la password del Mac (o TouchID) e l'app si aprirà.

## 📦 Struttura del Progetto

*   `Package.swift`: Configurazione del Swift Package Manager.
*   `Sources/LettoreApp/`: Entry point dell'applicazione SwiftUI e ciclo di vita.
*   `Sources/LettoreUI/`: Componenti dell'interfaccia utente (Pillola, HUD, Viste accessibili).
*   `Sources/LettoreEngine/`: Pipeline audio, Playback Coordinator e chiamate TTS.
*   `Sources/LettoreCore/`: Modelli di stato, Sentence Chunker, e Text Normalizer.
*   `Sources/LettoreSystem/`: Integrazione con macOS Accessibility (AX) e Vision OCR.
*   `Tests/`: Unit test in XCTest per la logica di dominio.
*   `backend/`: Il motore TTS neurale in Python (sidecar).
*   `backend_tests/`: I test originali per la parte Python.

## 🤝 Contribuire

Le Pull Request sono benvenute! Assicurati di eseguire `swift test` prima di proporre modifiche alla logica core, e di testare a fondo il comportamento dell'audio su diverse frequenze di campionamento.

## 📄 Licenza

Questo progetto è distribuito con licenza **Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)**. 
Questo significa che sei libero di utilizzare e modificare il codice, ma:
1. **Non puoi utilizzarlo per scopi commerciali**.
2. **Devi mantenere il progetto open source** (le tue modifiche devono essere distribuite sotto la stessa licenza).

Vedi il file `LICENSE.md` per ulteriori dettagli.
