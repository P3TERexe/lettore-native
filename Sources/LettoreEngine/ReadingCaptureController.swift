import Foundation
import LettoreCore

/// Policy unica di cattura per Play della UI e scorciatoia globale.
///
/// Decide se leggere una selezione o avviare la lettura continua, valida l'app
/// di origine, prepara i chunk e ripiega sulla coda già pronta. Non avvia il
/// playback né apre la sessione di highlight: restituisce l'esito e lascia il
/// wiring all'app.
@MainActor
public final class ReadingCaptureController {

    public enum CaptureOutcome {
        /// Selezione valida: la coda è già stata sostituita con i nuovi chunk.
        case captured(CapturedSelection)
        /// La lettura continua ha catturato testo e gestisce lei coda e play.
        case continuous(String)
        /// Nessuna cattura utile: il chiamante può riprendere la coda esistente.
        case fellBackToQueue
        /// Cattura non disponibile; `reason` è il messaggio per l'utente.
        case unavailable(reason: String)
    }

    public static let missingSourceApplicationNotice =
        "Nessuna app di origine disponibile: porta in primo piano l'app con il testo, poi torna qui e riprova."

    public typealias ContinuousCapture = @MainActor (pid_t?) async -> String?

    private let appState: AppState
    private let selectedText: any SelectedTextCapturing
    private let sourceApplications: any SourceApplicationProviding
    private let continuousCapture: ContinuousCapture
    private let textPreparer = ReadingTextPreparer()

    public init(
        appState: AppState,
        selectedText: any SelectedTextCapturing,
        sourceApplications: any SourceApplicationProviding,
        continuousCapture: @escaping ContinuousCapture
    ) {
        self.appState = appState
        self.selectedText = selectedText
        self.sourceApplications = sourceApplications
        self.continuousCapture = continuousCapture
    }

    /// Cattura richiesta dalla UI di Lettore (Play della pillola o pulsante
    /// dello Studio). La finestra di Lettore è in primo piano: la sorgente è
    /// l'ultima app esterna attivata, non il focused element interno.
    public func playFromUI(isContinuousEnabled: Bool) async -> CaptureOutcome {
        guard let sourcePID = sourceApplications.validatedExternalApplicationPID(
            appState.lastExternalApplicationPID
        ) else {
            return missingSourceApplicationOutcome()
        }

        return await capture(from: sourcePID, isContinuousEnabled: isContinuousEnabled)
    }

    /// Cattura richiesta dalla scorciatoia globale. Se Lettore è in primo piano
    /// vale la stessa policy della UI; altrimenti legge l'app davvero attiva,
    /// lasciando al servizio AX il fallback clipboard.
    public func captureFromFrontmost(isContinuousEnabled: Bool) async -> CaptureOutcome {
        if sourceApplications.frontmostApplicationPID == sourceApplications.currentProcessIdentifier {
            return await playFromUI(isContinuousEnabled: isContinuousEnabled)
        }

        return await capture(from: nil, isContinuousEnabled: isContinuousEnabled)
    }

    // MARK: - Policy

    private func missingSourceApplicationOutcome() -> CaptureOutcome {
        guard appState.playbackState != .playing else {
            return .unavailable(reason: Self.missingSourceApplicationNotice)
        }

        if appState.currentChunk != nil {
            appState.continuationNotice = nil
            return .fellBackToQueue
        }

        appState.continuationNotice = Self.missingSourceApplicationNotice
        return .unavailable(reason: Self.missingSourceApplicationNotice)
    }

    private func capture(from applicationPID: pid_t?, isContinuousEnabled: Bool) async -> CaptureOutcome {
        guard !isContinuousEnabled else {
            return await captureContinuously(from: applicationPID)
        }

        return await captureSelection(from: applicationPID)
    }

    private func captureContinuously(from applicationPID: pid_t?) async -> CaptureOutcome {
        if let captured = await continuousCapture(applicationPID) {
            return .continuous(captured)
        }

        // `ContinuousReadingController` scrive già l'avviso quando la cattura
        // non produce testo. Qui si aggiunge solo il ritorno alla coda.
        let reason = appState.continuationNotice ?? "Nessun testo leggibile nell'app in primo piano."
        guard appState.playbackState != .playing, appState.currentChunk != nil else {
            return .unavailable(reason: reason)
        }

        appState.continuationNotice = nil
        return .fellBackToQueue
    }

    private func captureSelection(from applicationPID: pid_t?) async -> CaptureOutcome {
        guard let selection = await selectedText.captureSelectedText(from: applicationPID),
              !selection.trimmedText.isEmpty else {
            guard appState.playbackState != .playing, appState.currentChunk != nil else {
                return .unavailable(reason: "Nessuna selezione leggibile.")
            }
            return .fellBackToQueue
        }

        appState.continuationNotice = nil
        appState.capturedDocumentText = ""

        let sourceRange = selection.trimmedSourceRange
        let reading = textPreparer.prepareInitial(
            text: selection.trimmedText,
            sourceRange: sourceRange,
            sourceDocumentID: selection.sourceDocumentID,
            mode: .off
        )
        appState.setQueue(reading.chunks)

        return .captured(selection)
    }
}
