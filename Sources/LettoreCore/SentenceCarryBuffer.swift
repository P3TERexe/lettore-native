import Foundation
import NaturalLanguage

/// Accumula la coda incompleta di una pagina e la unisce alla pagina successiva,
/// così una frase non viene mai spezzata artificialmente al confine di pagina.
public struct SentenceCarryBuffer: Sendable {

    private var carry: String = ""
    private let maxCarryLength: Int

    public init(maxCarryLength: Int = 4_000) {
        self.maxCarryLength = maxCarryLength
    }

    public var pendingText: String { carry }

    /// Aggiunge un frammento e restituisce la parte che può essere inviata alla
    /// segmentazione. La coda incompleta resta nel buffer.
    public mutating func append(_ text: String, isFinal: Bool) -> String {
        let combined = carry + text
        carry = ""

        guard !combined.isEmpty else { return "" }
        if isFinal { return combined }

        if let split = Self.lastCompleteSentenceEnd(in: combined) {
            let prefix = String(combined[..<split])
            carry = String(combined[split...])
            return prefix
        }

        // Nessun confine di frase: se il frammento è già molto lungo, non
        // possiamo attenderne uno all'infinito (es. testo senza punteggiatura).
        if combined.count > maxCarryLength {
            return combined
        }

        carry = combined
        return ""
    }

    /// Restituisce la coda residua, tipicamente alla fine del documento.
    public mutating func flush() -> String {
        defer { carry = "" }
        return carry
    }

    // MARK: - Confini di frase

    /// Indice dopo l'ultima frase completa presente nel testo, oppure `nil`.
    public static func lastCompleteSentenceEnd(in text: String) -> String.Index? {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var lastCompleteEnd: String.Index?
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if endsWithSentenceTerminator(text[range]) {
                lastCompleteEnd = range.upperBound
            }
            return true
        }
        return lastCompleteEnd
    }

    /// Punto di taglio per l'ascolto immediato del testo iniziale.
    ///
    /// Preferisce l'ultima frase completa prima di `targetLength`. Se non ne
    /// esiste una, accetta la prima frase completa che termina entro
    /// `targetLength + 4.000` caratteri, così il primo blocco audio non si
    /// ferma a metà frase. Solo se non esiste alcun confine utile ripiega
    /// sull'ultimo spazio e infine sul limite richiesto.
    public static func splitPoint(in text: String, targetLength: Int) -> String.Index {
        guard targetLength > 0, text.count > targetLength else {
            return text.endIndex
        }

        let target = text.index(text.startIndex, offsetBy: targetLength)
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var lastCompleteEnd: String.Index?
        var firstCompleteEndAfterTarget: String.Index?
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let endsSentence = endsWithSentenceTerminator(text[range])

            if range.upperBound <= target {
                if endsSentence {
                    lastCompleteEnd = range.upperBound
                }
                return true
            }

            // La prima frase che termina dopo il target viene tenuta intera,
            // a meno che non sia troppo lontana dal limite di latenza. Un
            // token senza terminatore (es. coda incompleta) non è un confine:
            // continua a cercare.
            if endsSentence {
                firstCompleteEndAfterTarget = range.upperBound
                return false
            }
            return true
        }

        if let lastCompleteEnd {
            return lastCompleteEnd
        }

        if let firstCompleteEndAfterTarget,
           text.distance(from: text.startIndex, to: firstCompleteEndAfterTarget)
               <= targetLength + 4_000 {
            return firstCompleteEndAfterTarget
        }

        if let whitespace = text[..<target].lastIndex(where: \.isWhitespace),
           whitespace > text.startIndex {
            return whitespace
        }

        return target
    }

    private static let sentenceTerminators: Set<Character> = [
        ".", "!", "?", "…", "。", "！", "？"
    ]

    private static let closingMarks: Set<Character> = [
        ")", "]", "»", "\"", "”", "’", "'"
    ]

    private static func endsWithSentenceTerminator(_ text: Substring) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return false }

        if sentenceTerminators.contains(last) {
            return true
        }

        if closingMarks.contains(last),
           let before = trimmed.dropLast().last,
           sentenceTerminators.contains(before) {
            return true
        }

        return false
    }
}
