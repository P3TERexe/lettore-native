# Documentazione di Sviluppo Attiva (`dev-docs/`)

Questa cartella raccoglie **esclusivamente i documenti viventi** che accompagnano e tracciano l'avanzamento continuo del progetto:

| File | Scopo Primario | Quando va Aggiornato |
|---|---|---|
| **[`FEATURES.md`](./FEATURES.md)** | Registro di **tutte e sole le feature realmente implementate** nel codice e capacità native del motore TTS in uso. | Ad ogni nuova feature implementata, modifica al backend o al player. |
| **[`roadmap.md`](./roadmap.md)** | Piano di sviluppo per sprint/settimane (Track 1 MVP e Track 2 Post-Release), priorità UX e gate. | Ad ogni ripianificazione, aggiunta requisiti o superamento di un gate di fase. |
| **[`bug.md`](./bug.md)** | Registro operativo dei bug aperti, regressioni, passi di riproduzione e note diagnostiche. | All'apertura, isolamento diagnostico o risoluzione di un bug. |
| **[`decisions.md`](./decisions.md)** | Registro delle Decisioni Architetturali (ADR) vincolanti e salvaguardie tecniche intoccabili. | Quando si adotta una scelta architetturale o un vincolo che non deve essere rimosso. |
| **[`testing-checklist.md`](./testing-checklist.md)** | Protocollo di smoke testing manuale rapido (~5 min) per verificare hardware e OS reale. | Quando si aggiungono flussi utente critici o scenari di test prima delle release. |

---

## 📋 Regole di Manutenzione & Formattazione Obbligatorie

1. **Aggiornamento Continuo**: Nessuna modifica architetturale o di funzionalità deve essere conclusa senza aver aggiornato il rispettivo file in `dev-docs/`.
2. **Formattazione Rigorosa per File**:
   - **`FEATURES.md`**: Solo item completati con checkbox `[x]` e rinvio esatto ai percorsi del codice reale. Nessuna promessa o mock.
   - **`bug.md`**: Titolo numerato, *Description*, *Steps to Reproduce*, *Expected Behavior*, *Actual Behavior* e *Diagnosi tecnica*.
   - **`decisions.md`**: ID incrementale `[ADR-XXX]`, *Stato*, *Contesto & Problema*, *Decisione Presa*, *Alternative Scartate*, *Conseguenze & Vincoli Intoccabili*.
   - **`testing-checklist.md`**: ID scenario `[TC-XXX]`, *Prerequisiti*, *Passaggi*, *Esito Atteso*, *Esito Fallito (Segnale di Allarme)*.
   - **`roadmap.md`**: Divisione rigorosa in Track 1 (Settimane 0–7) e Track 2, con Gate di uscita quantificati.
