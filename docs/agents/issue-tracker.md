# Issue tracker: Markdown locale

Le issue e le specifiche di questo repo vivono come file Markdown in `.scratch/`.

## Convenzioni

- Una feature per directory: `.scratch/<feature-slug>/`
- La specifica è `.scratch/<feature-slug>/spec.md`
- Le issue di implementazione sono un file per ticket in `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numerati da `01`, mai un unico file combinato
- Lo stato di triage è una riga `Status:` vicino all'inizio di ogni file issue (vedi `triage-labels.md` per le stringhe dei ruoli)
- Commenti e cronologia conversazionale si accodano in fondo al file sotto un'intestazione `## Comments`

## Quando una skill dice "publish to the issue tracker"

Crea un nuovo file sotto `.scratch/<feature-slug>/` (creando la directory se necessario).

## Quando una skill dice "fetch the relevant ticket"

Leggi il file al percorso indicato. Normalmente l'utente passa direttamente il percorso o il numero della issue.

## Operazioni di wayfinding

Usate da `/wayfinder`. La **mappa** è un file con un **file figlio** per ticket.

- **Mappa**: `.scratch/<effort>/map.md` (il corpo con Note / Decisioni finora / Nebbia).
- **Ticket figlio**: `.scratch/<effort>/issues/NN-<slug>.md`, numerato da `01`, con la domanda nel corpo. Una riga `Type:` registra il tipo di ticket (`research`/`prototype`/`grilling`/`task`); una riga `Status:` registra `claimed`/`resolved`.
- **Blocco**: una riga `Blocked by: NN, NN` vicino all'inizio. Un ticket è sbloccato quando ogni file elencato è `resolved`.
- **Frontiera**: scansiona `.scratch/<effort>/issues/` per file aperti, sbloccati e non reclamati; vince il primo per numero.
- **Claim**: imposta `Status: claimed` e salva prima di qualsiasi lavoro.
- **Resolve**: accoda la risposta sotto un'intestazione `## Answer`, imposta `Status: resolved`, poi accoda un puntatore di contesto (sintesi + link) alle Decisioni-finora in `map.md`.
