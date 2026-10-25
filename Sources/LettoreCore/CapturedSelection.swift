import Foundation

/// Risultato di un'operazione di cattura del testo da un'applicazione esterna.
public struct CapturedSelection: Sendable {
    public let text: String
    /// Sessione sorgente registrata per l'highlight, se la selezione è stata
    /// letta via AX. Resta `nil` quando si usa il fallback clipboard.
    public let sourceDocumentID: UUID?
    public let sourceRange: SourceTextRange?
    public let sourcePID: pid_t?

    public init(
        text: String,
        sourceDocumentID: UUID? = nil,
        sourceRange: SourceTextRange? = nil,
        sourcePID: pid_t? = nil
    ) {
        self.text = text
        self.sourceDocumentID = sourceDocumentID
        self.sourceRange = sourceRange
        self.sourcePID = sourcePID
    }
}

public extension CapturedSelection {
    /// Testo della selezione senza spazi di bordo, l'unico che il chiamante
    /// usa per la coda.
    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Range assoluto del `trimmedText` nell'app di origine. Avanza la base di
    /// quante unità UTF-16 sono state rimosse all'inizio; resta `nil` quando la
    /// cattura non ha una sessione AX mappabile (es. clipboard).
    var trimmedSourceRange: SourceTextRange? {
        sourceRange.map {
            SourceTextTrimming.trimmedRange(selection: $0, selectedText: text)
        }
    }
}
