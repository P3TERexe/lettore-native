import XCTest
@testable import LettoreCore
@testable import LettoreEngine

@MainActor
final class PlaybackCoordinatorTests: XCTestCase {

    /// Pipeline che non produce audio: i test verificano solo i callback e
    /// cancellano la sintesi con `stop()`, senza rete né uscita audio reale.
    private final class HangingTTSPipeline: TTSPipelineProtocol, @unchecked Sendable {
        var isModelLoaded = true

        func loadModel() async throws {}

        func synthesize(
            text: String,
            voice: VoiceProfile,
            speed: Float
        ) async throws -> Data {
            try await synthesize(text: text, voice: voice, speed: speed, steps: 8)
        }

        func synthesize(
            text: String,
            voice: VoiceProfile,
            speed: Float,
            steps: Int
        ) async throws -> Data {
            try await Task.sleep(nanoseconds: 30_000_000_000)
            return Data()
        }
    }

    /// Pipeline che completa la sintesi solo quando il test lo decide:
    /// simula un backend che ignora la cancellazione e risponde in ritardo,
    /// dopo lo stop. Serve a verificare che `started`/`finished` tardivi non
    /// riaccendano il playback né ripopolino la coda.
    private final class GatedTTSPipeline: TTSPipelineProtocol, @unchecked Sendable {
        var isModelLoaded = true

        private let lock = NSLock()
        private var pending: [CheckedContinuation<Data, Error>] = []

        var pendingCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return pending.count
        }

        func loadModel() async throws {}

        func synthesize(
            text: String,
            voice: VoiceProfile,
            speed: Float
        ) async throws -> Data {
            try await synthesize(text: text, voice: voice, speed: speed, steps: 8)
        }

        func synthesize(
            text: String,
            voice: VoiceProfile,
            speed: Float,
            steps: Int
        ) async throws -> Data {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                pending.append(continuation)
                lock.unlock()
            }
        }

        /// Risponde a tutte le sintesi rimaste sospese, come farebbe un
        /// backend che completa la richiesta dopo la cancellazione.
        func completePending() {
            lock.lock()
            let continuations = pending
            pending.removeAll()
            lock.unlock()
            for continuation in continuations {
                continuation.resume(returning: Data())
            }
        }
    }

    @MainActor
    private final class DeferredQueueLow {
        private(set) var continuation: CheckedContinuation<Bool, Never>?

        func wait() async -> Bool {
            await withCheckedContinuation { self.continuation = $0 }
        }

        func resolve(_ value: Bool) {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }

    /// Cattura di selezione sospesa finché il test non la rilascia: simula una
    /// cattura/preparazione ancora in volo quando arriva lo stop esplicito.
    private actor GatedSelectionCapture: SelectedTextCapturing {
        private var continuation: CheckedContinuation<CapturedSelection?, Never>?
        private(set) var started = false

        func captureSelectedText(from applicationPID: pid_t?) async -> CapturedSelection? {
            started = true
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }

        func release(_ selection: CapturedSelection?) {
            let pending = continuation
            continuation = nil
            pending?.resume(returning: selection)
        }
    }

    @MainActor
    private final class StubSourceApplications: SourceApplicationProviding {
        var currentProcessIdentifier: pid_t = 900
        var frontmostApplicationPID: pid_t?
        var runningExternalPIDs: Set<pid_t> = []

        func validatedExternalApplicationPID(_ pid: pid_t?) -> pid_t? {
            guard let pid,
                  pid != currentProcessIdentifier,
                  runningExternalPIDs.contains(pid) else {
                return nil
            }
            return pid
        }
    }

    // MARK: - Chunk corrente

    func testCurrentChunkCallbackFiresOnPlaySkipJumpAndResume() {
        let (state, cleanup) = makeState(["Uno.", "Due.", "Tre."])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        var seen: [String] = []
        coordinator.onCurrentChunkChanged = { seen.append($0.text) }

        coordinator.playCurrentChunk()
        XCTAssertEqual(seen, ["Uno."], "Il play del primo chunk notifica il cambio")

        coordinator.skipForward()
        XCTAssertEqual(seen, ["Uno.", "Due."], "Lo skip in avanti notifica il nuovo chunk")

        coordinator.jumpToChunk(state.readingQueue[2])
        XCTAssertEqual(seen, ["Uno.", "Due.", "Tre."], "Il jump dalla lista notifica il chunk scelto")

        state.playbackState = .paused
        coordinator.play()
        XCTAssertEqual(seen.last, "Tre.", "La ripresa da pausa rivaluta il chunk corrente")

        coordinator.stop()
    }

    func testCurrentChunkCallbackIsNotFiredOnAudioProgress() {
        let (state, cleanup) = makeState(["Uno.", "Due."])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        var count = 0
        coordinator.onCurrentChunkChanged = { _ in count += 1 }
        coordinator.playCurrentChunk()

        coordinator.audioEngine.onProgressUpdate?(0.5)
        coordinator.audioEngine.onProgressUpdate?(0.9)

        XCTAssertEqual(count, 1, "Il progresso audio non deve aggiornare l'highlight")
        coordinator.stop()
    }

    // MARK: - Stato durante sintesi e paging

    func testPlayDuringSynthesisDoesNotRestartTheRequest() {
        let (state, cleanup) = makeState(["Uno.", "Due."])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        var seen: [String] = []
        coordinator.onCurrentChunkChanged = { seen.append($0.text) }

        coordinator.playCurrentChunk()
        XCTAssertEqual(state.playbackState, .synthesizing)
        XCTAssertEqual(seen, ["Uno."])

        coordinator.play()
        XCTAssertEqual(seen, ["Uno."], "Play durante la sintesi non deve riavviare il chunk")
        XCTAssertEqual(state.playbackState, .synthesizing)

        coordinator.stop()
    }

    func testJumpWhileFetchIsPendingCancelsThePendingPlay() async {
        let (state, cleanup) = makeState(["Uno.", "Due."])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        let gate = DeferredQueueLow()
        coordinator.onQueueLow = { await gate.wait() }

        var ended = 0
        coordinator.onPlaybackEnded = { ended += 1 }

        coordinator.playCurrentChunk()
        for _ in 0..<200 where gate.continuation == nil {
            await Task.yield()
        }
        XCTAssertNotNil(gate.continuation, "La fetch pagina deve essere in volo")

        // Esaurisce la coda mentre la pagina è in volo: il Play resta armato.
        coordinator.skipForward()
        coordinator.skipForward()
        XCTAssertEqual(state.playbackState, .synthesizing)

        // Il jump sceglie un chunk esistente: l'attesa non deve più chiudere
        // la sessione né riavviare la coda quando la fetch termina.
        coordinator.jumpToChunk(state.readingQueue[0])
        gate.resolve(false)
        for _ in 0..<200 where ended > 0 {
            await Task.yield()
        }

        XCTAssertEqual(ended, 0, "Il jump ha soddisfatto il Play: la fetch non chiude la sessione")
        XCTAssertEqual(state.playbackState, .synthesizing)
        coordinator.stop()
    }

    func testStopResetsWaveformLevels() {
        let (state, cleanup) = makeState(["Uno."])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        state.liveWaveformLevels = [1, 1, 1, 1, 1, 1, 1]
        coordinator.stop()

        XCTAssertEqual(state.liveWaveformLevels, AudioEngineService.idleWaveformLevels)
    }

    // MARK: - Stop con svuotamento coda

    func testStopAndClearQueueInterruptsInFlightSynthesisWithoutLatePlayback() async {
        let (state, cleanup) = makeState(["Sintesi in volo \(UUID().uuidString)."])
        defer { cleanup() }
        let pipeline = GatedTTSPipeline()
        let coordinator = makeCoordinator(state: state, pipeline: pipeline)

        var currentChanges = 0
        var playbackEnded = 0
        coordinator.onCurrentChunkChanged = { _ in currentChanges += 1 }
        coordinator.onPlaybackEnded = { playbackEnded += 1 }

        coordinator.playCurrentChunk()
        XCTAssertEqual(state.playbackState, .synthesizing)
        for _ in 0..<200 where pipeline.pendingCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(pipeline.pendingCount, 1, "La sintesi deve essere in volo")

        coordinator.stopAndClearQueue()
        XCTAssertEqual(state.playbackState, .idle)
        XCTAssertTrue(state.readingQueue.isEmpty)
        XCTAssertNil(state.currentChunk)

        // Il backend risponde dopo lo stop ignorando la cancellazione: gli
        // eventi tardivi non devono riportare lo stato in playing né
        // riavviare la coda appena svuotata.
        pipeline.completePending()
        for _ in 0..<200 {
            await Task.yield()
        }

        XCTAssertEqual(
            state.playbackState,
            .idle,
            "Un started tardivo non deve riaccendere il playback"
        )
        XCTAssertTrue(state.readingQueue.isEmpty, "Nessuna coda ricreata dopo lo stop")
        XCTAssertNil(state.currentChunk, "Nessun chunk corrente dopo lo stop")
        XCTAssertEqual(currentChanges, 1, "Nessun play tardivo dopo lo stop")
        XCTAssertEqual(playbackEnded, 1, "La fine sessione arriva una sola volta")
    }

    func testStopAndClearQueueCancelsPendingPagingWithoutLatePlay() async {
        let (state, cleanup) = makeState(["Pagina in volo \(UUID().uuidString)."])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        let gate = DeferredQueueLow()
        coordinator.onQueueLow = { await gate.wait() }

        var currentChanges = 0
        var playbackEnded = 0
        coordinator.onCurrentChunkChanged = { _ in currentChanges += 1 }
        coordinator.onPlaybackEnded = { playbackEnded += 1 }

        coordinator.playCurrentChunk()
        for _ in 0..<200 where gate.continuation == nil {
            await Task.yield()
        }
        XCTAssertNotNil(gate.continuation, "La fetch pagina deve essere in volo")

        coordinator.stopAndClearQueue()
        XCTAssertTrue(state.readingQueue.isEmpty)
        XCTAssertEqual(state.playbackState, .idle)

        // La pagina risponde "true" in ritardo: la richiesta cancellata non
        // deve far ripartire il play su una coda ormai vuota.
        gate.resolve(true)
        for _ in 0..<200 {
            await Task.yield()
        }

        XCTAssertTrue(state.readingQueue.isEmpty, "Nessuna coda ricreata dopo lo stop")
        XCTAssertEqual(state.playbackState, .idle, "La pagina tardiva non riapre il play")
        XCTAssertEqual(currentChanges, 1, "Nessun play tardivo dopo lo stop")
        XCTAssertEqual(playbackEnded, 1, "La fine sessione arriva una sola volta")
    }

    func testStopAndClearQueueStopsPlaybackAndEmptiesTheQueue() {
        let (state, cleanup) = makeState(["Uno.", "Due."])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        var playbackEnded = 0
        var sessionEnded = 0
        coordinator.onPlaybackEnded = { playbackEnded += 1 }
        coordinator.onSessionEnded = { sessionEnded += 1 }

        state.capturedDocumentText = "Documento intatto."
        coordinator.playCurrentChunk()
        state.playbackProgress = 0.5
        state.liveWaveformLevels = [1, 1, 1, 1, 1, 1, 1]
        state.isUsingSpeechFallback = true
        state.speechFallbackNotice = "Voce di sistema attiva."

        coordinator.stopAndClearQueue()

        XCTAssertEqual(state.playbackState, .idle, "Il playback torna idle")
        XCTAssertTrue(state.readingQueue.isEmpty, "La coda viene svuotata")
        XCTAssertNil(state.currentChunk, "Non resta alcun chunk corrente")
        XCTAssertEqual(state.playbackProgress, 0.0, "Il progresso torna a zero")
        XCTAssertEqual(state.liveWaveformLevels, AudioEngineService.idleWaveformLevels)
        XCTAssertFalse(
            state.isUsingSpeechFallback,
            "Lo stop esplicito spegne il badge della voce di sistema"
        )
        XCTAssertNil(
            state.speechFallbackNotice,
            "Lo stop esplicito rimuove l'avviso di fallback, che descriveva l'audio interrotto"
        )
        XCTAssertEqual(
            state.capturedDocumentText,
            "Documento intatto.",
            "Svuotare la coda non tocca il documento catturato"
        )
        XCTAssertEqual(playbackEnded, 1, "La fine sessione arriva una sola volta")
        XCTAssertEqual(sessionEnded, 1, "La sessione viene chiusa una sola volta")

        coordinator.stopAndClearQueue()
        XCTAssertEqual(playbackEnded, 1, "Un secondo stop non duplica la fine")
        XCTAssertEqual(sessionEnded, 1, "Un secondo stop non richiude la sessione")
        XCTAssertTrue(state.readingQueue.isEmpty)
    }

    func testStopAndClearQueueClearsTheContinuationNoticeWithoutTouchingLatencyMetrics() {
        let (state, cleanup) = makeState(["Uno."])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        state.continuationNotice = "Nessun testo leggibile nell'app in primo piano."
        state.lastFirstChunkLatencyMs = 123.0
        state.lastSynthesisLatencyMs = 456.0

        coordinator.stopAndClearQueue()

        XCTAssertNil(
            state.continuationNotice,
            "Il banner di una cattura abbandonata non deve sopravvivere allo stop"
        )
        XCTAssertTrue(state.readingQueue.isEmpty, "Lo stop svuota la coda")
        XCTAssertEqual(
            state.lastFirstChunkLatencyMs,
            123.0,
            "Le telemetrie di latenza sono misure storiche e restano intatte"
        )
        XCTAssertEqual(state.lastSynthesisLatencyMs, 456.0)
    }

    func testExplicitStopInvalidatesPendingCapturesButPlainStopDoesNot() {
        let (state, cleanup) = makeState(["Uno."])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        var explicitStops = 0
        coordinator.onExplicitStop = { explicitStops += 1 }

        coordinator.stop()
        XCTAssertEqual(
            explicitStops,
            0,
            "Lo stop normale (skip, fine coda, cambio selezione) non invalida le catture"
        )

        coordinator.stopAndClearQueue()
        XCTAssertEqual(
            explicitStops,
            1,
            "Lo stop esplicito che svuota la coda invalida le catture in volo una sola volta"
        )

        coordinator.stop()
        XCTAssertEqual(explicitStops, 1, "Uno stop normale successivo non invalida di nuovo")
    }

    /// Integrazione reale `PlaybackCoordinator.onExplicitStop` ↔
    /// `ReadingCaptureController`: lo stop esplicito parte dal coordinatore,
    /// che invalida la richiesta di cattura ancora in volo. La coda svuotata
    /// dallo stop non deve essere ripopolata quando la cattura risponde.
    ///
    /// La fase di preparazione testuale non è iniettabile da qui (il preparer
    /// vive dentro il controller): la cattura resta sospesa, che copre la
    /// stessa finestra di invalidazione verificata dopo ogni `await`.
    func testExplicitStopInvalidatesPendingCaptureThroughControllerWiring() async {
        let (state, cleanup) = makeState([])
        defer { cleanup() }
        state.lastExternalApplicationPID = 42

        let capture = GatedSelectionCapture()
        let applications = StubSourceApplications()
        applications.runningExternalPIDs = [42]
        let controller = ReadingCaptureController(
            appState: state,
            selectedText: capture,
            sourceApplications: applications,
            continuousCapture: { _ in nil },
            cancelContinuousSession: {}
        )
        let coordinator = makeCoordinator(state: state)
        // Stesso wiring di `LettoreApp`: lo stop esplicito invalida catture e
        // preparazioni in volo prima di svuotare la coda.
        coordinator.onExplicitStop = { [weak controller] in
            controller?.invalidatePendingRequests()
        }

        let pending = Task { await controller.playFromUI(isContinuousEnabled: false) }
        let started = await waitUntil { await capture.started }
        XCTAssertTrue(started, "La cattura deve essere in volo prima dello stop")

        coordinator.stopAndClearQueue()
        XCTAssertTrue(state.readingQueue.isEmpty, "Lo stop svuota subito la coda")

        await capture.release(CapturedSelection(text: "Testo preparato prima dello stop."))
        let outcome = await pending.value
        guard case .unavailable = outcome else {
            return XCTFail("La richiesta superata dallo stop deve essere scartata, ricevuto \(outcome)")
        }
        XCTAssertTrue(
            state.readingQueue.isEmpty,
            "La cattura partita prima dello stop non deve ripopolare la coda svuotata"
        )
        XCTAssertNil(state.currentChunk)
    }

    // MARK: - Generazione di sessione (esiti asincroni tardivi)

    func testNewQueueAndClearQueueInvalidateTheSessionGeneration() {
        let (state, cleanup) = makeState(["Uno.", "Due."])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        let generation = state.sessionGeneration
        XCTAssertTrue(state.isSessionCurrent(generation))

        coordinator.stop()
        XCTAssertTrue(
            state.isSessionCurrent(generation),
            "Lo stop normale non svuota la coda: il token resta valido"
        )

        state.setQueue([ReadingChunk(index: 0, text: "Nuova coda.")])
        XCTAssertFalse(
            state.isSessionCurrent(generation),
            "Una coda nuova apre una sessione nuova: gli esiti in volo della precedente vanno superati"
        )
        let afterSetQueue = state.sessionGeneration
        XCTAssertTrue(state.isSessionCurrent(afterSetQueue))

        state.clearQueue()
        XCTAssertFalse(state.isSessionCurrent(afterSetQueue), "Il clear invalida la generazione precedente")
        XCTAssertNotEqual(state.sessionGeneration, afterSetQueue)
        XCTAssertTrue(state.isSessionCurrent(state.sessionGeneration))
    }

    func testEveryExplicitStopInvalidatesTheGeneration() {
        let (state, cleanup) = makeState(["Uno."])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        let initial = state.sessionGeneration
        coordinator.stopAndClearQueue()
        let afterFirstStop = state.sessionGeneration
        XCTAssertNotEqual(afterFirstStop, initial, "Lo stop esplicito invalida il token")

        coordinator.stopAndClearQueue()
        XCTAssertNotEqual(
            state.sessionGeneration,
            afterFirstStop,
            "Una riconnessione partita fra due stop resta comunque superata"
        )
    }

    // MARK: - Gate delle catture (stop durante una cattura in volo)

    func testCaptureGateBlocksConcurrentCapturesAndReleasesOnEnd() {
        let gate = CaptureInFlightGate()

        guard let first = gate.begin() else {
            return XCTFail("Con il gate libero la cattura deve partire")
        }
        XCTAssertTrue(gate.isBusy)
        XCTAssertNil(gate.begin(), "Una seconda cattura non parte mentre la prima è in volo")

        gate.end(first)
        XCTAssertFalse(gate.isBusy, "La cattura corrente libera il gate")
        XCTAssertNotNil(gate.begin(), "Dopo la risposta il gate è di nuovo libero")
    }

    /// Riproduce il blocker: dopo "Ferma" una cattura AX ancora in volo
    /// teneva `isBusy = true`, quindi RIPRODUCI/⌥P venivano scartati dal guard
    /// e il comando era no-op. Lo stop deve liberare il gate subito e superare
    /// la cattura, che alla risposta non deve toccare la sessione nuova.
    func testExplicitStopReleasesTheGateAndSupersedesTheInFlightCapture() {
        let gate = CaptureInFlightGate()
        guard let stale = gate.begin() else {
            return XCTFail("La cattura deve partire")
        }

        gate.invalidate()
        XCTAssertFalse(
            gate.isBusy,
            "Lo stop non deve lasciare il gate occupato fino alla risposta AX"
        )
        XCTAssertFalse(gate.isCurrent(stale), "La cattura in volo è superata dallo stop")
        XCTAssertEqual(gate.generation, stale &+ 1, "Lo stop apre una generazione nuova")

        guard let fresh = gate.begin() else {
            return XCTFail("Dopo lo stop il comando successivo deve poter catturare subito")
        }
        XCTAssertNotEqual(fresh, stale)
        XCTAssertTrue(gate.isCurrent(fresh))

        // La cattura vecchia risponde dopo lo stop: il suo `defer` non deve
        // liberare il gate della cattura nuova.
        gate.end(stale)
        XCTAssertTrue(gate.isBusy, "Il defer della cattura superata non tocca il gate nuovo")
        XCTAssertTrue(gate.isCurrent(fresh))

        gate.end(fresh)
        XCTAssertFalse(gate.isBusy)
    }

    /// La riconnessione di Supertonic cattura il token prima di `loadModel()`:
    /// se nel frattempo arriva uno Stop, l'esito tardivo (successo o errore)
    /// non va applicato, altrimenti riaccenderebbe badge e avvisi della
    /// sessione che l'utente ha appena chiuso.
    func testReconnectOutcomeIsDiscardedAfterStopDuringTheAwait() async {
        let (state, cleanup) = makeState(["Uno."])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        let generation = state.sessionGeneration
        let reconnect = Task { () -> Bool in
            // Backend lento: lo stop arriva prima dell'esito.
            try? await Task.sleep(nanoseconds: 50_000_000)
            return state.isSessionCurrent(generation)
        }

        coordinator.stopAndClearQueue()
        let applied = await reconnect.value

        XCTAssertFalse(applied, "L'esito arrivato dopo lo stop non va applicato")
        XCTAssertFalse(state.isUsingSpeechFallback)
        XCTAssertNil(state.speechFallbackNotice)
    }

    // MARK: - Fine sessione

    func testPlaybackEndedFiresOnceOnRepeatedStop() {
        let (state, cleanup) = makeState(["Uno."])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        var ended = 0
        coordinator.onPlaybackEnded = { ended += 1 }

        coordinator.playCurrentChunk()
        coordinator.stop()
        XCTAssertEqual(ended, 1)

        coordinator.stop()
        XCTAssertEqual(ended, 1, "Uno stop ripetuto non duplica la fine sessione")
    }

    func testPlaybackEndedFiresWhenQueueExhaustsAfterLastChunk() {
        let (state, cleanup) = makeState(["Unico."])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        var ended = 0
        coordinator.onPlaybackEnded = { ended += 1 }

        coordinator.playCurrentChunk()
        coordinator.skipForward()

        XCTAssertEqual(ended, 1, "La coda esaurita dichiara la fine una volta")

        coordinator.stop()
        XCTAssertEqual(ended, 1, "Lo stop successivo non duplica la fine")
    }

    func testPlaybackEndedFiresWithoutCurrentChunkAndResetsForANewSession() {
        let (state, cleanup) = makeState([])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        var ended = 0
        coordinator.onPlaybackEnded = { ended += 1 }

        coordinator.playCurrentChunk()
        XCTAssertEqual(ended, 1, "Senza chunk corrente la sessione è conclusa")

        coordinator.playCurrentChunk()
        XCTAssertEqual(ended, 1, "Nessun doppione senza un nuovo chunk")

        state.setQueue([ReadingChunk(index: 0, text: "Nuova sessione.")])
        coordinator.playCurrentChunk()
        coordinator.stop()
        XCTAssertEqual(ended, 2, "Una nuova sessione può terminare di nuovo")
    }

    func testPlaybackEndedWaitsForPendingFetchThatReturnsNoChunks() async {
        let (state, cleanup) = makeState(["Unico."])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        let gate = DeferredQueueLow()
        coordinator.onQueueLow = { await gate.wait() }

        var ended = 0
        coordinator.onPlaybackEnded = { ended += 1 }

        coordinator.playCurrentChunk()
        for _ in 0..<200 where gate.continuation == nil {
            await Task.yield()
        }
        XCTAssertNotNil(gate.continuation, "La fetch pagina deve essere in volo")

        coordinator.skipForward()
        XCTAssertEqual(ended, 0, "La fine non va dichiarata prima dell'esito della fetch")

        gate.resolve(false)
        for _ in 0..<200 where ended == 0 {
            await Task.yield()
        }

        XCTAssertEqual(ended, 1, "Una fetch senza chunk chiude la sessione")
        coordinator.stop()
        XCTAssertEqual(ended, 1)
    }

    func testPlayDuringPendingFetchDoesNotEndPlaybackSession() async {
        let (state, cleanup) = makeState(["Unico."])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        let gate = DeferredQueueLow()
        coordinator.onQueueLow = { await gate.wait() }

        var ended = 0
        coordinator.onPlaybackEnded = { ended += 1 }

        coordinator.playCurrentChunk()
        for _ in 0..<200 where gate.continuation == nil {
            await Task.yield()
        }
        XCTAssertNotNil(gate.continuation, "La fetch pagina deve essere in volo")

        coordinator.skipForward()
        XCTAssertEqual(ended, 0)

        // Play dalla pillola mentre la pagina è in volo: non c'è un chunk
        // corrente, ma la sessione non è finita.
        coordinator.playCurrentChunk()
        XCTAssertEqual(ended, 0, "Il Play non deve chiudere la sessione con una fetch pendente")
        XCTAssertEqual(state.playbackState, .synthesizing)

        gate.resolve(false)
        for _ in 0..<200 where ended == 0 {
            await Task.yield()
        }

        XCTAssertEqual(ended, 1, "La fine arriva solo quando la fetch non produce chunk")
        coordinator.stop()
        XCTAssertEqual(ended, 1)
    }

    // MARK: - Helper

    private func waitUntil(
        timeout: TimeInterval = 2.0,
        _ condition: () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return await condition()
    }

    private func makeState(_ texts: [String]) -> (AppState, () -> Void) {
        let suiteName = "LettoreTests.Playback.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let state = AppState(preferences: PreferencesStore(defaults: defaults))
        state.setQueue(texts.enumerated().map { index, text in
            ReadingChunk(index: index, text: text)
        })
        return (state, { defaults.removePersistentDomain(forName: suiteName) })
    }

    private func makeCoordinator(
        state: AppState,
        pipeline: any TTSPipelineProtocol = HangingTTSPipeline()
    ) -> PlaybackCoordinator {
        PlaybackCoordinator(
            appState: state,
            audioEngine: AudioEngineService(),
            supertonicPipeline: pipeline
        )
    }
}
