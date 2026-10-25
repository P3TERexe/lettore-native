import Foundation

/// Operazioni pure sul ritaglio del testo selezionato.
///
/// Il trimming lavora su `Character`, ma la base assoluta AX è in UTF-16:
/// contare i caratteri rimossi senza convertirli produrrebbe offset sbagliati
/// su emoji e altri caratteri fuori dal BMP.
public enum SourceTextTrimming {

    /// Numero di unità UTF-16 rimosse all'inizio da
    /// `trimmingCharacters(in: .whitespacesAndNewlines)`.
    public static func leadingUTF16Count(of raw: String) -> Int {
        guard !raw.isEmpty else { return 0 }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (raw as NSString).length }
        let found = (raw as NSString).range(of: trimmed)
        return found.location == NSNotFound ? 0 : found.location
    }

    /// Range del testo ritagliato all'interno di una selezione AX.
    ///
    /// La lunghezza non supera mai quella della selezione originale: un range
    /// più lungo è peggio di nessun range.
    public static func trimmedRange(
        selection: SourceTextRange,
        selectedText: String
    ) -> SourceTextRange {
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SourceTextRange(location: selection.location, length: 0)
        }

        let leading = leadingUTF16Count(of: selectedText)
        let start = selection.location + leading
        let available = max(0, selection.length - leading)
        let length = min((trimmed as NSString).length, available)
        return SourceTextRange(location: start, length: length)
    }
}
