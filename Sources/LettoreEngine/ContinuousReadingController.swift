import Foundation
import Observation
import LettoreCore

/// Orchestra la modalità "Lettura continua" (DSA-11).
///
/// Responsabilità:
/// - avviare la cattura documentale;
/// - preparare e accodare subito la prima porzione di testo;
/// - chunckare il resto del documento catturato in background;
/// - chiedere le pagine successive quando la coda si avvicina alla fine;
/// - fermare il paging (ma non la coda già catturata) quando l'utente
///   disattiva la modalità o il caricamento automatico.
@MainActor
public final class ContinuousReadingController {

    public static let immediatePlaybackLength = 8_000

    public let appState: AppState
    public let coordinator: PlaybackCoordinator
    private let source: any ContinuousTextSource

    private let normalizer = TextNormalizer()
    private let chunker = SentenceChunker()
    private let noiseFilter = DocumentNoiseFilter()

    private var rawCarry = SentenceCarryBuffer()
    private var isSessionActive = false
    private var didReachEnd = false
    private var pagingEnabled = true
    private var remainderTask: Task<[ReadingChunk], Never>?
    private var sourceCleanupTask: Task<Void, Never>?

    public init(
        appState: AppState,
        coordinator: PlaybackCoordinator,
        source: any ContinuousTextSource
    ) {
        self.appState = appState
        self.coordinator = coordinator
        self.source = source
        self.pagingEnabled = appState.isContinuousReadingEnabled && appState.isAutoPageEnabled

        coordinator.onQueueLow = { [weak self] in
            guard let self else { return false }
            return await self.fetchNextPage()
        }

        coordinator.onSessionEnded = { [weak self] in
            self?.finishSession()
        }

        observePagingPreferences()
    }

    // MARK: - API pubblica

    /// Cattura il testo dall'app in primo piano e avvia la lettura continua.
    /// Restituisce il testo preparato da mostrare nello Studio, oppure `nil`
    /// se non c'era nulla di leggibile.
    @discardableResult
    public func captureAndPlay() async -> String? {
        if isSessionActive || appState.isContinuousSessionActive {
            stopSession()
        }

        // La chiusura della sessione AX precedente è asincrona: attendila
        // prima di aprirne una nuova, altrimenti potrebbe cancellarla.
        if let cleanup = sourceCleanupTask {
            await cleanup.value
            sourceCleanupTask = nil
        }

        isSessionActive = true
        didReachEnd = false
        pagingEnabled = appState.isContinuousReadingEnabled && appState.isAutoPageEnabled
        rawCarry = SentenceCarryBuffer()
        appState.continuationNotice = nil
        appState.isContinuousSessionActive = true
        appState.isContinuousDocumentPaged = false
        appState.capturedDocumentText = ""
        appState.isFetchingMoreText = false

        let start = await source.startContinuousCapture()
        guard isSessionActive else { return nil }

        if let notice = start.notice {
            appState.continuationNotice = notice
        }

        guard !start.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            finishSession()
            if appState.continuationNotice == nil {
                appState.continuationNotice = "Nessun testo leggibile nell'app in primo piano."
            }
            return nil
        }

        appState.isContinuousDocumentPaged = start.canPage && appState.isAutoPageEnabled

        let filter = noiseFilter
        let normalizer = self.normalizer
        let chunker = self.chunker
        let mode = appState.noiseFilterMode
        let targetLength = Self.immediatePlaybackLength

        let preparation = await Task.detached(priority: .userInitiated) {
            let prepared = Self.prepare(
                start.text,
                normalizer: normalizer,
                filter: filter,
                mode: mode
            )
            let split = SentenceCarryBuffer.splitPoint(
                in: prepared,
                targetLength: targetLength
            )
            let prefix = String(prepared[..<split])
            let remainder = String(prepared[split...])

            return InitialPreparation(
                displayText: prepared,
                chunks: chunker.chunk(text: prefix),
                remainder: remainder
            )
        }.value

        guard isSessionActive else { return nil }

        guard !preparation.chunks.isEmpty else {
            finishSession()
            appState.continuationNotice = "Il testo catturato non contiene frasi leggibili."
            return nil
        }

        appState.capturedDocumentText = preparation.displayText
        appState.setQueue(preparation.chunks)

        if !preparation.remainder.isEmpty {
            let remainder = preparation.remainder
            remainderTask = Task.detached(priority: .utility) {
                chunker.chunk(text: remainder)
            }
        }

        coordinator.playCurrentChunk()
        return preparation.displayText
    }

    /// Ferma esplicitamente la sessione continua e la riproduzione.
    public func stopSession() {
        guard isSessionActive || appState.isContinuousSessionActive else { return }
        coordinator.stop()
        finishSession()
    }

    /// Chiamata dal `PlaybackCoordinator` quando la coda sta per esaurirsi.
    /// Restituisce `true` se sono stati accodati nuovi chunk.
    public func fetchNextPage() async -> Bool {
        guard isSessionActive else { return false }

        appState.isFetchingMoreText = true
        defer { appState.isFetchingMoreText = false }

        // Il resto del documento già catturato ha precedenza sulle nuove
        // pagine: l'ordine di lettura deve restare quello del documento.
        if let task = remainderTask {
            let chunks = await task.value
            remainderTask = nil

            // Anche se il task di paging è stato cancellato da uno skip, il
            // resto già catturato va accodato: fa parte della coda corrente.
            guard isSessionActive else { return false }
            if !chunks.isEmpty {
                appState.appendChunks(chunks)
                return true
            }
        }

        guard pagingEnabled,
              appState.isContinuousReadingEnabled,
              appState.isAutoPageEnabled,
              !didReachEnd else {
            return false
        }

        let page = await source.nextContinuousPage()

        // Se l'utente ha disattivato la modalità mentre la pagina era in
        // arrivo, la scartiamo: non si aggiunge testo dopo lo stop.
        guard isSessionActive,
              pagingEnabled,
              appState.isContinuousReadingEnabled,
              appState.isAutoPageEnabled else {
            return false
        }

        if let notice = page.notice {
            appState.continuationNotice = notice
        }

        if page.isFinal {
            didReachEnd = true
            appState.isContinuousDocumentPaged = false
        }

        let completeRaw = rawCarry.append(page.text, isFinal: page.isFinal)
        guard !completeRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let filter = noiseFilter
        let normalizer = self.normalizer
        let chunker = self.chunker
        let mode = appState.noiseFilterMode
        let preparedAndChunks = await Task.detached(priority: .userInitiated) {
            let prepared = Self.prepare(
                completeRaw,
                normalizer: normalizer,
                filter: filter,
                mode: mode
            )
            return (prepared, chunker.chunk(text: prepared))
        }.value

        guard isSessionActive,
              pagingEnabled,
              appState.isContinuousReadingEnabled,
              appState.isAutoPageEnabled else {
            return false
        }

        let (prepared, chunks) = preparedAndChunks
        guard !prepared.isEmpty, !chunks.isEmpty else { return false }

        appState.appendChunks(chunks)
        if appState.capturedDocumentText.isEmpty {
            appState.capturedDocumentText = prepared
        } else {
            appState.capturedDocumentText += "\n\n" + prepared
        }

        return true
    }

    // MARK: - Pulizia sessione

    private func finishSession() {
        guard isSessionActive || appState.isContinuousSessionActive else { return }

        isSessionActive = false
        didReachEnd = true
        remainderTask?.cancel()
        remainderTask = nil
        rawCarry = SentenceCarryBuffer()

        appState.isContinuousSessionActive = false
        appState.isContinuousDocumentPaged = false
        appState.isFetchingMoreText = false

        let previousCleanup = sourceCleanupTask
        sourceCleanupTask = Task {
            await previousCleanup?.value
            await source.endContinuousCapture()
        }
    }

    // MARK: - Preferenze

    /// Osserva i due toggle senza accoppiare `AppState` al controller.
    /// Disattivare la modalità o il paging ferma solo le nuove pagine: la
    /// coda già catturata continua a essere riprodotta.
    private func observePagingPreferences() {
        withObservationTracking {
            _ = appState.isContinuousReadingEnabled
            _ = appState.isAutoPageEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.pagingEnabled = self.appState.isContinuousReadingEnabled
                    && self.appState.isAutoPageEnabled
                if !self.pagingEnabled {
                    self.appState.isContinuousDocumentPaged = false
                }
                self.observePagingPreferences()
            }
        }
    }

    // MARK: - Preparazione testo

    nonisolated private static func prepare(
        _ text: String,
        normalizer: TextNormalizer,
        filter: DocumentNoiseFilter,
        mode: NoiseFilterMode
    ) -> String {
        let normalizedNewlines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)

        let filtered = filter.filter(normalizedNewlines, mode: mode)
        let paragraphs = filtered.components(separatedBy: "\n\n")
        return paragraphs
            .map { normalizer.normalize(text: $0) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

private struct InitialPreparation: Sendable {
    let displayText: String
    let chunks: [ReadingChunk]
    let remainder: String
}
