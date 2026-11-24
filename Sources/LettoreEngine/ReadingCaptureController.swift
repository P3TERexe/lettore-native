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
    /// Ferma la sessione continua attiva o ancora in cattura. Serve a evitare
    /// che una selezione e una lettura continua scrivano la coda a gara.
    public typealias ContinuousSessionCancellation = @MainActor () -> Void

    private static let supersededNotice =
        "Richiesta superata da una cattura più recente."

    private let appState: AppState
    private let selectedText: any SelectedTextCapturing
    private let sourceApplications: any SourceApplicationProviding
    private let continuousCapture: ContinuousCapture
    private let cancelContinuousSession: ContinuousSessionCancellation
    private let textPreparer = ReadingTextPreparer()
    /// Identifica l'ultima richiesta di lettura: cattura o input manuale.
    /// Ogni percorso la incrementa all'ingresso e la verifica dopo ogni await,
    /// così una richiesta vecchia non può sostituire la coda di una nuova.
    private var requestGeneration: UInt64 = 0

    public init(
        appState: AppState,
        selectedText: any SelectedTextCapturing,
        sourceApplications: any SourceApplicationProviding,
        continuousCapture: @escaping ContinuousCapture,
        cancelContinuousSession: @escaping ContinuousSessionCancellation
    ) {
        self.appState = appState
        self.selectedText = selectedText
        self.sourceApplications = sourceApplications
        self.continuousCapture = continuousCapture
        self.cancelContinuousSession = cancelContinuousSession
    }

    /// Cattura richiesta dalla UI di Lettore (Play della pillola o pulsante
    /// dello Studio). La finestra di Lettore è in primo piano: la sorgente è
    /// l'ultima app esterna attivata, non il focused element interno.
    public func playFromUI(isContinuousEnabled: Bool) async -> CaptureOutcome {
        let generation = beginRequest()

        guard let sourcePID = sourceApplications.validatedExternalApplicationPID(
            appState.lastExternalApplicationPID
        ) else {
            return missingSourceApplicationOutcome(generation: generation)
        }

        return await capture(
            from: sourcePID,
            isContinuousEnabled: isContinuousEnabled,
            generation: generation
        )
    }

    /// Cattura richiesta dalla scorciatoia globale. Se Lettore è in primo piano
    /// vale la stessa policy della UI; altrimenti legge l'app davvero attiva,
    /// lasciando al servizio AX il fallback clipboard.
    public func captureFromFrontmost(isContinuousEnabled: Bool) async -> CaptureOutcome {
        if sourceApplications.frontmostApplicationPID == sourceApplications.currentProcessIdentifier {
            return await playFromUI(isContinuousEnabled: isContinuousEnabled)
        }

        let generation = beginRequest()
        return await capture(
            from: nil,
            isContinuousEnabled: isContinuousEnabled,
            generation: generation
        )
    }

    /// Apre una richiesta di lettura manuale (testo scritto o incollato nello
    /// Studio) e restituisce il token da verificare dopo la preparazione.
    /// La richiesta manuale supera e ferma anche un'eventuale sessione continua.
    public func beginManualReadingRequest() -> UInt64 {
        beginRequest()
    }

    /// `true` se la richiesta è ancora la più recente.
    public func isCurrentReadingRequest(_ generation: UInt64) -> Bool {
        generation == requestGeneration
    }

    // MARK: - Policy

    private func beginRequest() -> UInt64 {
        requestGeneration &+= 1
        // Ogni nuova richiesta ferma la lettura continua esistente o ancora
        // in cattura, anche quando poi fallisce prima di leggere il testo
        // (per esempio PID di origine mancante).
        cancelContinuousSession()
        return requestGeneration
    }

    private func missingSourceApplicationOutcome(generation: UInt64) -> CaptureOutcome {
        fallbackToQueue(
            reason: Self.missingSourceApplicationNotice,
            generation: generation
        )
    }

    /// Unica regola di ripiego: durante il playback la coda sta già suonando,
    /// quindi non si riavvia; altrimenti, se esiste un chunk, si riprende.
    /// L'avviso viene sempre conservato in `continuationNotice`, anche quando
    /// la coda riparte: l'utente deve sapere perché la cattura non è riuscita.
    private func fallbackToQueue(reason: String, generation: UInt64) -> CaptureOutcome {
        // Una richiesta superata non deve toccare avvisi, coda o playback
        // della richiesta più recente.
        guard isCurrentReadingRequest(generation) else {
            return .unavailable(reason: Self.supersededNotice)
        }

        appState.continuationNotice = reason

        guard appState.playbackState != .playing, appState.currentChunk != nil else {
            return .unavailable(reason: reason)
        }

        return .fellBackToQueue
    }

    private func capture(
        from applicationPID: pid_t?,
        isContinuousEnabled: Bool,
        generation: UInt64
    ) async -> CaptureOutcome {
        guard !isContinuousEnabled else {
            return await captureContinuously(
                from: applicationPID,
                generation: generation
            )
        }

        return await captureSelection(
            from: applicationPID,
            generation: generation
        )
    }

    private func captureContinuously(
        from applicationPID: pid_t?,
        generation: UInt64
    ) async -> CaptureOutcome {
        if let captured = await continuousCapture(applicationPID) {
            guard isCurrentReadingRequest(generation) else {
                // La sessione continua è già stata fermata dalla richiesta
                // più recente: non restituire un esito che farebbe partire
                // un secondo playback.
                return .unavailable(reason: Self.supersededNotice)
            }
            return .continuous(captured)
        }

        guard isCurrentReadingRequest(generation) else {
            return .unavailable(reason: Self.supersededNotice)
        }

        // `ContinuousReadingController` scrive già l'avviso quando la cattura
        // non produce testo: si conserva invece di sostituirlo con un generico.
        let reason = appState.continuationNotice ?? "Nessun testo leggibile nell'app in primo piano."
        return fallbackToQueue(reason: reason, generation: generation)
    }

    private func captureSelection(
        from applicationPID: pid_t?,
        generation: UInt64
    ) async -> CaptureOutcome {
        guard let selection = await selectedText.captureSelectedText(from: applicationPID),
              !selection.trimmedText.isEmpty else {
            return fallbackToQueue(
                reason: "Nessuna selezione leggibile: seleziona testo nell'app di origine e verifica l'Accessibilità di Lettore.",
                generation: generation
            )
        }

        // Una richiesta manuale o un'altra cattura può aver preso il controllo
        // mentre il servizio AX rispondeva: non serve preparare nulla.
        guard isCurrentReadingRequest(generation) else {
            return .unavailable(reason: Self.supersededNotice)
        }

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

        // Una seconda richiesta può essere partita durante la preparazione:
        // la più vecchia non deve sostituire la coda di quella più recente.
        guard isCurrentReadingRequest(generation) else {
            return .unavailable(reason: Self.supersededNotice)
        }

        appState.continuationNotice = nil
        appState.capturedDocumentText = ""
        appState.setQueue(reading.chunks)
        return .captured(selection)
    }
}
