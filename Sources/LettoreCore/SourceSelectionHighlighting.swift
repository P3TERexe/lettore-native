import Foundation

/// Esito della richiesta di evidenziazione nativa nell'app di origine.
public enum SourceHighlightOutcome: Equatable, Sendable {
    /// La selezione è stata scritta e verificata.
    case applied
    /// L'app di origine non è in primo piano: nessuna scrittura.
    case suspended
    /// La sessione non supporta la scrittura della selezione.
    case unsupported
    /// La scrittura o la verifica del range è fallita.
    case failed
}

/// Scrittura della selezione nativa nella sessione sorgente corrente.
///
/// Il protocollo vive in `LettoreCore` per disaccoppiare il chiamante dagli
/// `AXUIElement`: l'implementazione reale resta in `LettoreSystem`.
public protocol SourceSelectionHighlighting: Sendable {
    @discardableResult
    func highlightSourceRange(
        _ range: SourceTextRange,
        documentID: UUID
    ) async -> SourceHighlightOutcome

    /// Rilascia observer e stato della sessione senza deselezionare il testo.
    func endSourceHighlight(documentID: UUID) async
}

/// Notifica di cambio selezione prodotto dall'utente.
///
/// L'implementazione reale confronta il readback AX con l'ultimo range scritto
/// e applica un debounce. Il callback viene invocato fuori dal MainActor.
public protocol SourceSelectionChangeObserving: Sendable {
    /// Installa l'osservazione sulla sessione. Restituisce `false` se l'app non
    /// permette di osservare `AXSelectedTextChanged`.
    @discardableResult
    func observeSelectionChanges(
        documentID: UUID,
        onChange: @escaping @Sendable () -> Void
    ) async -> Bool

    func stopObservingSelectionChanges(documentID: UUID) async
}
