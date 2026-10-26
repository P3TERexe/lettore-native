import Foundation

/// Risultato della preparazione di un testo per la lettura.
///
/// Il contenuto del remainder è volutamente opaco: solo `ReadingTextPreparer`
/// sa come ricostruirlo, così i chiamanti non possono duplicare l'ordine
/// filtro → split → chunk → normalizzazione.
public struct PreparedReading: Sendable {
    public let displayText: String
    public let chunks: [ReadingChunk]
    public let hasRemainder: Bool

    let remainder: Remainder?

    init(
        displayText: String,
        chunks: [ReadingChunk],
        remainder: Remainder? = nil
    ) {
        self.displayText = displayText
        self.chunks = chunks
        self.hasRemainder = remainder != nil
        self.remainder = remainder
    }

    struct Remainder: Sendable {
        let filteredText: FilteredText
        let range: SourceTextRange
        let sourceDocumentID: UUID?
        let mappingBase: Int?
    }
}

/// Unico punto in cui il testo catturato diventa chunk pronunciabili.
///
/// L'ordine delle operazioni è parte dell'interfaccia: il filtro rimuove il
/// rumore conservando la mappa, lo split sceglie un confine di frase, il
/// chunker produce i range e solo alla fine il normalizzatore riscrive il testo
/// pronunciato. Normalizzare prima del chunking cambierebbe i confini di frase
/// e renderebbe inutilizzabile la mappa verso l'app di origine.
public struct ReadingTextPreparer: Sendable {

    private let chunker: SentenceChunker
    private let filter: DocumentNoiseFilter
    private let normalizer: TextNormalizer

    public init(
        chunker: SentenceChunker = SentenceChunker(),
        filter: DocumentNoiseFilter = DocumentNoiseFilter(),
        normalizer: TextNormalizer = TextNormalizer()
    ) {
        self.chunker = chunker
        self.filter = filter
        self.normalizer = normalizer
    }

    /// Prepara una cattura iniziale o un testo manuale.
    ///
    /// - Parameters:
    ///   - text: Testo grezzo catturato o incollato.
    ///   - sourceRange: Posizione UTF-16 assoluta di `text` nel documento,
    ///     quando esiste. Abilita la mappa sorgente dei chunk.
    ///   - sourceDocumentID: Identità del documento di origine.
    ///   - mode: Filtro rumore. Per il testo manuale e le selezioni è `.off`.
    ///   - maxImmediateLength: Se valorizzato, la riproduzione parte dal
    ///     prefisso che termina su un confine di frase entro questa soglia e il
    ///     resto viene preparato con `prepareRemainder(of:)`.
    public func prepareInitial(
        text: String,
        sourceRange: SourceTextRange? = nil,
        sourceDocumentID: UUID? = nil,
        mode: NoiseFilterMode = .off,
        maxImmediateLength: Int? = nil
    ) -> PreparedReading {
        let filtered = filter.filterWithMapping(text, mode: mode)
        // Un range senza identità di documento non è una mappa utilizzabile:
        // produrrebbe chunk con `sourceRange` ma senza documento, che nessuna
        // sessione di evidenziazione può consumare.
        let mappingBase = sourceDocumentID == nil ? nil : sourceRange?.location
        let limit = maxImmediateLength.flatMap { $0 > 0 ? $0 : nil }

        guard let limit, filtered.text.count > limit else {
            let chunks = makeChunks(
                in: filtered,
                range: nil,
                sourceDocumentID: sourceDocumentID,
                mappingBase: mappingBase
            )
            return PreparedReading(displayText: filtered.text, chunks: chunks)
        }

        let split = SentenceCarryBuffer.splitPoint(in: filtered.text, targetLength: limit)
        let splitOffset = filtered.text[..<split].utf16.count
        let prefixRange = SourceTextRange(location: 0, length: splitOffset)
        let remainderRange = SourceTextRange(
            location: splitOffset,
            length: max(0, filtered.utf16Length - splitOffset)
        )

        let chunks = makeChunks(
            in: filtered,
            range: prefixRange,
            sourceDocumentID: sourceDocumentID,
            mappingBase: mappingBase
        )
        let remainder = remainderRange.isEmpty
            ? nil
            : PreparedReading.Remainder(
                filteredText: filtered,
                range: remainderRange,
                sourceDocumentID: sourceDocumentID,
                mappingBase: mappingBase
            )

        return PreparedReading(
            displayText: filtered.text,
            chunks: chunks,
            remainder: remainder
        )
    }

    /// Prepara il resto del documento dopo uno split iniziale.
    ///
    /// Restituisce una lista vuota se la lettura non ha un remainder. È
    /// abbastanza oneroso da poter essere eseguito fuori dal MainActor.
    public func prepareRemainder(of reading: PreparedReading) -> [ReadingChunk] {
        guard let remainder = reading.remainder else { return [] }
        return makeChunks(
            in: remainder.filteredText,
            range: remainder.range,
            sourceDocumentID: remainder.sourceDocumentID,
            mappingBase: remainder.mappingBase
        )
    }

    /// Prepara una pagina successiva di un documento virtualizzato.
    ///
    /// Il paging non ha una mappa perché la pagina non è un intervallo
    /// contiguo del documento originale: i chunk restano senza range.
    public func preparePage(text: String, mode: NoiseFilterMode = .off) -> PreparedReading {
        let prepared = Self.cleanDocumentText(text, filter: filter, mode: mode)
        let normalized = normalizer.normalize(chunker.chunk(text: prepared))
        let chunks = Self.boundNormalizedChunks(normalized)
        return PreparedReading(displayText: prepared, chunks: chunks)
    }

    // MARK: - Implementazione

    private func makeChunks(
        in filtered: FilteredText,
        range: SourceTextRange?,
        sourceDocumentID: UUID?,
        mappingBase: Int?
    ) -> [ReadingChunk] {
        let produced: [ReadingChunk]

        if let mappingBase {
            produced = chunker.chunk(
                filteredText: filtered,
                range: range,
                sourceDocumentID: sourceDocumentID
            ).map { $0.offsettingSourceRange(by: mappingBase) }
        } else {
            let slice: String
            if let range {
                slice = (filtered.text as NSString).substring(with: range.nsRange)
            } else {
                slice = filtered.text
            }
            produced = chunker.chunk(
                text: slice,
                sourceRange: nil,
                sourceDocumentID: nil
            )
        }

        return Self.boundNormalizedChunks(normalizer.normalize(produced))
    }

    /// La normalizzazione può allungare il testo (`Es.` → `ad esempio`, URL,
    /// valute): il limite dei 240 caratteri va riapplicato dopo di essa, non
    /// solo sul testo grezzo. Le parti condividono la mappa della frase
    /// originale, quindi l'evidenziazione resta corretta.
    private static func boundNormalizedChunks(_ chunks: [ReadingChunk]) -> [ReadingChunk] {
        let limit = SentenceChunker.defaultMaxChunkLength
        var result: [ReadingChunk] = []
        result.reserveCapacity(chunks.count)

        for chunk in chunks {
            let parts = splitForSpeech(chunk.text, maxLength: limit)
            if parts.count <= 1 {
                result.append(chunk.reindexed(result.count))
                continue
            }

            for part in parts {
                result.append(ReadingChunk(
                    index: result.count,
                    text: part,
                    rawText: chunk.rawText,
                    sourceDocumentID: chunk.sourceDocumentID,
                    sourceRange: chunk.sourceRange
                ))
            }
        }
        return result
    }

    private static func splitForSpeech(_ text: String, maxLength: Int) -> [String] {
        guard text.count > maxLength else { return [text] }
        let limit = max(1, maxLength)
        var parts: [String] = []
        var start = text.startIndex

        while start < text.endIndex {
            if text[start...].count <= limit {
                let tail = text[start...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty {
                    parts.append(tail)
                }
                break
            }

            var cut = text.index(start, offsetBy: limit, limitedBy: text.endIndex)
                ?? text.endIndex

            // Spezza sullo spazio più vicino al limite, se esiste.
            var probe = cut
            while probe > start {
                let previous = text.index(before: probe)
                if text[previous].isWhitespace {
                    cut = previous
                    break
                }
                probe = previous
            }

            let piece = text[start..<cut].trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty {
                parts.append(piece)
            }

            start = cut
            while start < text.endIndex, text[start].isWhitespace {
                start = text.index(after: start)
            }
        }

        return parts
    }

    private static func cleanDocumentText(
        _ text: String,
        filter: DocumentNoiseFilter,
        mode: NoiseFilterMode
    ) -> String {
        let normalizedNewlines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)

        let filtered = filter.filter(normalizedNewlines, mode: mode)
        let paragraphs = filtered
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return paragraphs.joined(separator: "\n\n")
    }
}
