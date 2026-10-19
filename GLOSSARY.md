# Lettore

Applicazione macOS di lettura vocale assistita per testi catturati da altre applicazioni, pensata per utenti con dislessia, ADHD, ipovisione o altre condizioni che rendono faticosa la lettura visiva continua.

## Language

**Chunk**:
Unità minima di testo inviata al motore vocale e riprodotta come segmento audio continuo.
_Avoid_: blocco, frammento, pezzo

**Read-From-Here**:
Modalità di lettura che parte dalla posizione corrente del cursore e prosegue fino alla fine del testo, senza richiedere una selezione manuale.
_Avoid_: leggi da qui, lettura dal cursore

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

**Profilo di accessibilità**:
Insieme di impostazioni di lettura e resa visiva calibrate su una specifica condizione dell'utente (DSA, ADHD, ipovisione).
_Avoid_: modalità, tema, preset

**Blocco semantico**:
Porzione di testo catturato classificata per ruolo strutturale (titolo, paragrafo, voce di elenco, citazione, codice) e navigabile come unità.
_Avoid_: sezione, paragrafo (quando si intende il blocco classificato)

**Cattura**:
Acquisizione del testo dall'applicazione in primo piano, con ripiego progressivo su selezione e riconoscimento ottico quando l'accessibilità non basta.
_Avoid_: estrazione, scraping, grab
