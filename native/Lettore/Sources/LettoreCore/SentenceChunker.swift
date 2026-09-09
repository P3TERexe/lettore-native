import Foundation
import NaturalLanguage

/// Motore di segmentazione intelligente del testo per la sintesi vocale.
/// Sostituisce pySBD utilizzando NaturalLanguage.framework combinato con
/// euristiche di disambiguazione per la lingua italiana.
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
    /// - Parameters:
    ///   - text: Il testo in ingresso da segmentare.
    ///   - maxChunkLength: Lunghezza massima consigliata per singola frase (default 240 caratteri).
    /// - Returns: Array di ReadingChunk pronti per la sintesi.
    public func chunk(text: String, maxChunkLength: Int = 240) -> [ReadingChunk] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        let rawSentences = extractSentencesWithNaturalLanguage(text: trimmed)
        let mergedSentences = mergeAbbreviationSplits(rawSentences)
        
        var chunks: [ReadingChunk] = []
        var index = 0
        
        for sentence in mergedSentences {
            let sentenceClean = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentenceClean.isEmpty else { continue }
            
            if sentenceClean.count > maxChunkLength {
                let subChunks = splitLongSentence(sentenceClean, maxLen: maxChunkLength)
                for sub in subChunks {
                    chunks.append(ReadingChunk(index: index, text: sub))
                    index += 1
                }
            } else {
                chunks.append(ReadingChunk(index: index, text: sentenceClean))
                index += 1
            }
        }
        
        return chunks
    }
    
    // MARK: - Private Helpers
    
    private func extractSentencesWithNaturalLanguage(text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            let sentence = String(text[tokenRange])
            sentences.append(sentence)
            return true
        }
        
        if sentences.isEmpty {
            sentences.append(text)
        }
        
        return sentences
    }
    
    private func mergeAbbreviationSplits(_ sentences: [String]) -> [String] {
        guard sentences.count > 1 else { return sentences }
        
        var result: [String] = []
        var accumulator = ""
        
        for sentence in sentences {
            if accumulator.isEmpty {
                accumulator = sentence
                continue
            }
            
            let trimmedPrev = accumulator.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let endsWithAbbr = Self.italianAbbreviations.contains { abbr in
                trimmedPrev.hasSuffix(abbr)
            }
            
            if endsWithAbbr {
                let cleanSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanAccumulator = accumulator.trimmingCharacters(in: .whitespacesAndNewlines)
                accumulator = cleanAccumulator + " " + cleanSentence
            } else {
                result.append(accumulator)
                accumulator = sentence
            }
        }
        
        if !accumulator.isEmpty {
            result.append(accumulator)
        }
        
        return result
    }
    
    private func splitLongSentence(_ sentence: String, maxLen: Int) -> [String] {
        let clauseDelimiters = ["; ", ": ", " — ", " - ", ", "]
        
        for delimiter in clauseDelimiters {
            let parts = sentence.components(separatedBy: delimiter)
            if parts.count > 1 {
                var result: [String] = []
                var current = ""
                
                for (idx, part) in parts.enumerated() {
                    let suffix = (idx < parts.count - 1) ? delimiter.trimmingCharacters(in: .whitespaces) : ""
                    let piece = part + suffix
                    
                    if current.isEmpty {
                        current = piece
                    } else if (current + " " + piece).count <= maxLen {
                        current += " " + piece
                    } else {
                        result.append(current.trimmingCharacters(in: .whitespaces))
                        current = piece
                    }
                }
                
                if !current.isEmpty {
                    result.append(current.trimmingCharacters(in: .whitespaces))
                }
                
                if result.count > 1 {
                    return result
                }
            }
        }
        
        return [sentence]
    }
}
