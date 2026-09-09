import Foundation

/// Modulo di normalizzazione fonetica ed espansione del testo prima della sintesi vocale.
public struct TextNormalizer: Sendable {
    
    public init() {}
    
    /// Normalizza un testo espandendo valute, simboli, link e abbreviazioni frequenti.
    ///
    /// - Parameters:
    ///   - text: Testo grezzo in ingresso.
    ///   - exclusions: Lista di stringhe o firme escluse da rimuovere prima della lettura.
    /// - Returns: Testo foneticamente ottimizzato per la sintesi vocale.
    public func normalize(text: String, exclusions: [String] = []) -> String {
        var processed = filterExclusions(text: text, exclusions: exclusions)
        
        // 1. URLs e Link Web
        processed = processed.replacingOccurrences(
            of: #"https?:\/\/[^\s]+"#,
            with: "link web",
            options: .regularExpression
        )
        
        // 2. Indirizzi Email
        processed = processed.replacingOccurrences(
            of: #"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
            with: "indirizzo email",
            options: .regularExpression
        )
        
        // 3. Valuta Euro con decimali: es. "12,50 €" o "12.50€" -> "12 euro e 50 centesimi"
        processed = processed.replacingOccurrences(
            of: #"(\d+)[,\.](\d{2})\s*€"#,
            with: "$1 euro e $2 centesimi",
            options: .regularExpression
        )
        
        // 4. Valuta Euro intera: es. "50 €" o "€ 50" -> "50 euro"
        processed = processed.replacingOccurrences(
            of: #"(\d+)\s*€"#,
            with: "$1 euro",
            options: .regularExpression
        )
        processed = processed.replacingOccurrences(
            of: #"€\s*(\d+)"#,
            with: "$1 euro",
            options: .regularExpression
        )
        
        // 5. Percentuali: es. "25%" -> "25 per cento"
        processed = processed.replacingOccurrences(
            of: #"(\d+)\s*%"#,
            with: "$1 per cento",
            options: .regularExpression
        )
        
        // 6. Abbreviazioni comuni italiane
        let wordReplacements: [(pattern: String, replacement: String)] = [
            (#"\b[Ee]s\.\s*"#, "ad esempio "),
            (#"\b[Ee]cc\.\s*"#, "eccetera "),
            (#"\b[Aa]rt\.\s*(\d+)"#, "articolo $1"),
            (#"\b[Pp]ag\.\s*(\d+)"#, "pagina $1"),
            (#"\b[Pp]agg\.\s*(\d+)"#, "pagine $1"),
            (#"\b[Nn]\.\s*(\d+)"#, "numero $1"),
            (#"\b[Dd]ott\.\s*"#, "Dottor "),
            (#"\b[Dd]ott\.ssa\s*"#, "Dottoressa "),
            (#"\b[Pp]rof\.\s*"#, "Professor "),
            (#"\b[Pp]rof\.ssa\s*"#, "Professoressa "),
            (#"\b[Aa]vv\.\s*"#, "Avvocato "),
            (#"\b[Ii]ng\.\s*"#, "Ingegner ")
        ]
        
        for rule in wordReplacements {
            processed = processed.replacingOccurrences(
                of: rule.pattern,
                with: rule.replacement,
                options: .regularExpression
            )
        }
        
        // Rimuovi spazi doppi orfani
        processed = processed.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        
        return processed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Rimuove dal testo le stringhe blacklistate configurate dall'utente.
    public func filterExclusions(text: String, exclusions: [String]) -> String {
        var cleaned = text
        for item in exclusions {
            let pattern = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty else { continue }
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .caseInsensitive)
        }
        return cleaned
    }
}
