import Foundation
import Observation
import LettoreCore

/// Interfaccia minima verso il motore di riproduzione usata dal controller.
///
/// In produzione è `PlaybackCoordinator`; nei test un sink finto evita di
/// istanziare sintesi vocale, audio e rete.
@MainActor
protocol ContinuousPlaybackSink: AnyObject {
    var onQueueLow: (() async -> Bool)? { get set }
    var onSessionEnded: (() -> Void)? { get set }
    func stop(endingSession: Bool)
    func playCurrentChunk()
}

/// Orchestra la modalità "Lettura continua" (DSA-11).
///
/// Responsabilità:
/// - avviare la cattura documentale;
/// - preparare e accodare subito la prima porzione di testo;
/// - chunckare il resto del documento catturato in background;
/// - chiedere le pagine successive quando la coda si avvicina alla fine;
/// - fermare il paging (ma non la coda già catturata) quando l'utente
///   disattiva la modalità o il caricamento automatico.
///
/// Ogni sessione ha una `sessionGeneration`: i task asincroni la catturano
/// all'avvio e la verificano dopo ogni `await`. Un task rimasto in volo da una
/// sessione precedente non può più accodare testo né mutare lo stato della
/// sessione nuova.
@MainActor
public final class ContinuousReadingController {

    public static let immediatePlaybackLength = 8_000

    /// Tetto di sicurezza per una singola `fetchNextPage`: evita che un
    /// documento senza terminatori di frase o una sorgente che non avanza
    /// tengano il controller in un ciclo senza fine.
    private static let maxPageFetchesPerRequest = 32

    public let appState: AppState
    public let coordinator: PlaybackCoordinator
    private let source: any ContinuousTextSource
    private let playback: any ContinuousPlaybackSink

    /// Chiamata quando anche il resto del documento è stato accodato e il
    /// playback può partire. Arriva solo quando la sorgente espone documento,
    /// PID e range: senza tutti e tre l'highlight non è mappabile.
    public var onSourceSessionStarted: ((UUID, pid_t) -> Void)?
    /// Chiamata una sola volta alla chiusura della sessione (stop, fine coda o
    /// errore di cattura). Non deseleziona nulla nell'app di origine.
    public var onSourceSessionEnded: (() -> Void)?

    private let textPreparer = ReadingTextPreparer()

    private var rawCarry = SentenceCarryBuffer()
    private var isSessionActive = false
    /// Identifica la sessione corrente: incrementata all'avvio di una nuova
    /// sessione e alla sua chiusura. I task asincroni la catturano all'avvio e
    /// la ricontrollano dopo ogni `await`.
    private var sessionGeneration = 0
    private var didReachEnd = false
    private var pagingEnabled = true
    private var remainderTask: Task<[ReadingChunk], Never>?
    private var sourceCleanupTask: Task<Void, Never>?
    private var hasSourceSession = false

    public convenience init(
        appState: AppState,
        coordinator: PlaybackCoordinator,
        source: any ContinuousTextSource
    ) {
        self.init(
            appState: appState,
            coordinator: coordinator,
            source: source,
            playback: coordinator
        )
    }

    /// Inizializzatore interno per i test: usa un sink finto al posto del
    /// `PlaybackCoordinator` reale, senza modificare l'API pubblica.
    init(
        appState: AppState,
        coordinator: PlaybackCoordinator,
        source: any ContinuousTextSource,
        playback: any ContinuousPlaybackSink
    ) {
        self.appState = appState
        self.coordinator = coordinator
        self.source = source
        self.playback = playback
        self.pagingEnabled = appState.isContinuousReadingEnabled && appState.isAutoPageEnabled

        playback.onQueueLow = { [weak self] in
            guard let self else { return false }
            return await self.fetchNextPage()
        }

        playback.onSessionEnded = { [weak self] in
            self?.finishSession()
        }

        observePagingPreferences()
    }

    /// Solo per test: porzione incompleta attualmente trattenuta in attesa di
    /// una frase completa.
    var pendingCarryText: String { rawCarry.pendingText }

    /// Solo per test: stato del paging dopo l'ultima osservazione dei toggle.
    var isPagingEnabled: Bool { pagingEnabled }

    // MARK: - API pubblica

    /// Cattura il testo dall'app in primo piano e avvia la lettura continua.
    /// Restituisce il testo preparato da mostrare nello Studio, oppure `nil`
    /// se non c'era nulla di leggibile.
    @discardableResult
    public func captureAndPlay() async -> String? {
        await captureAndPlay(from: nil)
    }

    /// Cattura il testo dall'app indicata (o da quella in primo piano se il PID
    /// è `nil`) e avvia la lettura continua.
    ///
    /// Il PID esplicito è necessario quando la richiesta parte dallo Studio:
    /// la finestra di Lettore è in primo piano, ma il testo da leggere vive
    /// nell'ultima app esterna attivata.
    @discardableResult
    public func captureAndPlay(from applicationPID: pid_t? = nil) async -> String? {
        if isSessionActive || appState.isContinuousSessionActive {
            stopSession()
        }

        // La chiusura della sessione AX precedente è asincrona: attendila
        // prima di aprirne una nuova, altrimenti potrebbe cancellarla.
        if let cleanup = sourceCleanupTask {
            await cleanup.value
            sourceCleanupTask = nil
        }

        let generation = beginSession()
        isSessionActive = true
        didReachEnd = false
        pagingEnabled = appState.isContinuousReadingEnabled && appState.isAutoPageEnabled
        rawCarry = SentenceCarryBuffer()
        remainderTask = nil
        appState.continuationNotice = nil
        appState.isContinuousSessionActive = true
        appState.isContinuousDocumentPaged = false
        appState.capturedDocumentText = ""
        appState.isFetchingMoreText = false

        let start: ContinuousCaptureStart
        if let applicationPID,
           let targeted = source as? any TargetedContinuousTextSource {
            start = await targeted.startContinuousCapture(from: applicationPID)
        } else {
            start = await source.startContinuousCapture()
        }
        guard isCurrent(generation) else { return nil }

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

        let preparer = textPreparer
        let mode = appState.noiseFilterMode
        let sourceRange = start.sourceRange
        let sourceDocumentID = start.sourceDocumentID
        let targetLength = Self.immediatePlaybackLength

        let preparation = await Task.detached(priority: .userInitiated) {
            preparer.prepareInitial(
                text: start.text,
                sourceRange: sourceRange,
                sourceDocumentID: sourceDocumentID,
                mode: mode,
                maxImmediateLength: targetLength
            )
        }.value

        guard isCurrent(generation) else { return nil }

        guard !preparation.chunks.isEmpty else {
            finishSession()
            appState.continuationNotice = "Il testo catturato non contiene frasi leggibili."
            return nil
        }

        appState.capturedDocumentText = preparation.displayText
        appState.setQueue(preparation.chunks)

        if preparation.hasRemainder {
            let preparer = textPreparer
            remainderTask = Task.detached(priority: .utility) {
                preparer.prepareRemainder(of: preparation)
            }
        }

        if let documentID = start.sourceDocumentID,
           let sourcePID = start.sourcePID,
           start.sourceRange != nil {
            hasSourceSession = true
            onSourceSessionStarted?(documentID, sourcePID)
        }

        playback.playCurrentChunk()
        return preparation.displayText
    }

    /// Ferma esplicitamente la sessione continua e la riproduzione.
    public func stopSession() {
        guard isSessionActive || appState.isContinuousSessionActive else { return }
        playback.stop(endingSession: true)
        finishSession()
    }

    /// Chiamata dal `PlaybackCoordinator` quando la coda sta per esaurirsi.
    /// Restituisce `true` se sono stati accodati nuovi chunk.
    ///
    /// Il testo trattenuto incompleto non fa terminare la sessione: il ciclo
    /// continua a chiedere pagine finché non produce almeno un chunk, la
    /// sorgente dichiara la fine del documento, o scatta il tetto di sicurezza.
    public func fetchNextPage() async -> Bool {
        guard isSessionActive else { return false }
        let generation = sessionGeneration

        appState.isFetchingMoreText = true
        defer {
            // Se nel frattempo è nata una sessione nuova, il flag appartiene a
            // quella sessione: non azzerarlo da qui.
            if generation == sessionGeneration {
                appState.isFetchingMoreText = false
            }
        }

        // Il resto del documento già catturato ha precedenza sulle nuove
        // pagine: l'ordine di lettura deve restare quello del documento.
        if let task = remainderTask {
            let chunks = await task.value
            guard isCurrent(generation) else { return false }
            remainderTask = nil

            // Anche se il task di paging è stato cancellato da uno skip, il
            // resto già catturato va accodato: fa parte della coda corrente.
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

        // Il carry viene lavorato su una copia locale e committato solo alla
        // fine: se la sessione cambia a metà fetch non resta alcuna scrittura
        // parziale nello stato della sessione nuova.
        var carry = rawCarry
        var pendingChunks: [ReadingChunk] = []
        var appendedText = ""
        var pendingNotice: String?
        var reachedEnd = false
        var appendedChunk = false
        var fetchCount = 0

        while !reachedEnd, !appendedChunk, fetchCount < Self.maxPageFetchesPerRequest {
            fetchCount += 1

            let page = await source.nextContinuousPage()
            guard isCurrent(generation),
                  pagingEnabled,
                  appState.isContinuousReadingEnabled,
                  appState.isAutoPageEnabled else {
                return false
            }

            if let notice = page.notice {
                pendingNotice = notice
            }
            reachedEnd = page.isFinal

            let completeRaw = carry.append(page.text, isFinal: page.isFinal)
            if !completeRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard let batch = await preparedBatch(from: completeRaw, generation: generation) else {
                    return false
                }
                if !batch.displayText.isEmpty, !batch.chunks.isEmpty {
                    appendedText = appendedText.isEmpty
                        ? batch.displayText
                        : appendedText + "\n\n" + batch.displayText
                    pendingChunks.append(contentsOf: batch.chunks)
                    appendedChunk = true
                }
            }
        }

        // Tetto di sicurezza raggiunto senza chunk: il residuo trattenuto non
        // potrà più essere completato da una pagina successiva e va letto
        // comunque. A fine documento `append(isFinal:)` lo restituisce già.
        if !appendedChunk, !reachedEnd {
            let tail = carry.flush()
            if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard let batch = await preparedBatch(from: tail, generation: generation) else {
                    return false
                }
                if !batch.displayText.isEmpty, !batch.chunks.isEmpty {
                    appendedText = appendedText.isEmpty
                        ? batch.displayText
                        : appendedText + "\n\n" + batch.displayText
                    pendingChunks.append(contentsOf: batch.chunks)
                }
            }
        }

        guard isCurrent(generation) else { return false }

        rawCarry = carry
        if let pendingNotice {
            appState.continuationNotice = pendingNotice
        }
        if reachedEnd {
            didReachEnd = true
            appState.isContinuousDocumentPaged = false
        }

        guard !pendingChunks.isEmpty else { return false }

        appState.appendChunks(pendingChunks)
        if !appendedText.isEmpty {
            if appState.capturedDocumentText.isEmpty {
                appState.capturedDocumentText = appendedText
            } else {
                appState.capturedDocumentText += "\n\n" + appendedText
            }
        }

        return true
    }

    // MARK: - Generazione di sessione

    /// Avvia una nuova sessione e restituisce il token da verificare dopo ogni
    /// `await`.
    private func beginSession() -> Int {
        sessionGeneration &+= 1
        return sessionGeneration
    }

    /// `true` solo se il task appartiene ancora alla sessione corrente.
    private func isCurrent(_ generation: Int) -> Bool {
        generation == sessionGeneration && isSessionActive
    }

    // MARK: - Pulizia sessione

    private func finishSession() {
        guard isSessionActive || appState.isContinuousSessionActive else { return }

        // Invalida ogni task in volo: da qui in poi non può più scrivere.
        sessionGeneration &+= 1
        isSessionActive = false
        didReachEnd = true
        remainderTask?.cancel()
        remainderTask = nil
        rawCarry = SentenceCarryBuffer()

        appState.isContinuousSessionActive = false
        appState.isContinuousDocumentPaged = false
        appState.isFetchingMoreText = false

        if hasSourceSession {
            hasSourceSession = false
            onSourceSessionEnded?()
        }

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

    private func preparedBatch(from raw: String, generation: Int) async -> PreparedReading? {
        let preparer = textPreparer
        let mode = appState.noiseFilterMode

        let reading = await Task.detached(priority: .userInitiated) {
            preparer.preparePage(text: raw, mode: mode)
        }.value

        guard isCurrent(generation) else { return nil }
        return reading
    }
}
