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

    public enum CaptureOutcome: Sendable {
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
    /// Scarta una selezione preparata mentre ne parte un'altra.
    private var captureGeneration = 0

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
        fallbackToQueue(reason: Self.missingSourceApplicationNotice)
    }

    /// Unica regola di ripiego: durante il playback la coda sta già suonando,
    /// quindi non si riavvia; altrimenti, se esiste un chunk, si riprende.
    /// In tutti i casi l'avviso arriva all'utente perché i chiamanti leggono
    /// `continuationNotice`, non il motivo dell'esito.
    private func fallbackToQueue(reason: String) -> CaptureOutcome {
        guard appState.playbackState != .playing, appState.currentChunk != nil else {
            appState.continuationNotice = reason
            return .unavailable(reason: reason)
        }

        appState.continuationNotice = nil
        return .fellBackToQueue
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
        // non produce testo: si conserva invece di sostituirlo con un generico.
        let reason = appState.continuationNotice ?? "Nessun testo leggibile nell'app in primo piano."
        return fallbackToQueue(reason: reason)
    }

    private func captureSelection(from applicationPID: pid_t?) async -> CaptureOutcome {
        // Il token si assegna all'ingresso, non al ritorno dalla cattura:
        // altrimenti una richiesta vecchia ma più lenta diventerebbe la più
        // recente e sovrascriverebbe quella nuova.
        captureGeneration &+= 1
        let generation = captureGeneration

        guard let selection = await selectedText.captureSelectedText(from: applicationPID),
              !selection.trimmedText.isEmpty else {
            return fallbackToQueue(reason: "Nessuna selezione leggibile.")
        }

        appState.continuationNotice = nil
        appState.capturedDocumentText = ""

        let preparer = textPreparer
        let text = selection.trimmedText
        let sourceRange = selection.trimmedSourceRange
        let sourceDocumentID = selection.sourceDocumentID
        let reading = await Task.detached(priority: .userInitiated) {
            preparer.prepareInitial(
                text: text,
                sourceRange: sourceRange,
                sourceDocumentID: sourceDocumentID,
                mode: .off
            )
        }.value

        // Una seconda cattura può essere partita durante la preparazione:
        // la più vecchia non deve sostituire la coda di quella più recente.
        guard generation == captureGeneration else {
            return .unavailable(reason: "Cattura superata da una richiesta più recente.")
        }

        appState.setQueue(reading.chunks)
        return .captured(selection)
    }
}
