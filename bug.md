# Bug Report 1

## Description
C'è un problema con il pitch (tono) della voce in relazione alla velocità di riproduzione.

## Steps to Reproduce
1. Avviare la riproduzione vocale.
2. Modificare la velocità di riproduzione.
3. Ascoltare l'effetto sulla voce.

## Expected Behavior
Il pitch della voce dovrebbe rimanere naturale e costante, senza subire distorsioni quando si modifica la velocità di lettura.

## Actual Behavior
Il pitch della voce risulta alterato in modo anomalo o innaturale quando si varia la velocità.

---

# Bug Report 2

## Description
Non funziona il cambio della voce dalle impostazioni: la sintesi continua a usare la voce precedente.

## Steps to Reproduce
1. Aprire Impostazioni → Voce.
2. Selezionare una voce diversa da quella attiva.
3. Avviare la lettura di un testo.

## Expected Behavior
La voce selezionata viene usata per la sintesi del testo.

## Actual Behavior
La lettura continua con la voce precedente; il cambio non ha alcun effetto.

---

# Bug Report 3

## Description
Il motore spesso confonde le lingue: la pronuncia non corrisponde alla lingua del testo.

## Steps to Reproduce
1. Inserire un testo in una lingua (es. italiano) e avviare la lettura.
2. Ripetere con testi in lingue diverse o miste nella stessa sessione.

## Expected Behavior
La lingua rilevata/selezionata corrisponde al testo e la pronuncia è corretta.

## Actual Behavior
Il testo viene sintetizzato con pronuncia/accento della lingua sbagliata, soprattutto alternando testi in lingue diverse.

---

# Bug Report 4

## Description
La finestra in modalità pillola (compact) non si può spostare trascinandola.

## Steps to Reproduce
1. Attivare la modalità compact/pillola (bottone "Cambia visualizzazione" nella sidebar).
2. Provare a spostare la finestra trascinando la player strip.

## Expected Behavior
Trascinando lo strip la finestra si sposta (drag region attiva).

## Actual Behavior
La finestra non si sposta: il drag non parte.
