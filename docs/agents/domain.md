# Domain Docs

Come le skill di ingegneria devono consumare la documentazione di dominio di questo repo durante l'esplorazione del codice.

## Prima di esplorare, leggi

- **`GLOSSARY.md`** alla root del repo.
- **`docs/adr/`**: leggi gli ADR che toccano l'area su cui stai per lavorare.

Se questi file non esistono, **procedi in silenzio**. Non segnalarne l'assenza e non proporne la creazione in anticipo. La skill `/domain-modeling` (raggiungibile via `/grill-with-docs` e `/improve-codebase-architecture`) li crea in modo lazy quando termini o decisioni vengono effettivamente risolti.

## Layout

Repo single-context:

```
/
├── GLOSSARY.md
├── docs/adr/
│   ├── 001-cattura-testo-nativa-rust-axuielement.md
│   └── 002-serializzazione-inferenza-onnx-lock-sincrono.md
└── Sources/
```

## Altri documenti di dominio presenti nel repo

Questi file non sono il modello di dominio delle skill, ma vanno letti quando la domanda li riguarda:

- **`repo-docs/glossary.md`**: tabella dei termini tecnici con stato `Confirmed`/`Planned`, rivolta a chi legge la guida del repository. Se un termine cambia, aggiorna anche questa tabella: il validatore `repo-docs` ne controlla la copertura.
- **`dev-docs/`**: documenti strategici (roadmap, feature, bug, checklist di test). Sono la fonte di verità di prodotto, non di dominio.
- **`audit-progetto.md`**: audit storico, non normativo.

## Usa il vocabolario del glossario

Quando il tuo output nomina un concetto di dominio (in un titolo di issue, una proposta di refactor, un'ipotesi, il nome di un test), usa il termine come definito in `GLOSSARY.md`. Non scivolare verso i sinonimi che il glossario elenca sotto `_Avoid_`.

Se il concetto che ti serve non è ancora nel glossario, è un segnale: o stai inventando linguaggio che il progetto non usa (rivaluta), oppure c'è una lacuna reale (annotala per `/domain-modeling`).

## Segnala i conflitti con gli ADR

Se il tuo output contraddice un ADR esistente, rendilo esplicito invece di sovrascriverlo in silenzio:

> _Contrasta con ADR-008 (rewrite 100% nativo macOS), ma vale la pena riaprirlo perché…_
