import XCTest
@testable import LettoreCore
@testable import LettoreEngine

@MainActor
final class ReadingCaptureControllerTests: XCTestCase {

    // MARK: - Fake

    actor FakeSelectedTextCapture: SelectedTextCapturing {
        let result: CapturedSelection?
        private(set) var requestedPIDs: [pid_t?] = []

        init(result: CapturedSelection?) {
            self.result = result
        }

        func captureSelectedText(from applicationPID: pid_t?) async -> CapturedSelection? {
            requestedPIDs.append(applicationPID)
            return result
        }
    }

    /// Cattura che sospende ogni richiesta finché il test non la rilascia:
    /// permette di invertire l'ordine di completamento di due richieste.
    actor GatedSelectedTextCapture: SelectedTextCapturing {
        private let results: [CapturedSelection?]
        private var nextIndex = 0
        private var continuations: [Int: CheckedContinuation<CapturedSelection?, Never>] = [:]

        init(results: [CapturedSelection?]) {
            self.results = results
        }

        var startedCount: Int { nextIndex }

        func captureSelectedText(from applicationPID: pid_t?) async -> CapturedSelection? {
            let index = nextIndex
            nextIndex += 1
            return await withCheckedContinuation { continuation in
                continuations[index] = continuation
            }
        }

        func release(_ index: Int) {
            guard let continuation = continuations.removeValue(forKey: index) else { return }
            continuation.resume(returning: results[index])
        }
    }

    @MainActor
    final class FakeSourceApplications: SourceApplicationProviding {
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

    @MainActor
    final class ContinuousCaptureSpy {
        var result: String?
        private(set) var requestedPIDs: [pid_t?] = []

        init(result: String? = nil) {
            self.result = result
        }

        func capture(from applicationPID: pid_t?) async -> String? {
            requestedPIDs.append(applicationPID)
            return result
        }
    }

    /// Cattura continua sospesa finché il test non la rilascia, per invertire
    /// l'ordine di completamento rispetto a una selezione.
    actor GatedContinuousCapture {
        private let results: [String?]
        private var nextIndex = 0
        private var continuations: [Int: CheckedContinuation<String?, Never>] = [:]

        init(results: [String?]) {
            self.results = results
        }

        var startedCount: Int { nextIndex }

        func capture(from applicationPID: pid_t?) async -> String? {
            let index = nextIndex
            nextIndex += 1
            return await withCheckedContinuation { continuation in
                continuations[index] = continuation
            }
        }

        func release(_ index: Int) {
            guard let continuation = continuations.removeValue(forKey: index) else { return }
            continuation.resume(returning: results[index])
        }
    }

    @MainActor
    final class ContinuousSessionSpy {
        var isActive = false
        private(set) var stopCount = 0

        func stop() {
            stopCount += 1
            isActive = false
        }
    }

    // MARK: - Play dalla UI

    func testValidSelectionReplacesQueueAndPreservesMappedRange() async {
        let documentID = UUID()
        let selection = CapturedSelection(
            text: "  Ciao mondo.  ",
            sourceDocumentID: documentID,
            sourceRange: SourceTextRange(location: 100, length: 20),
            sourcePID: 42
        )
        let (state, cleanup) = makeState(queue: [makeChunk("Vecchia coda.")])
        defer { cleanup() }
        state.lastExternalApplicationPID = 42
        state.continuationNotice = "Avviso vecchio"

        let capture = FakeSelectedTextCapture(result: selection)
        let applications = makeApplications(runningExternalPIDs: [42])
        let continuous = ContinuousCaptureSpy()
        let controller = makeController(
            state: state,
            selectedText: capture,
            sourceApplications: applications,
            continuous: continuous
        )

        let outcome = await controller.playFromUI(isContinuousEnabled: false)

        guard case .captured(let captured) = outcome else {
            return XCTFail("Atteso .captured, ricevuto \(outcome)")
        }
        XCTAssertEqual(captured.text, selection.text)
        let requestedPIDs = await capture.requestedPIDs
        XCTAssertEqual(requestedPIDs, [42])
        XCTAssertTrue(continuous.requestedPIDs.isEmpty, "La modalità selezione non chiama la cattura continua")
        XCTAssertEqual(state.readingQueue.map(\.text), ["Ciao mondo."])
        XCTAssertEqual(
            state.readingQueue.first?.sourceRange,
            SourceTextRange(location: 102, length: 11),
            "Il range sorgente deve partire dopo i due spazi iniziali"
        )
        XCTAssertEqual(state.readingQueue.first?.sourceDocumentID, documentID)
        XCTAssertNil(state.continuationNotice)
        XCTAssertEqual(state.capturedDocumentText, "")
    }

    func testEmptySelectionFallsBackToQueueWhenAvailable() async {
        let (state, cleanup) = makeState(queue: [makeChunk("Coda pronta.")])
        defer { cleanup() }
        state.lastExternalApplicationPID = 42

        let capture = FakeSelectedTextCapture(result: CapturedSelection(text: "   \n"))
        let applications = makeApplications(runningExternalPIDs: [42])
        let controller = makeController(
            state: state,
            selectedText: capture,
            sourceApplications: applications
        )

        let outcome = await controller.playFromUI(isContinuousEnabled: false)

        guard case .fellBackToQueue = outcome else {
            return XCTFail("Atteso .fellBackToQueue, ricevuto \(outcome)")
        }
        XCTAssertEqual(state.continuationNotice, "Nessuna selezione leggibile.")
        XCTAssertEqual(state.readingQueue.map(\.text), ["Coda pronta."])
        let requestedPIDs = await capture.requestedPIDs
        XCTAssertEqual(requestedPIDs, [42])
    }

    func testEmptySelectionWhilePlayingDoesNotReplacePlaybackWithQueue() async {
        let (state, cleanup) = makeState(queue: [makeChunk("Coda pronta.")])
        defer { cleanup() }
        state.lastExternalApplicationPID = 42
        state.playbackState = .playing

        let capture = FakeSelectedTextCapture(result: CapturedSelection(text: "  "))
        let applications = makeApplications(runningExternalPIDs: [42])
        let controller = makeController(
            state: state,
            selectedText: capture,
            sourceApplications: applications
        )

        let outcome = await controller.playFromUI(isContinuousEnabled: false)

        guard case .unavailable(let reason) = outcome else {
            return XCTFail("Durante il playback non si riprende la coda, ricevuto \(outcome)")
        }
        XCTAssertEqual(state.continuationNotice, reason)
        XCTAssertEqual(state.readingQueue.map(\.text), ["Coda pronta."])
    }

    func testOlderSelectionCannotReplaceNewerQueue() async {
        let (state, cleanup) = makeState(queue: [makeChunk("Coda iniziale.")])
        defer { cleanup() }
        state.lastExternalApplicationPID = 42

        let capture = GatedSelectedTextCapture(results: [
            CapturedSelection(text: "Selezione vecchia."),
            CapturedSelection(text: "Selezione nuova.")
        ])
        let applications = makeApplications(runningExternalPIDs: [42])
        let controller = makeController(
            state: state,
            selectedText: capture,
            sourceApplications: applications
        )

        let first = Task { await controller.playFromUI(isContinuousEnabled: false) }
        let firstStarted = await waitUntil { await capture.startedCount == 1 }
        XCTAssertTrue(firstStarted)

        let second = Task { await controller.playFromUI(isContinuousEnabled: false) }
        let secondStarted = await waitUntil { await capture.startedCount == 2 }
        XCTAssertTrue(secondStarted)

        // La richiesta nuova completa per prima...
        await capture.release(1)
        let secondOutcome = await second.value
        guard case .captured = secondOutcome else {
            return XCTFail("Atteso .captured dalla richiesta nuova, ricevuto \(secondOutcome)")
        }
        XCTAssertEqual(state.readingQueue.map(\.text), ["Selezione nuova."])

        // ...poi completa la vecchia, che non deve sovrascrivere la coda.
        await capture.release(0)
        let firstOutcome = await first.value
        guard case .unavailable = firstOutcome else {
            return XCTFail("La cattura superata deve essere scartata, ricevuto \(firstOutcome)")
        }
        XCTAssertEqual(state.readingQueue.map(\.text), ["Selezione nuova."])
    }

    func testOlderSelectionCannotReplaceNewerContinuousQueue() async {
        let (state, cleanup) = makeState(queue: [makeChunk("Coda iniziale.")])
        defer { cleanup() }
        state.lastExternalApplicationPID = 42

        let selectionCapture = GatedSelectedTextCapture(results: [
            CapturedSelection(text: "Selezione vecchia.")
        ])
        let continuousCapture = GatedContinuousCapture(results: ["Documento continuo."])
        let session = ContinuousSessionSpy()
        let applications = makeApplications(runningExternalPIDs: [42])
        let controller = makeController(
            state: state,
            selectedText: selectionCapture,
            sourceApplications: applications,
            continuousCapture: { _ in
                session.isActive = true
                let text = await continuousCapture.capture(from: nil)
                guard session.isActive else { return nil }
                if let text {
                    state.setQueue([ReadingChunk(index: 0, text: text)])
                }
                return text
            },
            cancelContinuousSession: { session.stop() }
        )

        // La selezione parte per prima ma è più lenta della lettura continua.
        let selectionTask = Task { await controller.playFromUI(isContinuousEnabled: false) }
        let selectionStarted = await waitUntil { await selectionCapture.startedCount == 1 }
        XCTAssertTrue(selectionStarted)

        let continuousTask = Task { await controller.playFromUI(isContinuousEnabled: true) }
        let continuousStarted = await waitUntil { await continuousCapture.startedCount == 1 }
        XCTAssertTrue(continuousStarted)

        await continuousCapture.release(0)
        let continuousOutcome = await continuousTask.value
        guard case .continuous = continuousOutcome else {
            return XCTFail("Atteso .continuous, ricevuto \(continuousOutcome)")
        }
        XCTAssertEqual(state.readingQueue.map(\.text), ["Documento continuo."])

        await selectionCapture.release(0)
        let selectionOutcome = await selectionTask.value
        guard case .unavailable = selectionOutcome else {
            return XCTFail("La selezione superata deve essere scartata, ricevuto \(selectionOutcome)")
        }
        XCTAssertEqual(
            state.readingQueue.map(\.text),
            ["Documento continuo."],
            "La selezione vecchia non deve sostituire la coda della lettura continua nuova"
        )
    }

    func testNewerSelectionStopsContinuousAndKeepsItsOwnQueue() async {
        let (state, cleanup) = makeState(queue: [makeChunk("Coda iniziale.")])
        defer { cleanup() }
        state.lastExternalApplicationPID = 42

        let selectionCapture = FakeSelectedTextCapture(
            result: CapturedSelection(text: "Selezione nuova.")
        )
        let continuousCapture = GatedContinuousCapture(results: ["Documento vecchio."])
        let session = ContinuousSessionSpy()
        let applications = makeApplications(runningExternalPIDs: [42])
        let controller = makeController(
            state: state,
            selectedText: selectionCapture,
            sourceApplications: applications,
            continuousCapture: { _ in
                session.isActive = true
                let text = await continuousCapture.capture(from: nil)
                guard session.isActive else { return nil }
                if let text {
                    state.setQueue([ReadingChunk(index: 0, text: text)])
                }
                return text
            },
            cancelContinuousSession: { session.stop() }
        )

        let continuousTask = Task { await controller.playFromUI(isContinuousEnabled: true) }
        let continuousStarted = await waitUntil { await continuousCapture.startedCount == 1 }
        XCTAssertTrue(continuousStarted)
        XCTAssertTrue(session.isActive)

        let selectionOutcome = await controller.playFromUI(isContinuousEnabled: false)
        guard case .captured = selectionOutcome else {
            return XCTFail("Atteso .captured, ricevuto \(selectionOutcome)")
        }
        XCTAssertFalse(session.isActive, "La selezione deve fermare la sessione continua in volo")
        XCTAssertEqual(state.readingQueue.map(\.text), ["Selezione nuova."])

        await continuousCapture.release(0)
        let continuousOutcome = await continuousTask.value
        guard case .unavailable = continuousOutcome else {
            return XCTFail("La continua superata deve essere scartata, ricevuto \(continuousOutcome)")
        }
        XCTAssertEqual(
            state.readingQueue.map(\.text),
            ["Selezione nuova."],
            "La cattura continua vecchia non deve rimpiazzare la selezione nuova"
        )
    }

    func testStaleSelectionFailureDoesNotClearNewerContinuousNotice() async {
        let (state, cleanup) = makeState(queue: [makeChunk("Coda iniziale.")])
        defer { cleanup() }
        state.lastExternalApplicationPID = 42

        let selectionCapture = GatedSelectedTextCapture(results: [nil])
        let applications = makeApplications(runningExternalPIDs: [42])
        let controller = makeController(
            state: state,
            selectedText: selectionCapture,
            sourceApplications: applications,
            continuousCapture: { _ in
                state.continuationNotice = "Lettura continua attiva."
                state.setQueue([ReadingChunk(index: 0, text: "Documento continuo.")])
                return "Documento continuo."
            }
        )

        let selectionTask = Task { await controller.playFromUI(isContinuousEnabled: false) }
        let selectionStarted = await waitUntil { await selectionCapture.startedCount == 1 }
        XCTAssertTrue(selectionStarted)

        let continuousOutcome = await controller.playFromUI(isContinuousEnabled: true)
        guard case .continuous = continuousOutcome else {
            return XCTFail("Atteso .continuous, ricevuto \(continuousOutcome)")
        }

        await selectionCapture.release(0)
        let selectionOutcome = await selectionTask.value
        guard case .unavailable = selectionOutcome else {
            return XCTFail("La cattura superata deve essere scartata, ricevuto \(selectionOutcome)")
        }
        XCTAssertEqual(
            state.continuationNotice,
            "Lettura continua attiva.",
            "Un fallback vecchio non deve cancellare l'avviso della richiesta nuova"
        )
        XCTAssertEqual(state.readingQueue.map(\.text), ["Documento continuo."])
    }

    func testManualRequestStopsContinuousSessionAndInvalidatesCapture() async {
        let (state, cleanup) = makeState()
        defer { cleanup() }
        state.lastExternalApplicationPID = 42

        let selectionCapture = GatedSelectedTextCapture(results: [
            CapturedSelection(text: "Selezione superata.")
        ])
        let session = ContinuousSessionSpy()
        session.isActive = true
        let applications = makeApplications(runningExternalPIDs: [42])
        let controller = makeController(
            state: state,
            selectedText: selectionCapture,
            sourceApplications: applications,
            cancelContinuousSession: { session.stop() }
        )

        let selectionTask = Task { await controller.playFromUI(isContinuousEnabled: false) }
        let selectionStarted = await waitUntil { await selectionCapture.startedCount == 1 }
        XCTAssertTrue(selectionStarted)

        let manualToken = controller.beginManualReadingRequest()
        XCTAssertTrue(controller.isCurrentReadingRequest(manualToken))
        XCTAssertFalse(session.isActive, "L'input manuale deve fermare la sessione continua")
        XCTAssertEqual(session.stopCount, 2, "Una volta per la selezione e una per l'input manuale")

        await selectionCapture.release(0)
        let outcome = await selectionTask.value
        guard case .unavailable = outcome else {
            return XCTFail("La selezione superata dall'input manuale deve essere scartata, ricevuto \(outcome)")
        }
        XCTAssertTrue(state.readingQueue.isEmpty)
    }

    func testInvalidSourceDuringContinuousCaptureStopsTheSession() async {
        let (state, cleanup) = makeState()
        defer { cleanup() }
        state.lastExternalApplicationPID = 42

        let selectionCapture = FakeSelectedTextCapture(result: nil)
        let continuousCapture = GatedContinuousCapture(results: ["Documento in volo."])
        let session = ContinuousSessionSpy()
        let applications = makeApplications(runningExternalPIDs: [42])
        let controller = makeController(
            state: state,
            selectedText: selectionCapture,
            sourceApplications: applications,
            continuousCapture: { _ in
                session.isActive = true
                let text = await continuousCapture.capture(from: nil)
                guard session.isActive else { return nil }
                if let text {
                    state.setQueue([ReadingChunk(index: 0, text: text)])
                }
                return text
            },
            cancelContinuousSession: { session.stop() }
        )

        let continuousTask = Task { await controller.playFromUI(isContinuousEnabled: true) }
        let started = await waitUntil { await continuousCapture.startedCount == 1 }
        XCTAssertTrue(started)
        XCTAssertTrue(session.isActive)

        // La UI perde l'app di origine mentre la cattura continua è in volo.
        state.lastExternalApplicationPID = nil
        let invalidOutcome = await controller.playFromUI(isContinuousEnabled: false)
        guard case .unavailable = invalidOutcome else {
            return XCTFail("Atteso .unavailable, ricevuto \(invalidOutcome)")
        }
        XCTAssertEqual(
            session.stopCount,
            2,
            "Anche una richiesta che fallisce prima della cattura deve fermare la continua"
        )
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(
            state.continuationNotice,
            ReadingCaptureController.missingSourceApplicationNotice
        )

        await continuousCapture.release(0)
        let continuousOutcome = await continuousTask.value
        guard case .unavailable = continuousOutcome else {
            return XCTFail("La continua superata deve essere scartata, ricevuto \(continuousOutcome)")
        }
        XCTAssertTrue(state.readingQueue.isEmpty)
        XCTAssertEqual(
            state.continuationNotice,
            ReadingCaptureController.missingSourceApplicationNotice,
            "La cattura vecchia non deve cancellare l'avviso della richiesta nuova"
        )
    }

    // MARK: - App di origine

    func testInvalidExternalPIDFallsBackToQueueWhenAvailable() async {
        let (state, cleanup) = makeState(queue: [makeChunk("Coda pronta.")])
        defer { cleanup() }
        state.lastExternalApplicationPID = 77
        state.continuationNotice = "Avviso vecchio"

        let capture = FakeSelectedTextCapture(result: nil)
        let applications = makeApplications(runningExternalPIDs: [42])
        let controller = makeController(
            state: state,
            selectedText: capture,
            sourceApplications: applications
        )

        let outcome = await controller.playFromUI(isContinuousEnabled: false)

        guard case .fellBackToQueue = outcome else {
            return XCTFail("Atteso .fellBackToQueue, ricevuto \(outcome)")
        }
        XCTAssertEqual(
            state.continuationNotice,
            ReadingCaptureController.missingSourceApplicationNotice
        )
        let requestedPIDs = await capture.requestedPIDs
        XCTAssertTrue(requestedPIDs.isEmpty, "Un PID invalido non deve arrivare alla cattura")
        XCTAssertEqual(state.readingQueue.map(\.text), ["Coda pronta."])
    }

    func testEmptySelectionWithoutQueueShowsMessage() async {
        let (state, cleanup) = makeState()
        defer { cleanup() }
        state.lastExternalApplicationPID = 42

        let capture = FakeSelectedTextCapture(result: nil)
        let applications = makeApplications(runningExternalPIDs: [42])
        let controller = makeController(
            state: state,
            selectedText: capture,
            sourceApplications: applications
        )

        let outcome = await controller.playFromUI(isContinuousEnabled: false)

        guard case .unavailable(let reason) = outcome else {
            return XCTFail("Atteso .unavailable, ricevuto \(outcome)")
        }
        XCTAssertEqual(state.continuationNotice, reason)
        XCTAssertTrue(state.readingQueue.isEmpty)
    }

    func testMissingSourceApplicationWithoutQueueShowsMessage() async {
        let (state, cleanup) = makeState()
        defer { cleanup() }

        let capture = FakeSelectedTextCapture(result: nil)
        let applications = makeApplications(runningExternalPIDs: [])
        let controller = makeController(
            state: state,
            selectedText: capture,
            sourceApplications: applications
        )

        let outcome = await controller.playFromUI(isContinuousEnabled: false)

        guard case .unavailable(let reason) = outcome else {
            return XCTFail("Atteso .unavailable, ricevuto \(outcome)")
        }
        XCTAssertEqual(reason, ReadingCaptureController.missingSourceApplicationNotice)
        XCTAssertEqual(state.continuationNotice, ReadingCaptureController.missingSourceApplicationNotice)
        XCTAssertTrue(state.readingQueue.isEmpty)
        let requestedPIDs = await capture.requestedPIDs
        XCTAssertTrue(requestedPIDs.isEmpty)
    }

    // MARK: - Lettura continua

    func testContinuousCaptureDoesNotTouchTheQueue() async {
        let (state, cleanup) = makeState(queue: [makeChunk("Coda pronta.")])
        defer { cleanup() }
        state.lastExternalApplicationPID = 42

        let capture = FakeSelectedTextCapture(result: nil)
        let applications = makeApplications(runningExternalPIDs: [42])
        let continuous = ContinuousCaptureSpy(result: "Testo continuo.")
        let controller = makeController(
            state: state,
            selectedText: capture,
            sourceApplications: applications,
            continuous: continuous
        )

        let outcome = await controller.playFromUI(isContinuousEnabled: true)

        guard case .continuous(let text) = outcome else {
            return XCTFail("Atteso .continuous, ricevuto \(outcome)")
        }
        XCTAssertEqual(text, "Testo continuo.")
        XCTAssertEqual(state.readingQueue.map(\.text), ["Coda pronta."])
        XCTAssertEqual(continuous.requestedPIDs, [42])
        let requestedPIDs = await capture.requestedPIDs
        XCTAssertTrue(requestedPIDs.isEmpty, "La modalità continua non passa dalla selezione")
    }

    func testFailedContinuousCaptureFallsBackToQueueAndKeepsNotice() async {
        let (state, cleanup) = makeState(queue: [makeChunk("Coda pronta.")])
        defer { cleanup() }
        state.lastExternalApplicationPID = 42
        let reason = "Nessun testo leggibile nell'app in primo piano."
        state.continuationNotice = reason

        let capture = FakeSelectedTextCapture(result: nil)
        let applications = makeApplications(runningExternalPIDs: [42])
        let continuous = ContinuousCaptureSpy(result: nil)
        let controller = makeController(
            state: state,
            selectedText: capture,
            sourceApplications: applications,
            continuous: continuous
        )

        let outcome = await controller.playFromUI(isContinuousEnabled: true)

        guard case .fellBackToQueue = outcome else {
            return XCTFail("Atteso .fellBackToQueue, ricevuto \(outcome)")
        }
        XCTAssertEqual(state.continuationNotice, reason)
        XCTAssertEqual(state.readingQueue.map(\.text), ["Coda pronta."])
    }

    // MARK: - Scorciatoia globale contro UI

    func testCaptureFromFrontmostUsesNilPIDWhenAnotherAppIsActive() async {
        let selection = CapturedSelection(text: "Selezione esterna.")
        let (state, cleanup) = makeState()
        defer { cleanup() }
        state.lastExternalApplicationPID = 42

        let capture = FakeSelectedTextCapture(result: selection)
        let applications = makeApplications(
            frontmostApplicationPID: 42,
            runningExternalPIDs: [42]
        )
        let controller = makeController(
            state: state,
            selectedText: capture,
            sourceApplications: applications
        )

        let outcome = await controller.captureFromFrontmost(isContinuousEnabled: false)

        guard case .captured = outcome else {
            return XCTFail("Atteso .captured, ricevuto \(outcome)")
        }
        let requestedPIDs = await capture.requestedPIDs
        XCTAssertEqual(requestedPIDs, [nil])
    }

    func testCaptureFromFrontmostUsesValidatedExternalPIDWhenLettoreIsActive() async {
        let selection = CapturedSelection(text: "Selezione esterna.")
        let (state, cleanup) = makeState()
        defer { cleanup() }
        state.lastExternalApplicationPID = 42

        let capture = FakeSelectedTextCapture(result: selection)
        let applications = makeApplications(
            frontmostApplicationPID: 900,
            runningExternalPIDs: [42]
        )
        let controller = makeController(
            state: state,
            selectedText: capture,
            sourceApplications: applications
        )

        let outcome = await controller.captureFromFrontmost(isContinuousEnabled: false)

        guard case .captured = outcome else {
            return XCTFail("Atteso .captured, ricevuto \(outcome)")
        }
        let requestedPIDs = await capture.requestedPIDs
        XCTAssertEqual(requestedPIDs, [42])
    }

    // MARK: - Helper

    private func makeState(queue: [ReadingChunk] = []) -> (AppState, () -> Void) {
        let suiteName = "LettoreTests.Capture.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let preferences = PreferencesStore(defaults: defaults)
        preferences.isContinuousReadingEnabled = false
        preferences.isAutoPageEnabled = false

        let state = AppState(preferences: preferences)
        if !queue.isEmpty {
            state.setQueue(queue)
        }
        return (state, { defaults.removePersistentDomain(forName: suiteName) })
    }

    private func makeChunk(_ text: String) -> ReadingChunk {
        ReadingChunk(index: 0, text: text)
    }

    private func makeApplications(
        frontmostApplicationPID: pid_t? = nil,
        runningExternalPIDs: Set<pid_t> = []
    ) -> FakeSourceApplications {
        let applications = FakeSourceApplications()
        applications.frontmostApplicationPID = frontmostApplicationPID
        applications.runningExternalPIDs = runningExternalPIDs
        return applications
    }

    private func makeController(
        state: AppState,
        selectedText: any SelectedTextCapturing,
        sourceApplications: FakeSourceApplications,
        continuous: ContinuousCaptureSpy = ContinuousCaptureSpy(),
        continuousCapture: ReadingCaptureController.ContinuousCapture? = nil,
        cancelContinuousSession: @escaping ReadingCaptureController.ContinuousSessionCancellation = {}
    ) -> ReadingCaptureController {
        ReadingCaptureController(
            appState: state,
            selectedText: selectedText,
            sourceApplications: sourceApplications,
            continuousCapture: continuousCapture ?? { applicationPID in
                await continuous.capture(from: applicationPID)
            },
            cancelContinuousSession: cancelContinuousSession
        )
    }

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
}
