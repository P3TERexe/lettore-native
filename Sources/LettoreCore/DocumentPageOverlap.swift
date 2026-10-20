import Foundation

/// Deduplicazione del testo tra due viewport consecutive di un documento.
///
/// Il paging ricostruisce la viewport visibile a ogni scorrimento: due
/// raccolte successive condividono una testa (la parte ancora a schermo dopo
/// lo scroll). La parte nuova è `new` privato del più lungo suffisso di `old`
/// che coincide con un prefisso di `new`.
///
/// L'algoritmo è KMP (funzione di fallimento): tempo e memoria lineari nel
/// limite di ricerca, al contrario del confronto quadratico naive. Il limite
/// è `min(old.count, new.count)` per default, così un overlap reale non viene
/// mai scartato per un cap fisso troppo basso.
public enum DocumentPageOverlap {

    /// Restituisce la parte di `new` che non era già presente in coda a `old`.
    ///
    /// - Parameters:
    ///   - old: la viewport precedente (già letta).
    ///   - new: la viewport corrente dopo lo scorrimento.
    ///   - maxOverlap: limite massimo di caratteri confrontati; se `nil` il
    ///     limite è l'intera pagina (`min(old.count, new.count)`).
    /// - Returns: `new` senza la testa già contenuta in `old`; `new` invariato
    ///   se non esiste alcun overlap.
    public static func textAfterOverlap(
        _ old: String,
        _ new: String,
        maxOverlap: Int? = nil
    ) -> String {
        guard !new.isEmpty else { return "" }
        guard !old.isEmpty else { return new }

        let limit = maxOverlap.map { min($0, min(old.count, new.count)) } ?? min(old.count, new.count)
        guard limit > 0 else { return new }

        let pattern = Array(new.prefix(limit))
        let haystack = Array(old.suffix(limit))

        let overlap = longestPrefix(of: pattern, matchingSuffixOf: haystack)
        guard overlap > 0 else { return new }

        return String(new.dropFirst(overlap))
    }

    // MARK: - KMP

    /// Lunghezza del più lungo prefisso di `pattern` che è anche suffisso di
    /// `haystack`.
    private static func longestPrefix(of pattern: [Character], matchingSuffixOf haystack: [Character]) -> Int {
        guard !pattern.isEmpty else { return 0 }

        let failure = failureFunction(of: pattern)
        var matched = 0

        for character in haystack {
            // Dopo una corrispondenza completa il prossimo carattere deve
            // ripartire dal più lungo bordo della parola.
            if matched == pattern.count {
                matched = failure[matched - 1]
            }

            while matched > 0 && character != pattern[matched] {
                matched = failure[matched - 1]
            }

            if character == pattern[matched] {
                matched += 1
            }
        }

        return matched
    }

    private static func failureFunction(of pattern: [Character]) -> [Int] {
        var failure = [Int](repeating: 0, count: pattern.count)
        var matched = 0
        var index = 1

        while index < pattern.count {
            if pattern[index] == pattern[matched] {
                matched += 1
                failure[index] = matched
                index += 1
            } else if matched > 0 {
                matched = failure[matched - 1]
            } else {
                failure[index] = 0
                index += 1
            }
        }

        return failure
    }
}
