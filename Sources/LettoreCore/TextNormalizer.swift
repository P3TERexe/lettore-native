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
            of: #"https?:\/\/[^\s]*[^\s.,;:!?)\]\}]"#,
            with: "link web",
            options: .regularExpression
        )
        processed = processed.replacingOccurrences(
            of: #"\bwww\.[^\s]*[^\s.,;:!?)\]\}]"#,
            with: "link web",
            options: .regularExpression
        )
        
        // 2. Indirizzi Email
        processed = processed.replacingOccurrences(
            of: #"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
            with: "indirizzo email",
            options: .regularExpression
        )
        
        // 3. Valuta Euro con simbolo anteposto: es. "€12,50"
        processed = processed.replacingOccurrences(
            of: #"€\s*(\d+)[,.](\d{2})"#,
            with: "$1 euro e $2 centesimi",
            options: .regularExpression
        )

        // 4. Valuta Euro con decimali: es. "12,50 €" o "12.50€" -> "12 euro e 50 centesimi"
        processed = processed.replacingOccurrences(
            of: #"(\d+)[,\.](\d{2})\s*€"#,
            with: "$1 euro e $2 centesimi",
            options: .regularExpression
        )
        
        // 5. Valuta Euro intera: es. "50 €" o "€ 50" -> "50 euro"
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
        
        // 6. Percentuali: es. "25%" -> "25 per cento"
        processed = processed.replacingOccurrences(
            of: #"(\d+)\s*%"#,
            with: "$1 per cento",
            options: .regularExpression
        )
        
        // 7. Abbreviazioni comuni italiane
        let wordReplacements: [(pattern: String, replacement: String)] = [
            (#"\b[Ee]s\.\s*"#, "ad esempio "),
            (#"\b[Ee]cc\.\s*"#, "eccetera "),
            (#"\b[Aa]rt\.\s*(\d+)"#, "articolo $1"),
            (#"\b[Pp]ag\.\s*(\d+)"#, "pagina $1"),
            (#"\b[Pp]agg\.\s*(\d+)"#, "pagine $1"),
            (#"\b[Nn]\.\s*(\d+)"#, "numero $1"),
            // I titoli femminili vanno prima delle forme base: `Dott.` con
            // `\s*` intercetterebbe anche il prefisso di `Dott.ssa`.
            (#"\b[Dd]ott\.ssa\s*"#, "Dottoressa "),
            (#"\b[Dd]ott\.(?!ssa)\s*"#, "Dottor "),
            (#"\b[Pp]rof\.ssa\s*"#, "Professoressa "),
            (#"\b[Pp]rof\.(?!ssa)\s*"#, "Professor "),
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
        
        // 8. Rimuovi variation selectors Unicode e caratteri invisibili
        processed = processed.replacingOccurrences(
            of: #"[\x{FE00}-\x{FE0F}\x{200B}\x{FEFF}]"#,
            with: "",
            options: .regularExpression
        )
        
        // Rimuovi spazi doppi orfani
        processed = processed.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        
        return processed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Normalizza il testo di un chunk già segmentato, senza toccare la mappa
    /// sorgente.
    ///
    /// Il range è stato calcolato sul testo grezzo/filtrato prima della
    /// normalizzazione: espandere valute o URL cambia la lunghezza del testo
    /// pronunciato, non la geometria della frase nel documento.
    public func normalize(_ chunk: ReadingChunk, exclusions: [String] = []) -> ReadingChunk {
        let normalized = normalize(text: chunk.rawText, exclusions: exclusions)
        return chunk.replacingText(normalized)
    }

    /// Applica `normalize(_:exclusions:)` a una coda già segmentata.
    public func normalize(_ chunks: [ReadingChunk], exclusions: [String] = []) -> [ReadingChunk] {
        chunks.map { normalize($0, exclusions: exclusions) }
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
