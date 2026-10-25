# Evidenziazione della frase nell'app di origine (DSA-10 fase 1)

- **Stato**: Accettata; primitive AX validate dalla sonda 01, matrice GUI end-to-end ancora da eseguire
- **Data**: 2026-10-22
- **Riferimenti**: [DSA-10 nella roadmap](../../ROADMAP.md), [ADR-010](010-lettura-continua.md), branch `feature/dsa-10-frase`, commit `437c3d5`

## Contesto & Problema

La doppia codifica aiuta chi legge con difficoltà visive o attentive: vedere la
frase mentre la si ascolta ancora i fonemi ai grafemi e riduce il vagare dello
sguardo. Una finestra separata non basta, perché l'utente deve continuare a
leggere nel punto in cui si trova, dentro l'applicazione di origine.

La fase 1 di DSA-10 risponde a un requisito volutamente più stretto del
"karaoke": evidenziare **la frase corrente**, intera, nell'app di origine,
mentre la sintesi avanza. Non serve conoscere il timing delle singole parole,
non si proietta alcun overlay e non si modifica il documento.

I vincoli sono quelli già consolidati dalla lettura continua (ADR-010):

- non rubare il focus all'app di origine;
- non modificare il testo, non alterare gli appunti e non ripristinare
  automaticamente la selezione iniziale;
- non inviare eventi di tastiera per evidenziare;
- continuare l'audio quando l'evidenziazione non è possibile;
- non inventare posizioni quando la sorgente non è mappabile.

## Decisione

### 1. Selezione AX nativa, a granularità di frase

Alla cattura, `AXCaptureService` apre una **sessione di evidenziazione** con:

- un `documentID` UUID;
- il PID dell'app di origine;
- l'elemento AX che possiede la selezione o la web area che possiede i marker;
- la modalità di scrittura (`AXSelectedTextRange` o `AXSelectedTextMarkerRange`);
- il range UTF-16 assoluto del testo catturato.

`ReadingChunk` trasporta `sourceDocumentID` e `sourceRange`. I chunk manuali
restano senza entrambi; un chunk senza range non produce scritture anche quando
conserva l'identità del documento.

`PlaybackCoordinator` segnala il chunk corrente con `onCurrentChunkChanged` su
play, skip, jump e ripresa da pausa, **non** a ogni aggiornamento di progresso
audio. `SourceHighlightCoordinator` serializza `begin`/`update`, conserva
l'ultimo range in attesa e chiama
`SourceSelectionController.update(range:documentID:)`; il controller, se la
sorgente è frontmost, chiama
`AXCaptureService.highlightSourceRange(_:documentID:)`.

La scrittura usa solo le API Accessibility e verifica il readback:

- TextEdit e VS Code: `AXSelectedTextRange` con un `AXValue` `CFRange`;
- Safari: `AXSelectedTextMarkerRange`, con marker start/end creati da indice.

Non si scrive l'attributo `AXValue` (il testo del documento), non si inviano
`CGEvent` di tastiera e non si forza il focus. Se l'attributo non è scrivibile, la
sessione restituisce `.unsupported`; se la scrittura o il readback falliscono,
`.failed`.

### 2. Range UTF-16 e mapping attraverso filtro e normalizzazione

Gli offset sono in **unità UTF-16**, le stesse usate da `NSRange`, `AXValue` e
dai marker di Safari. Contare `Character` perderebbe posizioni su emoji e
caratteri fuori dal BMP.

Il percorso è:

1. `DocumentNoiseFilter.filterWithMapping` produce un `FilteredText`: testo
   filtrato più una sequenza di segmenti ordinati che mappano ogni intervallo
   di output sul corrispondente intervallo sorgente. Le parti rimosse non
   compaiono e i salti restano discontinuità tra segmenti.
2. `SentenceChunker` lavora sul testo filtrato, anche per un sotto-intervallo
   (prefisso immediato e remainder), e produce `SourceTextRange` relativi al
   testo catturato.
3. La base assoluta AX (`ContinuousCaptureStart.sourceRange.location` o
   `CapturedSelection.trimmedSourceRange.location`, allora `AXCaptureResult`)
   viene sommata **una sola volta**, dopo il chunking.
4. Il trimming iniziale della selezione avanza la base di quante unità UTF-16
   sono state rimosse, non di quanti `Character`.
5. `TextNormalizer` lavora **dopo** il chunking: cambia il testo pronunciato,
   non la geometria. `ReadingChunk.replacingText` preserva `sourceRange` e
   `sourceDocumentID`.

Un range non valido o fuori dal testo filtrato restituisce `nil`. Un chunk senza
range non produce alcuna scrittura: non si inventa una posizione.

### 3. Sospensione in background e stop sull'input

La scrittura AX funzionerebbe anche in background, ma la policy di prodotto
sospende gli aggiornamenti quando l'app di origine non è frontmost. L'audio
continua. Al ritorno frontmost, `SourceSelectionController` riapplica l'ultimo
range corrente; se nel frattempo il chunk è diventato non mappabile, il range
viene invalidato e non si riapplica la frase precedente.

Una sessione si ferma quando l'utente interagisce **nell'app di origine**:

- `keyDown`, incluse scorciatoie e paste;
- `leftMouseDown`, `leftMouseDragged`, `rightMouseDown`, `otherMouseDown`.

Lo scroll con rotella o trackpad è consentito e non ferma la sessione. Il
monitor globale `NSEvent` osserva senza modificare gli eventi e senza rubare il
focus. In parallelo, un `AXObserver` su `kAXSelectedTextChangedNotification`
confronta il readback con l'ultimo range scritto e applica un debounce di 60 ms:
le notifiche generate dalla nostra scrittura vengono ignorate. Il callback di
stop arriva una sola volta per sessione e ferma la lettura, non solo
l'evidenziazione.

Pausa e stop non deselezionano la frase corrente. Alla ripresa si rivaluta il
chunk corrente. Non si ripristina automaticamente la selezione iniziale.

### 4. Auto-scroll e limiti

Non esiste un auto-scroll custom. Si sfrutta lo scroll nativo prodotto dalla
selezione impostata:

- **TextEdit**: la selezione fuori viewport scrolla da sola; i bounds sono
  utilizzabili, ma non servono in fase 1.
- **Safari**: la selezione fuori viewport scrolla da sola. L'highlight è
  visibile solo con la web area focalizzata; non si forza il focus.
- **VS Code**: la selezione **non** scrolla e `AXBoundsForRange` restituisce
  `{0,0}`; `AXScrollToVisible` è un no-op. Una frase fuori viewport resta non
  visibile; non si simula PageDown e non si costruisce un overlay senza
  geometria. In quel caso resta il fallback Studio.

“Riduci movimento” è rispettato perché non ci sono animazioni custom: l'unico
movimento è quello nativo dell'app quando la selezione entra in viewport.

### 5. Fallback Studio

La lista dello Studio continua a evidenziare il chunk corrente confrontando
`appState.currentChunk?.id` con l'id della riga. È il comportamento previsto, non
un bug, quando:

- il testo è manuale o arriva dagli appunti;
- l'app non espone una selezione AX scrivibile;
- la cattura è il fallback clipboard;
- il chunk o la pagina non hanno un range mappabile;
- la scrittura restituisce `.unsupported` o `.failed`.

Il toggle “Evidenzia la frase nell'app di origine” è persistito in
`UserDefaults`, è attivo di default e resta disponibile anche senza permessi di
Accessibilità; in quel caso l'evidenziazione nativa è inattiva e lo Studio mostra
un avviso discreto. Spegnere il toggle non ferma l'audio.

### 6. Limiti noti

- **Safari**: il marker range è scrivibile, ma l'highlight può non essere
  disegnato se la web area non è focalizzata. Il comportamento dipende dalla
  versione di Safari e non si corregge rubando il focus.
- **Word**: non è installato nell'ambiente di validazione. Il supporto resta
  **best effort** e non è dichiarato verificato.
- **Preview/PDF**: non espone un'ancora AX utilizzabile; la lettura continua è
  best effort e l'evidenziazione ripiega sullo Studio.
- **Documenti paginati o virtualizzati**: le pagine successive possono non avere
  un range continuo. L'evidenziazione si ferma all'ultima porzione mappata e la
  lettura prosegue nello Studio.
- **Snapshot**: la cattura è un'istantanea al Play; le modifiche successive del
  documento non vengono inseguite.
- **App senza selezione scrivibile**: fase 1 con fallback Studio; nessun overlay
  automatico.

### 7. Race Q20: la prima digitazione

La selezione nativa vive nell'editor dell'app di origine. Quando l'utente inizia
a digitare, il primo `keyDown` può arrivare all'editor **prima** che il monitor
globale consegni lo stop: il carattere sostituisce quindi la frase selezionata.
La sessione si ferma subito dopo, ma il testo può essere già cambiato.

È un limite accettato della fase 1. Non si tenta di annullare la digitazione, non
si ripristina il testo e non si rallenta il monitor: intercettare e annullare
l'input sarebbe più invasivo del problema che risolve. La documentazione utente
deve descrivere il comportamento, non promettere che la selezione sia
intoccabile.

### 8. Fase 2 esplicitamente fuori perimetro

Sono fuori da questa decisione e non sono promessi dalla fase 1:

- evidenziazione parola-per-parola;
- forced alignment o timing dei fonemi;
- overlay trasparente sopra l'app di origine;
- karaoke proporzionale o sincronizzato alle parole.

La fase 2 richiede una decisione separata su allineamento reale, geometria e
overlay. DSA-6 (Teleprompter HUD nello Studio) resta un'iniziativa distinta e non
è l'evidenziazione dentro le app terze.

## Conseguenze

**Positive**

- La frase corrente è visibile nell'app di origine senza una finestra separata.
- Focus, testo e appunti restano intatti; nessun evento di tastiera simulato.
- L'audio non si interrompe quando l'evidenziazione non è disponibile.
- Il mapping UTF-16 è esatto anche con filtro, split e normalizzazione.
- La policy è testabile senza GUI: writer, PID frontmost e monitor sono iniettati.

**Negative / limiti**

- VS Code non porta in vista le frasi fuori viewport.
- Safari richiede una web area focalizzata per mostrare l'highlight.
- La race Q20 resta possibile.
- Le pagine virtualizzate possono perdere il range e passare allo Studio.
- Word e Preview/PDF non sono coperti end-to-end.

## Alternative scartate

- **Evidenziare parole in fase 1**: richiede timing o forced alignment che il
  motore vocale attuale non espone; sarebbe una promessa non verificabile.
- **Overlay custom sopra l'app**: servono bounds affidabili, assenti in VS Code e
  in Preview; aumenta il rischio di rubare focus e di disallinearsi allo scroll.
- **Modificare `AXValue` o il testo**: altera il documento e può corrompere
  l'editor.
- **Inviare `CGEvent` per selezionare o scrollare**: viola il vincolo di non
  rubare il focus e può attivare l'app sbagliata.
- **Deselezionare a pausa/stop**: per l'utente è un cambio di contesto inutile;
  la frase corrente resta selezionata.
- **Evidenziare solo nello Studio**: non realizza la doppia codifica nel punto di
  lettura; resta come fallback, non come default.

## Verifica

- `swift build` verde.
- `swift test`: **109 test, 0 failure**. Le suite direttamente coinvolte sono
  `SourceSelectionControllerTests` (15), `SourceRangeMappingTests` (14),
  `SourceHighlightPreferenceTests` (5) e `PlaybackCoordinatorTests` (7).
- La sonda 01 ha verificato la scrittura AX su TextEdit, Safari e VS Code:
  readback esatto, testo invariato, focus preservato; TextEdit/Safari scrollano
  da soli, VS Code no.
- La matrice GUI end-to-end (playback reale, click e scroll hardware, toggle,
  Q20) **non è stata eseguita in questa sessione headless**. Resta tracciata nel
  ticket 05 di `.scratch/dsa-10-frase/` e va completata prima di dichiarare la
  fase 1 chiusa sul campo.
