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
///
/// `filter` resta l'API storica e restituisce solo il testo. `filterWithMapping`
/// restituisce anche la mappa UTF-16 verso la sorgente, necessaria per
/// evidenziare la frase nell'app di origine.
public struct DocumentNoiseFilter: Sendable {

    public init() {}

    public func filter(_ text: String, mode: NoiseFilterMode) -> String {
        filterWithMapping(text, mode: mode).text
    }

    /// Filtra il testo mantenendo la corrispondenza con gli offset UTF-16
    /// originali. Con `.off` la mappa è identità.
    public func filterWithMapping(_ text: String, mode: NoiseFilterMode) -> FilteredText {
        guard mode == .light else { return FilteredText.identity(text) }

        var current = FilteredText.identity(text)
        current = normalizeNewlines(in: current)
        current = dehyphenateLineBreaks(in: current)
        current = collapseExtraNewlines(in: current)
        return removeEdgeNoise(in: current)
    }

    // MARK: - Fasi di filtro

    /// `\r\n` diventa `\n` eliminando il solo `\r`; un `\r` isolato diventa
    /// `\n` senza cambiare lunghezza, quindi la mappa resta valida.
    private func normalizeNewlines(in text: FilteredText) -> FilteredText {
        let nsText = text.text as NSString
        var deletions: [Range<Int>] = []
        var searchLocation = 0

        while searchLocation < nsText.length {
            let found = nsText.range(
                of: "\r\n",
                options: [],
                range: NSRange(location: searchLocation, length: nsText.length - searchLocation)
            )
            guard found.location != NSNotFound else { break }
            deletions.append(found.location..<(found.location + 1))
            searchLocation = found.location + found.length
        }

        var result = text.deleting(utf16Ranges: deletions)
        if result.text.contains("\r") {
            result = result.replacingCharactersPreservingMapping(
                result.text.replacingOccurrences(of: "\r", with: "\n")
            )
        }
        return result
    }

    /// Unisce le parole spezzate da un trattino a fine riga, ma solo quando la
    /// riga successiva inizia con una minuscola: evita di incollare nomi
    /// propri o titoli che iniziano con una maiuscola.
    ///
    /// La trasformazione è una rimozione: si eliminano trattino, spazi e
    /// newline tra le due lettere, quindi il testo filtrato resta mappabile.
    private func dehyphenateLineBreaks(in text: FilteredText) -> FilteredText {
        guard let regex = try? NSRegularExpression(
            pattern: #"([\p{L}])[-‐‑][ \t]*\n[ \t]*([\p{Ll}])"#
        ) else {
            return text
        }

        let nsText = text.text as NSString
        let matches = regex.matches(
            in: text.text,
            range: NSRange(location: 0, length: nsText.length)
        )

        let deletions: [Range<Int>] = matches.compactMap { match in
            let first = match.range(at: 1)
            let second = match.range(at: 2)
            guard first.location != NSNotFound,
                  second.location != NSNotFound else {
                return nil
            }
            let start = first.location + first.length
            let end = second.location
            return start < end ? start..<end : nil
        }

        return text.deleting(utf16Ranges: deletions)
    }

    /// Riduce tre o più newline consecutivi a due, eliminando solo quelli in
    /// eccesso.
    private func collapseExtraNewlines(in text: FilteredText) -> FilteredText {
        guard let regex = try? NSRegularExpression(pattern: #"\n{3,}"#) else {
            return text
        }

        let nsText = text.text as NSString
        let matches = regex.matches(
            in: text.text,
            range: NSRange(location: 0, length: nsText.length)
        )

        let deletions: [Range<Int>] = matches.compactMap { match in
            let keep = 2
            guard match.range.length > keep else { return nil }
            let start = match.range.location + keep
            return start..<(match.range.location + match.range.length)
        }

        return text.deleting(utf16Ranges: deletions)
    }

    /// Rimuove numeri di pagina e righe di intestazione/piè di pagina ripetute,
    /// ricostruendo il testo con gli stessi separatori del filtro storico.
    private func removeEdgeNoise(in text: FilteredText) -> FilteredText {
        let blocks = blockRanges(in: text.text)
        let repeatedEdges = repeatedEdgeLines(in: text.text.components(separatedBy: "\n\n"))

        var builder = FilteredTextBuilder(sourceLength: text.sourceLength)
        var previousBlockSourceEnd: Int?

        for block in blocks {
            let lines = lineRanges(in: text.text, within: block)
            let keptLines = lines.filter { line in
                let lineText = (text.text as NSString).substring(with: line.nsRange)
                return shouldKeepLine(lineText, repeatedEdges: repeatedEdges)
            }
            guard !keptLines.isEmpty else { continue }

            var blockBuilder = FilteredTextBuilder(sourceLength: text.sourceLength)
            for (index, line) in keptLines.enumerated() {
                if index > 0 {
                    let previousLine = keptLines[index - 1]
                    let gapStart = text.mapEnd(previousLine.upperBound) ?? 0
                    let gapEnd = text.mapStart(line.lowerBound) ?? gapStart
                    blockBuilder.append(
                        "\n",
                        mappingTo: SourceTextRange(location: gapStart, length: max(0, gapEnd - gapStart))
                    )
                }
                blockBuilder.append(text, range: line)
            }

            var blockText = blockBuilder.build()
            let edgeWhitespace = whitespaceEdgeRanges(in: blockText.text)
            if !edgeWhitespace.isEmpty {
                blockText = blockText.deleting(utf16Ranges: edgeWhitespace)
            }
            guard !blockText.text.isEmpty else { continue }

            if !builder.isEmpty, let previousEnd = previousBlockSourceEnd {
                let gapEnd = text.mapStart(block.lowerBound) ?? previousEnd
                builder.append(
                    "\n\n",
                    mappingTo: SourceTextRange(location: previousEnd, length: max(0, gapEnd - previousEnd))
                )
            }

            builder.append(blockText)
            previousBlockSourceEnd = blockText.mapEnd(blockText.utf16Length) ?? text.mapEnd(block.upperBound)
        }

        return builder.build()
    }

    // MARK: - Euristiche

    private func shouldKeepLine(_ line: String, repeatedEdges: Set<String>) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if isPageNumber(trimmed) { return false }
        if repeatedEdges.contains(normalizedKey(trimmed)) { return false }
        return true
    }

    /// Range dei blocchi separati da una riga vuota, inclusi i blocchi vuoti
    /// per replicare `components(separatedBy: "\n\n")`.
    private func blockRanges(in text: String) -> [Range<Int>] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [0..<0] }

        var result: [Range<Int>] = []
        var start = 0

        while start <= nsText.length {
            let found = nsText.range(
                of: "\n\n",
                options: [],
                range: NSRange(location: start, length: nsText.length - start)
            )
            guard found.location != NSNotFound else {
                result.append(start..<nsText.length)
                break
            }
            result.append(start..<found.location)
            start = found.location + found.length
        }
        return result
    }

    private func lineRanges(in text: String, within block: Range<Int>) -> [Range<Int>] {
        guard !block.isEmpty else { return [block] }

        let nsText = text as NSString
        var result: [Range<Int>] = []
        var start = block.lowerBound

        while start < block.upperBound {
            let found = nsText.range(
                of: "\n",
                options: [],
                range: NSRange(location: start, length: block.upperBound - start)
            )
            guard found.location != NSNotFound else {
                result.append(start..<block.upperBound)
                return result
            }
            result.append(start..<found.location)
            start = found.location + found.length
        }
        return result.isEmpty ? [block] : result
    }

    /// Range UTF-16 degli spazi iniziali e finali, equivalenti a
    /// `trimmingCharacters(in: .whitespacesAndNewlines)`.
    private func whitespaceEdgeRanges(in text: String) -> [Range<Int>] {
        let length = text.utf16.count
        guard length > 0 else { return [] }

        guard let first = text.firstIndex(where: { !$0.isWhitespace }),
              let last = text.lastIndex(where: { !$0.isWhitespace }) else {
            return [0..<length]
        }

        let leading = text[..<first].utf16.count
        let trailing = text[text.index(after: last)...].utf16.count

        var ranges: [Range<Int>] = []
        if leading > 0 {
            ranges.append(0..<leading)
        }
        if trailing > 0 {
            ranges.append((length - trailing)..<length)
        }
        return ranges
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

private extension Range where Bound == Int {
    var nsRange: NSRange {
        NSRange(location: lowerBound, length: upperBound - lowerBound)
    }
}
