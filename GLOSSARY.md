# Lettore

Applicazione macOS di lettura vocale assistita per testi catturati da altre applicazioni, pensata per utenti con dislessia, ADHD, ipovisione o altre condizioni che rendono faticosa la lettura visiva continua.

## Language

**Chunk**:
Unità minima di testo inviata al motore vocale e riprodotta come segmento audio continuo.
_Avoid_: blocco, frammento, pezzo

**Lettura continua (Read-From-Here)**:
Modalità DSA-11 in cui la selezione o il cursore è solo il punto di partenza: la sintesi prosegue nel documento, con paging automatico per i documenti virtualizzati.
_Avoid_: leggi da qui (nome della feature), lettura dal cursore (descrizione parziale), read-from-here (nome storico)

**Ancora**:
Offset UTF-16, all'interno del testo catturato, in cui è mappata la selezione o il cursore di partenza.
_Avoid_: punto di partenza (ambiguo), cursore iniziale

**Range sorgente**:
Intervallo UTF-16 assoluto di una frase nel testo originale dell'app di origine, trasportato da `ReadingChunk.sourceRange`. Resta assente quando la sorgente non è mappabile: non si inventa una posizione.
_Avoid_: offset del chunk (ambiguo), posizione nel documento

**Sessione di evidenziazione**:
Sessione aperta alla cattura che lega un `documentID`, il PID dell'app di origine e l'ultimo range selezionato; viene chiusa senza deselezionare il testo.
_Avoid_: highlight globale, selezione persistente

**Selezione AX nativa**:
Scrittura di `AXSelectedTextRange` o `AXSelectedTextMarkerRange` per evidenziare la frase corrente nell'app di origine, senza modificare il testo, inviare eventi di tastiera o rubare il focus.
_Avoid_: overlay, highlight custom, karaoke

**Paging automatico**:
Caricamento della viewport successiva di un documento virtualizzato, con deduplica del testo già catturato.
_Avoid_: scroll infinito, autoscroll

**Stato di fine scroll**:
Classificazione a tre valori della scroll bar (`atEnd`, `notAtEnd`, `unknown`); `unknown` non significa fine documento e impone un tentativo di scroll.
_Avoid_: isScrollAtEnd, fine scroll presunta

**Text marker**:
Riferimento opaco a una posizione o a un intervallo di un documento web (Safari/AXWebArea), usato per leggere il documento completo senza materializzare ogni nodo.
_Avoid_: marker, offset Safari

**Cattura targetizzata**:
Cattura avviata su un PID esplicito invece che sull'app in primo piano; serve al pulsante "Leggi da qui" dello Studio.
_Avoid_: cattura esterna, cattura forzata

**Filtro rumore leggero**:
Pulizia conservativa delle catture documentali che rimuove numeri di pagina, intestazioni/piè di pagina ripetuti e trattini di fine riga, senza toccare note e citazioni.
_Avoid_: pulizia testo, filtro PDF

**Smart Academic Skip**:
Filtro che rimuove citazioni bibliografiche e rimandi a note durante la lettura, per ridurre il carico sulla memoria di lavoro.
_Avoid_: skip accademico, filtro citazioni

**Pillola fluttuante**:
Finestra sempre visibile e trascinabile che mostra lo stato di riproduzione e i controlli essenziali sopra qualsiasi applicazione.
_Avoid_: Dynamic Island, isola dinamica, notch

**Studio**:
Finestra principale dell'applicazione, dove si consultano testo catturato, coda e impostazioni di lettura.
_Avoid_: editor, dashboard, pannello

**Motore vocale**:
Sorgente della sintesi vocale. Il motore preferito è il modello neurale locale; in sua assenza l'app ricade sulla voce di sistema.
_Avoid_: TTS, sintetizzatore, engine

**Voce di sistema**:
Voce fornita da macOS, usata come ripiego quando il motore vocale preferito non è disponibile.
_Avoid_: fallback, voce di riserva

**Qualità di sintesi adattiva**:
Default degli step del motore vocale derivato dalla memoria fisica: 12 (Hi-Fi) con almeno 16 GiB, altrimenti 8 (bilanciato).
_Avoid_: preset qualità, qualità automatica

**Boost del primo chunk**:
Riduzione a 5 step della sola sintesi del primo chunk, applicata solo con qualità bilanciata (8); con Turbo (5) e Hi-Fi (12) il primo chunk usa già gli step scelti e il boost non ha effetto.
_Avoid_: first-chunk boost, accelerazione iniziale

**Profilo di accessibilità**:
Insieme di impostazioni di lettura e resa visiva calibrate su una specifica condizione dell'utente (DSA, ADHD, ipovisione).
_Avoid_: modalità, tema, preset

**Blocco semantico**:
Porzione di testo catturato classificata per ruolo strutturale (titolo, paragrafo, voce di elenco, citazione, codice) e navigabile come unità.
_Avoid_: sezione, paragrafo (quando si intende il blocco classificato)

**Cattura**:
Acquisizione del testo dall'applicazione in primo piano, con ripiego progressivo su selezione e riconoscimento ottico quando l'accessibilità non basta.
_Avoid_: estrazione, scraping, grab
