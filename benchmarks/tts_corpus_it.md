# Corpus TTS italiano

28 testi per il benchmark di qualità e velocità. La versione machine-readable
usata dagli script è [`tts_corpus_it.jsonl`](tts_corpus_it.jsonl); questo file
è una vista leggibile generata dallo stesso corpus.

## Frasi brevi

- **`short-01`** — Ciao, come stai?
  _Saluto breve: attacco, intonazione ascendente e chiusura._
- **`short-02`** — Questa è una prova di sintesi vocale in italiano.
  _Frase dichiarativa lineare con accento finale._
- **`short-03`** — Attenzione: il documento è stato aggiornato.
  _Avviso con due punti e lessico tecnico._
- **`short-04`** — Possiamo iniziare la lettura quando vuoi.
  _Frase colloquiale con ritmo discendente._
- **`short-05`** — Il treno per Milano parte alle otto e quindici.
  _Orario espresso a parole, senza cifre._

## Frasi medie

- **`medium-01`** — La lettura ad alta voce migliora la comprensione e aiuta a mantenere l'attenzione sulle idee principali del testo.
  _Frase educativa con due proposizioni coordinate._
- **`medium-02`** — Il nuovo aggiornamento introduce una cache locale, un preload intelligente e una gestione più precisa della velocità di riproduzione.
  _Lessico tecnico e elenco di tre elementi._
- **`medium-03`** — Quando ascoltiamo una voce sintetica, il cervello cerca continuità nel ritmo, nelle pause e nell'intonazione delle frasi.
  _Subordinata iniziale e tre complementi coordinati._
- **`medium-04`** — Per configurare l'applicazione, apri il pannello delle impostazioni, seleziona la voce desiderata e regola la velocità con lo slider.
  _Istruzioni operative con tre verbi all'imperativo._
- **`medium-05`** — La ricerca scientifica mostra che alternare lettura e ascolto può ridurre l'affaticamento visivo durante lo studio prolungato.
  _Registro divulgativo con subordinata esplicita._
- **`medium-06`** — Il sistema operativo gestisce la memoria in modo dinamico, liberando le risorse che non sono più necessarie.
  _Spiegazione tecnica con gerundio finale._

## Paragrafi lunghi

- **`long-01`** — La lettura è un'attività complessa che coinvolge occhi, memoria e attenzione. Quando leggiamo un testo lungo, il cervello non elabora ogni parola in modo isolato: costruisce progressivamente il significato delle frasi, collega le informazioni nuove a quelle già conosciute e anticipa ciò che verrà dopo. L'ascolto può offrire un percorso alternativo, soprattutto per chi passa molte ore davanti a uno schermo. Una voce chiara, con pause ben calibrate, permette di seguire il filo del discorso senza interrompere il lavoro o affaticare la vista.
  _Paragrafo divulgativo di circa 90 parole, con due punti e frase lunga centrale._
- **`long-02`** — Per valutare la qualità di un motore di sintesi vocale non basta misurare la velocità. Bisogna ascoltare la pronuncia delle vocali, la naturalezza delle pause, la gestione delle parole straniere e la capacità di mantenere un ritmo costante anche nelle frasi più lunghe. Un sistema può essere rapidissimo eppure risultare faticoso da ascoltare se sbaglia gli accenti o se inserisce pause nel punto sbagliato. Per questo un buon benchmark combina misure oggettive, come la latenza e il consumo di memoria, con una valutazione umana attenta.
  _Paragrafo argomentativo con elenco e connettivi._
- **`long-03`** — Il progetto è stato aggiornato il 19 ottobre 2026. La nuova versione include tre modifiche principali: la cache audio su disco, il caricamento anticipato delle frasi successive e una soglia dinamica per il primo chunk. Durante i test, il tempo di generazione è sceso da circa 1,6 secondi a 0,85 secondi per una frase di otto secondi, con un consumo di memoria inferiore a 600 megabyte. I risultati migliori sono stati ottenuti con quattro thread di calcolo e il provider CPU.
  _Paragrafo con date, numeri decimali, unità di misura e sigla CPU._
- **`long-04`** — «Non è importante quanto velocemente corri», disse il maestro, «ma se riesci a fermarti prima di perdere il controllo». Il giovane annuì, respirò profondamente e riprese il percorso. Lungo la strada incontrò un cartello con su scritto: «Attenzione, strada stretta per due chilometri». Poco più avanti, una voce proveniente dalla radio annunciò che il treno delle 18:45 sarebbe partito dal binario 7 invece che dal binario 3. «Meglio controllare l'app», pensò, «prima di correre senza motivo».
  _Narrazione con dialogo, virgolette caporali e orari._

## Numeri, date e valute

- **`numbers-01`** — Il 25 aprile 2026, alle ore 14:30, il prezzo sarà di 1.234,56 euro, IVA inclusa al 22%.
  _Data, ora, migliaia, decimali e percentuale._
- **`numbers-02`** — Chiama il numero 02 1234 5678 oppure scrivi a info@example.com entro le 18:00.
  _Numero telefonico, indirizzo email e orario._
- **`numbers-03`** — La temperatura è scesa da 21,5 °C a meno 3,2 °C, mentre l'umidità è salita al 78%.
  _Decimali, simbolo dei gradi, valori negativi e percentuale._

## Abbreviazioni

- **`abbr-01`** — Il Dott. Rossi, della S.r.l. Bianchi & Figli, ha inviato il documento al prof. Verdi e alla dott.ssa Bianchi.
  _Titoli abbreviati, forma societaria e ampersand._
- **`abbr-02`** — Consultare l'art. 5, comma 2, e la pag. 12 del manuale, ecc. Per ulteriori informazioni, vedere l'Appendice A.
  _Abbreviazioni giuridiche, eccetera e riferimento a un'appendice._

## Punteggiatura

- **`punct-01`** — «Davvero?» chiese Anna. «Non ci credo... eppure i dati sono chiari: il 60% degli utenti preferisce l'ascolto.»
  _Domanda, punti di sospensione, due punti e percentuale._
- **`punct-02`** — Il percorso (breve, ma intenso) prevede tre tappe — nord, centro e sud — con una pausa; il ritorno è previsto per le 19:30.
  _Parentesi, lineette, punto e virgola e orario._

## Nomi e parole straniere

- **`multi-01`** — Ho installato macOS Sonoma, aggiornato SwiftUI e configurato CoreML insieme a ONNX Runtime sul mio MacBook Pro.
  _Nomi di prodotti e tecnologie in inglese dentro una frase italiana._
- **`multi-02`** — Il team di Zürich ha incontrato João e Müller a San Francisco per discutere del progetto «Lettore Native».
  _Nomi propri con dieresi, accenti e grafie straniere._

## Stress test

- **`stress-01`** — Ottimo lavoro! 🎉👏 Il risultato è al 100%: nessun errore, nessun ritardo, nessuna scusa.
  _Emoji e simboli non parlati: verifica la sanitizzazione senza crash._
- **`stress-02`** — Se anche tu, come me, hai passato l'intera giornata a leggere documenti, rispondere a email, partecipare a riunioni e cercare di ricordare dove hai lasciato le chiavi, allora sai bene quanto sia prezioso poter ascoltare un testo mentre fai altro.
  _Frase lunga con molte subordinate: stress su respiro e pianificazione._

## Dialoghi

- **`dialogue-01`** — «Pronto?» «Ciao, sono Luca. Sei libero per una chiamata?» «Certo, dimmi pure.» «Avresti cinque minuti per rivedere il capitolo tre?»
  _Botta e risposta rapido con domande e incisi._
- **`dialogue-02`** — «Dove andiamo stasera?» chiese Sofia. «Che ne dici di quel ristorante vicino al porto?» rispose Marco. «Mi hanno detto che il pesce è ottimo, ma è meglio prenotare.»
  _Dialogo narrativo con attribuzioni e intonazione interrogativa._
