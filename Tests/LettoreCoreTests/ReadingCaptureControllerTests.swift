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
        XCTAssertNil(state.continuationNotice)
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

    func testFailedContinuousCaptureFallsBackToQueueAndClearsNotice() async {
        let (state, cleanup) = makeState(queue: [makeChunk("Coda pronta.")])
        defer { cleanup() }
        state.lastExternalApplicationPID = 42
        state.continuationNotice = "Nessun testo leggibile nell'app in primo piano."

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
        XCTAssertNil(state.continuationNotice)
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
        selectedText: FakeSelectedTextCapture,
        sourceApplications: FakeSourceApplications,
        continuous: ContinuousCaptureSpy = ContinuousCaptureSpy()
    ) -> ReadingCaptureController {
        ReadingCaptureController(
            appState: state,
            selectedText: selectedText,
            sourceApplications: sourceApplications,
            continuousCapture: { applicationPID in
                await continuous.capture(from: applicationPID)
            }
        )
    }
}
