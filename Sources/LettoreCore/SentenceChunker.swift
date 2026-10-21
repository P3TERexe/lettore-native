import Foundation
import NaturalLanguage

/// Motore di segmentazione intelligente del testo per la sintesi vocale.
/// Sostituisce pySBD utilizzando NaturalLanguage.framework combinato con
/// euristiche di disambiguazione per la lingua italiana.
///
/// Il chunker lavora sempre su offset UTF-16. L'API `chunk(text:)` resta quella
/// storica e produce chunk senza range sorgente; le API con `sourceRange` o
/// `FilteredText` producono chunk mappati sul testo originale.
public struct SentenceChunker: Sendable {
    
    /// Abbreviazioni frequenti nella lingua italiana che non devono spezzare la frase.
    private static let italianAbbreviations: Set<String> = [
        "dott.", "dott.ssa", "prof.", "prof.ssa", "avv.", "ing.", "sig.", "sig.ra",
        "art.", "cap.", "vol.", "pag.", "pagg.", "ecc.", "es.", "n.", "nr.",
        "all.", "v.", "cfr.", "s.p.a.", "s.r.l.", "all."
    ]
    
    public init() {}
    
    /// Segmenta un testo in una sequenza ordinata di ReadingChunk.
    ///
    /// I chunk prodotti non hanno range sorgente: è il percorso del testo
    /// manuale, dove non esiste un documento di origine mappabile.
    ///
    /// - Parameters:
    ///   - text: Il testo in ingresso da segmentare.
    ///   - maxChunkLength: Lunghezza massima consigliata per singola frase (default 240 caratteri).
    /// - Returns: Array di ReadingChunk pronti per la sintesi.
    public func chunk(text: String, maxChunkLength: Int = 240) -> [ReadingChunk] {
        chunk(
            text: text,
            sourceRange: nil,
            sourceDocumentID: nil,
            maxChunkLength: maxChunkLength
        )
    }

    /// Segmenta un testo che è una porzione contigua del documento sorgente.
    ///
    /// `sourceRange` è la posizione UTF-16 di `text` nel documento originale.
    /// Per testo filtrato (non contiguo, perché il filtro rimuove caratteri)
    /// usare `chunk(filteredText:range:sourceDocumentID:maxChunkLength:)`.
    ///
    /// - Parameters:
    ///   - text: Porzione contigua del documento.
    ///   - sourceRange: Posizione UTF-16 di `text` nella sorgente; `nil` per
    ///     lasciare i chunk senza mappa.
    ///   - sourceDocumentID: Identità del documento sorgente.
    ///   - maxChunkLength: Lunghezza massima consigliata per singola frase.
    public func chunk(
        text: String,
        sourceRange: SourceTextRange?,
        sourceDocumentID: UUID? = nil,
        maxChunkLength: Int = 240
    ) -> [ReadingChunk] {
        let spans = makeChunks(in: text, maxChunkLength: maxChunkLength)

        return spans.enumerated().map { index, span in
            let chunkSourceRange: SourceTextRange?
            if let sourceRange,
               sourceRange.location >= 0,
               span.relativeRange.location >= 0,
               span.relativeRange.end <= sourceRange.length {
                chunkSourceRange = SourceTextRange(
                    location: sourceRange.location + span.relativeRange.location,
                    length: span.relativeRange.length
                )
            } else {
                chunkSourceRange = nil
            }

            return ReadingChunk(
                index: index,
                text: span.text,
                rawText: span.text,
                sourceDocumentID: sourceDocumentID,
                sourceRange: chunkSourceRange
            )
        }
    }

    /// Segmenta il testo filtrato mappando ogni frase sulla sorgente originale.
    ///
    /// La mappa viene applicata ai range relativi prodotti dalla tokenizzazione,
    /// non al testo: le sostituzioni del normalizzatore (valute, percentuali,
    /// URL) non possono spostare gli offset.
    ///
    /// - Parameters:
    ///   - filteredText: Testo prodotto da `DocumentNoiseFilter.filterWithMapping`.
    ///   - range: Intervallo UTF-16 del testo filtrato da segmentare; `nil` per
    ///     l'intero testo. Serve per prefisso e remainder.
    ///   - sourceDocumentID: Identità del documento sorgente.
    ///   - maxChunkLength: Lunghezza massima consigliata per singola frase.
    public func chunk(
        filteredText: FilteredText,
        range: SourceTextRange? = nil,
        sourceDocumentID: UUID? = nil,
        maxChunkLength: Int = 240
    ) -> [ReadingChunk] {
        let fullLength = filteredText.utf16Length
        let slice = range ?? SourceTextRange(location: 0, length: fullLength)

        guard slice.location >= 0,
              slice.length >= 0,
              slice.location <= fullLength else {
            return []
        }

        let end = min(slice.end, fullLength)
        guard slice.location < end else { return [] }

        let nsText = filteredText.text as NSString
        let sliceText = nsText.substring(with: NSRange(location: slice.location, length: end - slice.location))
        let spans = makeChunks(in: sliceText, maxChunkLength: maxChunkLength)

        return spans.enumerated().map { index, span in
            let filteredRange = SourceTextRange(
                location: slice.location + span.relativeRange.location,
                length: span.relativeRange.length
            )
            let chunkSourceRange = filteredText.sourceRange(forRelativeRange: filteredRange)

            return ReadingChunk(
                index: index,
                text: span.text,
                rawText: span.text,
                sourceDocumentID: sourceDocumentID,
                sourceRange: chunkSourceRange
            )
        }
    }
    
    // MARK: - Private Helpers

    private struct ChunkSpan {
        let text: String
        /// Range UTF-16 relativo alla stringa passata al chunker.
        let relativeRange: SourceTextRange
    }

    private func makeChunks(in text: String, maxChunkLength: Int) -> [ChunkSpan] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        var result: [ChunkSpan] = []
        for sentence in sentenceSpans(in: text) {
            let sentenceText = String(text[sentence])
            guard !sentenceText.isEmpty else { continue }

            if sentenceText.count > maxChunkLength {
                for subSentence in splitLongSentence(sentence, in: text, maxLen: maxChunkLength) {
                    appendChunk(subSentence, in: text, to: &result)
                }
            } else {
                appendChunk(sentence, in: text, to: &result)
            }
        }
        return result
    }

    private func appendChunk(_ range: Range<String.Index>, in text: String, to result: inout [ChunkSpan]) {
        let trimmed = trimmedSpan(range, in: text)
        guard !trimmed.isEmpty else { return }

        let nsRange = NSRange(trimmed, in: text)
        result.append(ChunkSpan(
            text: String(text[trimmed]),
            relativeRange: SourceTextRange(nsRange)
        ))
    }

    /// Tokenizza in frasi e unisce i falsi confini creati dalle abbreviazioni.
    /// I range restano quelli della stringa originale, quindi non perdono
    /// offset quando una frase viene accorpata alla precedente.
    private func sentenceSpans(in text: String) -> [Range<String.Index>] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var tokens: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            tokens.append(range)
            return true
        }

        if tokens.isEmpty {
            tokens = [text.startIndex..<text.endIndex]
        }

        var sentences: [Range<String.Index>] = []
        for token in tokens {
            let trimmed = trimmedSpan(token, in: text)
            guard !trimmed.isEmpty else { continue }

            if let last = sentences.last, endsWithAbbreviation(text[last]) {
                sentences[sentences.count - 1] = last.lowerBound..<trimmed.upperBound
            } else {
                sentences.append(trimmed)
            }
        }
        return sentences
    }

    private func endsWithAbbreviation(_ text: Substring) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return false }
        return Self.italianAbbreviations.contains { trimmed.hasSuffix($0) }
    }
    
    private func splitLongSentence(
        _ sentence: Range<String.Index>,
        in text: String,
        maxLen: Int
    ) -> [Range<String.Index>] {
        let clauseDelimiters = ["; ", ": ", " — ", " - ", ", "]

        for delimiter in clauseDelimiters {
            var segments: [Range<String.Index>] = []
            var cursor = sentence.lowerBound

            while cursor < sentence.upperBound,
                  let found = text.range(of: delimiter, range: cursor..<sentence.upperBound) {
                let segment = trimmedSpan(cursor..<found.upperBound, in: text)
                if !segment.isEmpty {
                    segments.append(segment)
                }
                cursor = found.upperBound
            }

            if cursor < sentence.upperBound {
                let tail = trimmedSpan(cursor..<sentence.upperBound, in: text)
                if !tail.isEmpty {
                    segments.append(tail)
                }
            }

            guard segments.count > 1 else { continue }

            let packed = pack(segments, in: text, maxLen: maxLen)
            if packed.count > 1 {
                return packed
            }
        }

        return [sentence]
    }

    private func pack(
        _ segments: [Range<String.Index>],
        in text: String,
        maxLen: Int
    ) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var current: Range<String.Index>?

        for segment in segments {
            guard let existing = current else {
                current = segment
                continue
            }

            let candidate = existing.lowerBound..<segment.upperBound
            if text[candidate].count <= maxLen {
                current = candidate
            } else {
                result.append(existing)
                current = segment
            }
        }

        if let current {
            result.append(current)
        }
        return result
    }

    private func trimmedSpan(_ range: Range<String.Index>, in text: String) -> Range<String.Index> {
        var lower = range.lowerBound
        var upper = range.upperBound

        while lower < upper, text[lower].isWhitespace {
            lower = text.index(after: lower)
        }
        while upper > lower {
            let previous = text.index(before: upper)
            guard text[previous].isWhitespace else { break }
            upper = previous
        }
        return lower..<upper
    }
}
