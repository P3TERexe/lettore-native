import Foundation

/// Modalità di pulizia del testo per le catture documentali continue.
///
/// Il filtro è volutamente conservativo: agisce solo su rumore strutturale
/// (numeri di pagina, intestazioni/piè di pagina ripetuti, parole spezzate a
/// fine riga) e non rimuove note o citazioni, che restano fuori dal perimetro
/// della lettura continua (DSA-1, DSA-9).
public enum NoiseFilterMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case light

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: return "Nessuno"
        case .light: return "Leggero"
        }
    }
}

/// Filtro del rumore tipografico di documenti lunghi.
public struct DocumentNoiseFilter: Sendable {

    public init() {}

    public func filter(_ text: String, mode: NoiseFilterMode) -> String {
        guard mode == .light else { return text }

        var cleaned = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        cleaned = dehyphenateLineBreaks(cleaned)
        cleaned = cleaned.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )

        let blocks = cleaned.components(separatedBy: "\n\n")
        let repeatedEdges = repeatedEdgeLines(in: blocks)

        var output: [String] = []
        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            let filtered = lines.filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return true }
                if isPageNumber(trimmed) { return false }
                if repeatedEdges.contains(normalizedKey(trimmed)) { return false }
                return true
            }

            let joined = filtered.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                output.append(joined)
            }
        }

        return output.joined(separator: "\n\n")
    }

    // MARK: - Euristiche

    /// Unisce le parole spezzate da un trattino a fine riga, ma solo quando la
    /// riga successiva inizia con una minuscola: evita di incollare nomi
    /// propri o titoli che iniziano con una maiuscola.
    private func dehyphenateLineBreaks(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"([\p{L}])[-‐‑][ \t]*\n[ \t]*([\p{Ll}])"#,
            with: "$1$2",
            options: .regularExpression
        )
    }

    private func repeatedEdgeLines(in blocks: [String]) -> Set<String> {
        var counts: [String: Int] = [:]

        for block in blocks {
            let lines = block
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard let first = lines.first, let last = lines.last else { continue }

            for line in Set([first, last]) where isRunningHeaderCandidate(line) {
                counts[normalizedKey(line), default: 0] += 1
            }
        }

        return Set(counts.filter { $0.value >= 3 }.map(\.key))
    }

    private func isRunningHeaderCandidate(_ line: String) -> Bool {
        guard line.count >= 2, line.count <= 80 else { return false }
        guard line.contains(where: \.isLetter) else { return false }
        guard !isPageNumber(line) else { return false }

        // Una frase completa non è un'intestazione di pagina.
        let last = line.last
        if last == "." || last == "!" || last == "?" {
            return false
        }
        return true
    }

    private func isPageNumber(_ line: String) -> Bool {
        let patterns = [
            #"^\s*(?:[—–-]\s*)?\d{1,4}(?:\s*[—–-])?\s*$"#,
            #"^\s*(?:pag(?:ina)?\.?\s*)\d{1,4}(?:\s*(?:di|/)\s*\d{1,4})?\s*$"#,
            #"^\s*\d{1,4}\s*/\s*\d{1,4}\s*$"#
        ]

        return patterns.contains { pattern in
            line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private func normalizedKey(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
