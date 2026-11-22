import Foundation

/// Modulo di normalizzazione fonetica ed espansione del testo prima della sintesi vocale.
public struct TextNormalizer: Sendable {

    /// Regola precompilata: `NSRegularExpression` non è `Sendable`, ma è
    /// immutabile e sicura da condividere tra thread.
    private struct RegexRule: @unchecked Sendable {
        let regex: NSRegularExpression
        let template: String
    }

    /// Le regole sono compilate una sola volta e applicate nello stesso ordine
    /// della versione storica, a ogni chunk.
    private static let rules: [RegexRule] = {
        let specs: [(pattern: String, template: String)] = [
            // 1. URLs e Link Web
            (#"https?:\/\/[^\s]*[^\s.,;:!?)\]\}]"#, "link web"),
            (#"\bwww\.[^\s]*[^\s.,;:!?)\]\}]"#, "link web"),
            // 2. Indirizzi Email
            (#"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, "indirizzo email"),
            // 3. Valuta Euro con simbolo anteposto: es. "€12,50"
            (#"€\s*(\d+)[,.](\d{2})"#, "$1 euro e $2 centesimi"),
            // 4. Valuta Euro con decimali: es. "12,50 €" o "12.50€"
            (#"(\d+)[,\.](\d{2})\s*€"#, "$1 euro e $2 centesimi"),
            // 5. Valuta Euro intera: es. "50 €" o "€ 50"
            (#"(\d+)\s*€"#, "$1 euro"),
            (#"€\s*(\d+)"#, "$1 euro"),
            // 6. Percentuali: es. "25%"
            (#"(\d+)\s*%"#, "$1 per cento"),
            // 7. Abbreviazioni comuni italiane
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
            (#"\b[Ii]ng\.\s*"#, "Ingegner "),
            // 8. Rimuovi variation selectors Unicode e caratteri invisibili
            (#"[\x{FE00}-\x{FE0F}\x{200B}\x{FEFF}]"#, ""),
            // Rimuovi spazi doppi orfani
            (#"\s{2,}"#, " ")
        ]
        return specs.compactMap { spec in
            guard let regex = try? NSRegularExpression(pattern: spec.pattern) else { return nil }
            return RegexRule(regex: regex, template: spec.template)
        }
    }()

    public init() {}

    /// Normalizza un testo espandendo valute, simboli, link e abbreviazioni frequenti.
    ///
    /// - Parameters:
    ///   - text: Testo grezzo in ingresso.
    ///   - exclusions: Lista di stringhe o firme escluse da rimuovere prima della lettura.
    /// - Returns: Testo foneticamente ottimizzato per la sintesi vocale.
    public func normalize(text: String, exclusions: [String] = []) -> String {
        var processed = filterExclusions(text: text, exclusions: exclusions)

        for rule in Self.rules {
            processed = rule.regex.stringByReplacingMatches(
                in: processed,
                range: NSRange(location: 0, length: (processed as NSString).length),
                withTemplate: rule.template
            )
        }

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
