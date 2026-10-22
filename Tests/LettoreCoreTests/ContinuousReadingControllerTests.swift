import XCTest
@testable import LettoreCore
@testable import LettoreEngine

@MainActor
final class ContinuousReadingControllerTests: XCTestCase {

    // MARK: - Sorgente finta

    @MainActor
    final class FakeContinuousTextSource: TargetedContinuousTextSource {
        var startResults: [ContinuousCaptureStart] = []
        var pages: [ContinuousTextPage] = []
        /// Quando attivo, la prossima `nextContinuousPage` si blocca finché il
        /// test non chiama `releaseHeldPage()`.
        var holdNextPage = false

        private(set) var startCallCount = 0
        private(set) var targetedStartPIDs: [pid_t] = []
        private(set) var pageCallCount = 0
        private(set) var isHoldingPage = false

        private var releaseContinuation: CheckedContinuation<Void, Never>?
        private var pageRequestWaiters: [CheckedContinuation<Void, Never>] = []

        func startContinuousCapture() async -> ContinuousCaptureStart {
            startCallCount += 1
            guard !startResults.isEmpty else {
                return ContinuousCaptureStart(text: "", selectedText: "")
            }
            return startResults.removeFirst()
        }

        func startContinuousCapture(from applicationPID: pid_t) async -> ContinuousCaptureStart {
            targetedStartPIDs.append(applicationPID)
            return await startContinuousCapture()
        }

        func nextContinuousPage() async -> ContinuousTextPage {
            pageCallCount += 1

            if holdNextPage {
                isHoldingPage = true
                let waiters = pageRequestWaiters
                pageRequestWaiters = []
                waiters.forEach { $0.resume() }
                await withCheckedContinuation { continuation in
                    releaseContinuation = continuation
                }
                isHoldingPage = false
                holdNextPage = false
            }

            guard !pages.isEmpty else { return .end }
            return pages.removeFirst()
        }

        func endContinuousCapture() async {}

        /// Attende che una richiesta di pagina sia entrata nella fase bloccata.
        func waitUntilPageRequestStarts() async {
            if isHoldingPage { return }
            await withCheckedContinuation { continuation in
                pageRequestWaiters.append(continuation)
            }
        }

        func releaseHeldPage() {
            releaseContinuation?.resume()
            releaseContinuation = nil
        }
    }

    // MARK: - Sink finto

    @MainActor
    final class FakePlaybackSink: ContinuousPlaybackSink {
        var onQueueLow: (() async -> Bool)?
        var onSessionEnded: (() -> Void)?

        private(set) var playCallCount = 0
        private(set) var stopCallCount = 0

        func stop(endingSession: Bool) {
            stopCallCount += 1
            onSessionEnded?()
        }

        func playCurrentChunk() {
            playCallCount += 1
        }
    }

    // MARK: - Test 1: pagina senza terminatori (< 4.000) seguita dalla pagina finale

    func testPageWithoutSentenceTerminatorsContinuesToFinalPageWithoutLosingText() async {
        let (state, cleanup) = makeState()
        defer { cleanup() }

        let source = FakeContinuousTextSource()
        source.startResults = [
            ContinuousCaptureStart(
                text: "Introduzione al documento.",
                selectedText: "Introduzione",
                canPage: true
            )
        ]
        source.pages = [
            ContinuousTextPage(text: "una pagina senza alcun punto fermo ", isFinal: false),
            ContinuousTextPage(text: "e la frase si conclude qui.", isFinal: true)
        ]

        let (controller, _) = makeController(state: state, source: source)

        let captured = await controller.captureAndPlay()
        XCTAssertEqual(captured, "Introduzione al documento.")
        XCTAssertEqual(source.pageCallCount, 0)

        let appended = await controller.fetchNextPage()

        XCTAssertTrue(appended, "La pagina finale deve completare il carry trattenuto")
        XCTAssertEqual(source.pageCallCount, 2, "Deve chiedere la pagina successiva invece di terminare")
        XCTAssertEqual(state.readingQueue.count, 2)
        XCTAssertEqual(state.readingQueue[0].text, "Introduzione al documento.")
        XCTAssertEqual(
            state.readingQueue[1].text,
            "una pagina senza alcun punto fermo e la frase si conclude qui."
        )
        XCTAssertTrue(controller.pendingCarryText.isEmpty)
        XCTAssertTrue(state.isContinuousSessionActive)
        XCTAssertFalse(state.isFetchingMoreText)
    }

    // MARK: - Test 2: pagina senza frasi, poi pagine successive

    func testPageWithoutSentencesKeepsRequestingPagesInsteadOfEnding() async {
        let (state, cleanup) = makeState()
        defer { cleanup() }

        let source = FakeContinuousTextSource()
        source.startResults = [
            ContinuousCaptureStart(text: "Avvio.", selectedText: "", canPage: true)
        ]
        source.pages = [
            ContinuousTextPage(text: "prima parte senza punto ", isFinal: false),
            ContinuousTextPage(text: "seconda parte ancora senza punto ", isFinal: false),
            ContinuousTextPage(text: "terza parte conclude.", isFinal: false)
        ]

        let (controller, _) = makeController(state: state, source: source)
        _ = await controller.captureAndPlay()

        let appended = await controller.fetchNextPage()

        XCTAssertTrue(appended)
        XCTAssertEqual(source.pageCallCount, 3, "Due pagine senza frasi non devono chiudere la sessione")
        XCTAssertEqual(
            state.readingQueue.map(\.text),
            [
                "Avvio.",
                "prima parte senza punto seconda parte ancora senza punto terza parte conclude."
            ]
        )
        XCTAssertTrue(state.isContinuousSessionActive)
    }

    // MARK: - Test I4: pagina interamente filtrata

    func testPageCompletelyFilteredOutKeepsRequestingPages() async {
        let (state, cleanup) = makeState()
        defer { cleanup() }

        let source = FakeContinuousTextSource()
        source.startResults = [
            ContinuousCaptureStart(text: "Avvio.", selectedText: "", canPage: true)
        ]
        source.pages = [
            // Solo un numero di pagina: il filtro lo rimuove e non resta nulla.
            ContinuousTextPage(text: "12\n", isFinal: false),
            ContinuousTextPage(text: "Testo della pagina successiva.", isFinal: false)
        ]

        let (controller, _) = makeController(state: state, source: source)
        _ = await controller.captureAndPlay()

        let appended = await controller.fetchNextPage()

        XCTAssertTrue(appended, "Una pagina filtrata non deve chiudere la sessione")
        XCTAssertEqual(source.pageCallCount, 2)
        XCTAssertEqual(
            state.readingQueue.map(\.text),
            ["Avvio.", "Testo della pagina successiva."]
        )
        XCTAssertTrue(state.isContinuousSessionActive)
    }

    // MARK: - Test 3: stop + nuova sessione durante una fetch lenta

    func testSlowFetchOfPreviousSessionCannotAppendTextToNewSession() async {
        let (state, cleanup) = makeState()
        defer { cleanup() }

        let source = FakeContinuousTextSource()
        source.startResults = [
            ContinuousCaptureStart(text: "Prima sessione.", selectedText: "", canPage: true)
        ]

        let (controller, _) = makeController(state: state, source: source)
        _ = await controller.captureAndPlay()

        source.holdNextPage = true
        let slowFetch = Task { await controller.fetchNextPage() }
        await source.waitUntilPageRequestStarts()
        XCTAssertTrue(source.isHoldingPage)

        controller.stopSession()
        XCTAssertFalse(state.isContinuousSessionActive)

        source.startResults = [
            ContinuousCaptureStart(text: "Seconda sessione.", selectedText: "", canPage: true)
        ]
        let captured = await controller.captureAndPlay()
        XCTAssertEqual(captured, "Seconda sessione.")

        // La pagina della sessione vecchia arriva solo ora.
        source.pages = [
            ContinuousTextPage(text: "TESTO DELLA VECCHIA SESSIONE.", isFinal: false)
        ]
        source.releaseHeldPage()

        let appendedByOldFetch = await slowFetch.value

        XCTAssertFalse(appendedByOldFetch, "Un fetch della sessione precedente non deve accodare nulla")
        XCTAssertEqual(state.readingQueue.map(\.text), ["Seconda sessione."])
        XCTAssertEqual(state.capturedDocumentText, "Seconda sessione.")
        XCTAssertFalse(state.isFetchingMoreText)
        XCTAssertTrue(state.isContinuousSessionActive)
    }

    // MARK: - Test B1: il vecchio remainderTask non entra nella sessione nuova

    func testRemainderOfPreviousSessionDoesNotLeakIntoNewSession() async {
        let (state, cleanup) = makeState()
        defer { cleanup() }

        let unit = "Frase iniziale numero uno molto lunga. "
        let longText = String(repeating: unit, count: 220) + "CODA VECCHIA. CODA VECCHIA DUE."

        let source = FakeContinuousTextSource()
        source.startResults = [
            ContinuousCaptureStart(text: longText, selectedText: "", canPage: true),
            ContinuousCaptureStart(text: "Seconda sessione breve.", selectedText: "", canPage: true)
        ]

        let (controller, _) = makeController(state: state, source: source)
        _ = await controller.captureAndPlay()

        // La cattura lunga ha lasciato un resto da chunkare in background.
        controller.stopSession()
        _ = await controller.captureAndPlay()

        let appended = await controller.fetchNextPage()
        XCTAssertFalse(appended)
        XCTAssertEqual(state.readingQueue.map(\.text), ["Seconda sessione breve."])
        XCTAssertFalse(state.capturedDocumentText.contains("CODA VECCHIA"))
    }

    // MARK: - Test 4: toggle off durante la fetch

    func testToggleOffDuringFetchDiscardsPageAndKeepsCarryIntact() async {
        let (state, cleanup) = makeState()
        defer { cleanup() }

        let source = FakeContinuousTextSource()
        source.startResults = [
            ContinuousCaptureStart(text: "Frase iniziale.", selectedText: "", canPage: true)
        ]
        source.pages = [
            ContinuousTextPage(text: "Frase completa. Frase incom", isFinal: false)
        ]

        let (controller, _) = makeController(state: state, source: source)
        _ = await controller.captureAndPlay()

        let firstFetch = await controller.fetchNextPage()
        XCTAssertTrue(firstFetch)
        XCTAssertEqual(state.readingQueue.map(\.text), ["Frase iniziale.", "Frase completa."])
        XCTAssertEqual(controller.pendingCarryText, "Frase incom")

        source.holdNextPage = true
        let slowFetch = Task { await controller.fetchNextPage() }
        await source.waitUntilPageRequestStarts()

        state.isContinuousReadingEnabled = false

        source.pages = [
            ContinuousTextPage(text: "pleta. Pagina scartata.", isFinal: false)
        ]
        source.releaseHeldPage()

        let appendedByDiscardedFetch = await slowFetch.value

        XCTAssertFalse(appendedByDiscardedFetch)
        XCTAssertEqual(
            state.readingQueue.map(\.text),
            ["Frase iniziale.", "Frase completa."],
            "La pagina arrivata dopo il toggle off non deve essere accodata"
        )
        XCTAssertEqual(controller.pendingCarryText, "Frase incom", "Il carry esistente non deve rompersi")

        // Riattivando la modalità il carry trattenuto deve completarsi.
        state.isContinuousReadingEnabled = true
        await waitUntilPagingEnabled(controller, expected: true)

        source.pages = [
            ContinuousTextPage(text: "pleta. Fine documento.", isFinal: false)
        ]
        let appendedAfterResume = await controller.fetchNextPage()

        XCTAssertTrue(appendedAfterResume)
        XCTAssertEqual(
            state.readingQueue.map(\.text),
            [
                "Frase iniziale.",
                "Frase completa.",
                "Frase incompleta.",
                "Fine documento."
            ]
        )
    }

    // MARK: - Test N10: pagina scartata senza avviso né fine sessione prematuri

    func testDiscardedPageDoesNotLeaveNoticeAndDoesNotEndSessionPrematurely() async {
        let (state, cleanup) = makeState()
        defer { cleanup() }

        let source = FakeContinuousTextSource()
        source.startResults = [
            ContinuousCaptureStart(text: "Avvio.", selectedText: "", canPage: true)
        ]

        let (controller, _) = makeController(state: state, source: source)
        _ = await controller.captureAndPlay()

        source.holdNextPage = true
        let slowFetch = Task { await controller.fetchNextPage() }
        await source.waitUntilPageRequestStarts()

        state.isContinuousReadingEnabled = false

        source.pages = [
            ContinuousTextPage(
                text: "Pagina finale scartata.",
                isFinal: true,
                notice: "Avviso della pagina scartata"
            )
        ]
        source.releaseHeldPage()

        let appended = await slowFetch.value

        XCTAssertFalse(appended)
        XCTAssertNil(state.continuationNotice, "Una pagina scartata non deve lasciare l'avviso a schermo")
        XCTAssertFalse(state.isContinuousDocumentPaged)

        // Riattiva: la sessione non è terminata, quindi la sorgente va richiamata.
        state.isContinuousReadingEnabled = true
        await waitUntilPagingEnabled(controller, expected: true)

        source.pages = [
            ContinuousTextPage(text: "Pagina valida.", isFinal: false)
        ]
        let appendedAfterResume = await controller.fetchNextPage()

        XCTAssertTrue(appendedAfterResume)
        XCTAssertEqual(source.pageCallCount, 2, "La fine del documento non deve essere stata registrata")
        XCTAssertEqual(state.readingQueue.last?.text, "Pagina valida.")
    }

    // MARK: - Test 5: ordine resto → pagine

    func testRemainderIsAppendedBeforeFetchedPagesAndPagesKeepDocumentOrder() async {
        let (state, cleanup) = makeState()
        defer { cleanup() }

        let unit = "Frase iniziale numero uno molto lunga. "
        let longText = String(repeating: unit, count: 220) + "CODA ALFA. CODA BETA."

        let source = FakeContinuousTextSource()
        source.startResults = [
            ContinuousCaptureStart(text: longText, selectedText: "", canPage: true)
        ]
        source.pages = [
            ContinuousTextPage(text: "PAGINA ALFA.", isFinal: false),
            ContinuousTextPage(text: "PAGINA BETA.", isFinal: true)
        ]

        let (controller, _) = makeController(state: state, source: source)
        _ = await controller.captureAndPlay()

        let immediateChunks = state.readingQueue.map(\.text)
        XCTAssertTrue(immediateChunks.count > 1, "Il testo iniziale deve essere accodato subito")
        XCTAssertEqual(immediateChunks.last, "Frase iniziale numero uno molto lunga.")

        let remainderAppended = await controller.fetchNextPage()
        XCTAssertTrue(remainderAppended)
        XCTAssertEqual(source.pageCallCount, 0, "Il resto della cattura deve precedere le nuove pagine")
        XCTAssertEqual(
            state.readingQueue.map(\.text).suffix(2),
            ["CODA ALFA.", "CODA BETA."]
        )

        let firstPageAppended = await controller.fetchNextPage()
        XCTAssertTrue(firstPageAppended)
        XCTAssertEqual(source.pageCallCount, 1)

        let secondPageAppended = await controller.fetchNextPage()
        XCTAssertTrue(secondPageAppended)
        XCTAssertEqual(source.pageCallCount, 2)

        XCTAssertEqual(
            state.readingQueue.map(\.text).suffix(4),
            ["CODA ALFA.", "CODA BETA.", "PAGINA ALFA.", "PAGINA BETA."]
        )
        XCTAssertFalse(state.isContinuousDocumentPaged)
    }

    // MARK: - Test 6: fine documento

    func testEndOfDocumentFlushesCarryAndStopsPaging() async {
        let (state, cleanup) = makeState()
        defer { cleanup() }

        let source = FakeContinuousTextSource()
        source.startResults = [
            ContinuousCaptureStart(text: "Avvio.", selectedText: "", canPage: true)
        ]
        source.pages = [
            ContinuousTextPage(text: "Una coda senza terminatore ", isFinal: false),
            ContinuousTextPage(text: "che termina con un punto.", isFinal: true)
        ]

        let (controller, _) = makeController(state: state, source: source)
        _ = await controller.captureAndPlay()

        let appended = await controller.fetchNextPage()
        XCTAssertTrue(appended)
        XCTAssertEqual(
            state.readingQueue.map(\.text),
            ["Avvio.", "Una coda senza terminatore che termina con un punto."]
        )
        XCTAssertTrue(controller.pendingCarryText.isEmpty)
        XCTAssertFalse(state.isContinuousDocumentPaged)

        let appendedAgain = await controller.fetchNextPage()
        XCTAssertFalse(appendedAgain)
        XCTAssertEqual(source.pageCallCount, 2, "A fine documento non si chiedono altre pagine")
    }

    // MARK: - Test B2: cattura da un PID esplicito

    func testCaptureAndPlayUsesExplicitApplicationPIDWithTargetedSource() async {
        let (state, cleanup) = makeState()
        defer { cleanup() }

        let source = FakeContinuousTextSource()
        source.startResults = [
            ContinuousCaptureStart(
                text: "Testo dall'app esterna.",
                selectedText: "Testo",
                canPage: false
            )
        ]

        let (controller, _) = makeController(state: state, source: source)

        let captured = await controller.captureAndPlay(from: 4_242)

        XCTAssertEqual(captured, "Testo dall'app esterna.")
        XCTAssertEqual(source.targetedStartPIDs, [4_242], "La sorgente target deve ricevere il PID esplicito")
        XCTAssertEqual(source.startCallCount, 1)
    }

    func testCaptureAndPlayWithoutPIDUsesUntargetedStart() async {
        let (state, cleanup) = makeState()
        defer { cleanup() }

        let source = FakeContinuousTextSource()
        source.startResults = [
            ContinuousCaptureStart(text: "Testo in primo piano.", selectedText: "", canPage: false)
        ]

        let (controller, _) = makeController(state: state, source: source)

        let captured = await controller.captureAndPlay()

        XCTAssertEqual(captured, "Testo in primo piano.")
        XCTAssertTrue(source.targetedStartPIDs.isEmpty, "Senza PID deve restare il percorso in primo piano")
        XCTAssertEqual(source.startCallCount, 1)
    }

    // MARK: - Range sorgente e callbacks (DSA-10)

    func testContinuousStartMapsAbsoluteRangesInImmediateChunksAndRemainder() async {
        let (state, cleanup) = makeState()
        defer { cleanup() }

        let documentID = UUID()
        let unit = "Questa è una frase di prova con 12,50 € e un numero. "
        let text = String(repeating: unit, count: 220)
        let base = SourceTextRange(location: 500, length: text.utf16.count)

        let source = FakeContinuousTextSource()
        source.startResults = [
            ContinuousCaptureStart(
                text: text,
                selectedText: "",
                canPage: false,
                sourceDocumentID: documentID,
                sourceRange: base,
                sourcePID: 42
            )
        ]

        let (controller, sink) = makeController(state: state, source: source)
        var started: [(UUID, pid_t)] = []
        var queueCountAtStart = -1
        var endedCount = 0
        controller.onSourceSessionStarted = { documentID, pid in
            started.append((documentID, pid))
            queueCountAtStart = state.readingQueue.count
        }
        controller.onSourceSessionEnded = { endedCount += 1 }

        let captured = await controller.captureAndPlay()

        XCTAssertNotNil(captured)
        XCTAssertEqual(started.count, 1, "La sessione sorgente parte una sola volta")
        XCTAssertEqual(started.first?.0, documentID)
        XCTAssertEqual(started.first?.1, 42)
        XCTAssertGreaterThan(queueCountAtStart, 0, "I chunk devono essere già in coda prima del callback")
        XCTAssertEqual(sink.playCallCount, 1)

        // Il prefisso immediato è mappato in assoluto e normalizzato senza
        // perdere il range: il testo diventa "12 euro e 50 centesimi".
        let immediate = state.readingQueue
        XCTAssertFalse(immediate.isEmpty)
        XCTAssertTrue(immediate.first?.text.contains("12 euro e 50 centesimi") == true)

        // Il resto del documento viene chunkato sullo stesso FilteredText.
        let appended = await controller.fetchNextPage()
        XCTAssertTrue(appended)
        XCTAssertGreaterThan(state.readingQueue.count, immediate.count)

        let nsText = text as NSString
        for chunk in state.readingQueue {
            XCTAssertEqual(chunk.sourceDocumentID, documentID)
            guard let range = chunk.sourceRange else {
                XCTFail("Chunk senza range: \(chunk.text)")
                continue
            }
            XCTAssertGreaterThanOrEqual(range.location, base.location)
            XCTAssertLessThanOrEqual(range.end, base.end)
            let slice = nsText.substring(
                with: NSRange(
                    location: range.location - base.location,
                    length: range.length
                )
            )
            XCTAssertEqual(slice, chunk.rawText)
            XCTAssertFalse(chunk.text.contains("12,50 €"), "Il testo TTS è normalizzato")
        }

        XCTAssertLessThan(
            immediate.last!.sourceRange!.location,
            state.readingQueue.last!.sourceRange!.location,
            "Il remainder deve stare dopo il prefisso"
        )

        controller.stopSession()
        XCTAssertEqual(endedCount, 1)
        controller.stopSession()
        XCTAssertEqual(endedCount, 1, "La chiusura della sessione sorgente è idempotente")
    }

    func testContinuousStartWithoutRangeLeavesChunksUnmappedAndSkipsSourceCallback() async {
        let (state, cleanup) = makeState()
        defer { cleanup() }

        let source = FakeContinuousTextSource()
        source.startResults = [
            ContinuousCaptureStart(
                text: "Prima frase. Seconda frase.",
                selectedText: "",
                canPage: false,
                sourceDocumentID: UUID(),
                sourceRange: nil,
                sourcePID: 42
            )
        ]

        let (controller, _) = makeController(state: state, source: source)
        var startedCount = 0
        var endedCount = 0
        controller.onSourceSessionStarted = { _, _ in startedCount += 1 }
        controller.onSourceSessionEnded = { endedCount += 1 }

        _ = await controller.captureAndPlay()

        XCTAssertEqual(startedCount, 0, "Senza range non si apre nessuna sessione di highlight")
        XCTAssertEqual(state.readingQueue.count, 2)
        for chunk in state.readingQueue {
            XCTAssertNil(chunk.sourceRange)
            XCTAssertNil(chunk.sourceDocumentID)
        }

        controller.stopSession()
        XCTAssertEqual(endedCount, 0, "Non c'era una sessione sorgente da chiudere")
    }

    // MARK: - Helper

    private func makeState() -> (AppState, () -> Void) {
        let suiteName = "LettoreTests.Continuous.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let preferences = PreferencesStore(defaults: defaults)
        preferences.isContinuousReadingEnabled = true
        preferences.isAutoPageEnabled = true

        let state = AppState(preferences: preferences)
        return (state, { defaults.removePersistentDomain(forName: suiteName) })
    }

    private func makeController(
        state: AppState,
        source: FakeContinuousTextSource
    ) -> (ContinuousReadingController, FakePlaybackSink) {
        let sink = FakePlaybackSink()
        let coordinator = PlaybackCoordinator(
            appState: state,
            audioEngine: AudioEngineService()
        )
        let controller = ContinuousReadingController(
            appState: state,
            coordinator: coordinator,
            source: source,
            playback: sink
        )
        return (controller, sink)
    }

    private func waitUntilPagingEnabled(
        _ controller: ContinuousReadingController,
        expected: Bool
    ) async {
        for _ in 0..<200 {
            if controller.isPagingEnabled == expected { return }
            await Task.yield()
        }
        XCTFail("pagingEnabled non aggiornato a \(expected)")
    }
}
