import Foundation

/// Decide quando vale la pena scandagliare l'albero del viewport durante
/// l'attesa di un cambio pagina.
///
/// La DFS del contenitore costa centinaia di nodi: con una scroll bar leggibile
/// si evita finché il suo valore non si muove. Il solo valore della barra però
/// non è una prova sufficiente: alcune app aggiornano il testo senza spostarla
/// (o con un valore che resta fermo), quindi serve un tick di sicurezza che
/// scandagli comunque ogni quattro tentativi. Senza scroll bar il campionamento
/// scende a una DFS ogni due tentativi: è una scelta voluta di questa policy
/// (prima si scandagliava a ogni tentativo), non una cadenza storica.
///
/// L'ultimo tentativo della finestra raccoglie sempre: è lì che il chiamante
/// decide se ripiegare su PageDown, e saltarlo con una barra immobile
/// significherebbe credere fallito uno scroll già avvenuto (doppio scroll).
///
/// Funzione pura, senza timer né stato: il ciclo di attesa resta in
/// `AXCaptureService+Continuous`.
public enum ViewportPollingPolicy {

    /// - Parameters:
    ///   - attempt: indice del tentativo, 0-based. I valori negativi sono
    ///     normalizzati a 0 (primo tentativo).
    ///   - totalAttempts: numero di tentativi della finestra di attesa. Un
    ///     valore non positivo viene trattato come 1, così ogni tentativo è
    ///     anche l'ultimo.
    ///   - scrollBarAvailable: la scroll bar verticale espone un valore
    ///     leggibile.
    ///   - scrollBarChanged: il valore della barra è cambiato almeno una volta
    ///     dall'inizio dell'attesa.
    /// - Returns: `true` quando il chiamante deve raccogliere il testo.
    public static func shouldCollect(
        attempt: Int,
        totalAttempts: Int,
        scrollBarAvailable: Bool,
        scrollBarChanged: Bool
    ) -> Bool {
        let tick = max(0, attempt)
        let lastAttempt = max(1, totalAttempts) - 1

        // Rete di sicurezza finale: senza una DFS all'ultimo tentativo il
        // chiamante non distingue "scroll non avvenuto" da "testo in ritardo"
        // e ripiegherebbe su PageDown dopo uno scroll già eseguito.
        if tick >= lastAttempt { return true }

        if scrollBarChanged { return true }

        if !scrollBarAvailable {
            return tick % 2 == 0
        }

        // Tick di sicurezza: tentativi 3, 7, 11 di una finestra di 14.
        return tick % 4 == 3
    }
}
