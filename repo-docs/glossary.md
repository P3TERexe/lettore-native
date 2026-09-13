# Glossary

Terminologia tecnica e concetti chiave utilizzati nel repository Lettore Native.

| Termine | Definizione | Stato |
| --- | --- | --- |
| **AXUIElement** | Elemento dell'Accessibility API di macOS utilizzato per interrogare la gerarchia dell'interfaccia, estrarre il testo selezionato o tracciare la posizione del cursore a schermo. | `Confirmed` |
| **SentenceChunker** | Modulo di segmentazione del testo che identifica i confini naturali delle frasi e delle pause respiratorie prima dell'invio al sintetizzatore vocale. | `Confirmed` |
| **TextNormalizer** | Pipeline di pre-elaborazione del testo per pulire caratteri speciali, abbreviazioni, citazioni e numeri prima della fonetizzazione. | `Confirmed` |
| **PlaybackCoordinator** | Servizio responsabile della gestione della coda di riproduzione, del pre-fetching asincrono dei chunk audio e del coordinamento temporale. | `Confirmed` |
| **Dynamic Island / Floating Pill** | Componente UI fluttuante ad aggancio elastico che visualizza lo stato di riproduzione e le onde sonore in tempo reale a basso impatto visivo. | `Confirmed` |
| **Supertonic** | Modello neurale di sintesi vocale TTS utilizzato per generare flussi audio naturali a bassa latenza. | `Confirmed` |
| **Read-From-Here** | Modalità di lettura continua che avvia la riproduzione dalla posizione corrente del cursore fino al termine del testo senza richiedere una selezione manuale preventiva. | `Planned` |
| **Smart Academic Skip** | Funzionalità mirata a DSA/neurodivergenza che filtra citazioni bibliografiche tra parentesi e rimandi di note a piè di pagina durante la lettura. | `Planned` |
