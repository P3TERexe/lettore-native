import Foundation

/// Cattura della selezione corrente da un'applicazione esterna.
///
/// L'implementazione reale vive in `LettoreSystem`; `ReadingCaptureController`
/// dipende solo da questo contratto.
public protocol SelectedTextCapturing: Sendable {
    /// Cattura la selezione nell'app indicata, oppure in quella in primo piano
    /// quando il PID è `nil`.
    func captureSelectedText(from applicationPID: pid_t?) async -> CapturedSelection?
}

/// Informazioni sul processo corrente e sull'app di origine di una cattura.
///
/// Separa la policy di cattura dalle API AppKit: `ReadingCaptureController`
/// resta in `LettoreEngine` senza importare `NSWorkspace`.
@MainActor
public protocol SourceApplicationProviding {
    /// PID del processo che ospita Lettore.
    var currentProcessIdentifier: pid_t { get }

    /// PID dell'app in primo piano, se il sistema lo espone.
    var frontmostApplicationPID: pid_t? { get }

    /// Restituisce il PID se appartiene a un'app esterna ancora in esecuzione,
    /// altrimenti `nil`. Il processo corrente non è mai una sorgente valida.
    func validatedExternalApplicationPID(_ pid: pid_t?) -> pid_t?
}
