import XCTest
@testable import LettoreCore
@testable import LettoreSystem

@MainActor
final class SourceSelectionControllerTests: XCTestCase {

    // MARK: - Doppi di test

    actor FakeSourceHighlighter: SourceSelectionHighlighting, SourceSelectionChangeObserving {
        private(set) var writes: [SourceTextRange] = []
        private(set) var writtenDocumentIDs: [UUID] = []
        private(set) var endedDocumentIDs: [UUID] = []
        private(set) var observeCallCount = 0
        private(set) var stopObserveCallCount = 0
        var outcome: SourceHighlightOutcome = .applied

        private var observerHandler: (@Sendable () -> Void)?

        func highlightSourceRange(
            _ range: SourceTextRange,
            documentID: UUID
        ) async -> SourceHighlightOutcome {
            writes.append(range)
            writtenDocumentIDs.append(documentID)
            return outcome
        }

        func endSourceHighlight(documentID: UUID) async {
            endedDocumentIDs.append(documentID)
        }

        func observeSelectionChanges(
            documentID: UUID,
            onChange: @escaping @Sendable () -> Void
        ) async -> Bool {
            observeCallCount += 1
            observerHandler = onChange
            return true
        }

        func stopObservingSelectionChanges(documentID: UUID) async {
            stopObserveCallCount += 1
            observerHandler = nil
        }

        func fireUserSelectionChange() {
            observerHandler?()
        }
    }

    @MainActor
    final class FakeInputMonitor: SourceInputMonitoring {
        private var handler: (@Sendable @MainActor (SourceInputEvent) -> Void)?
        private(set) var startCount = 0
        private(set) var stopCount = 0

        func start(handler: @escaping @Sendable @MainActor (SourceInputEvent) -> Void) {
            self.handler = handler
            startCount += 1
        }

        func stop() {
            handler = nil
            stopCount += 1
        }

        func send(_ event: SourceInputEvent) {
            handler?(event)
        }
    }

    @MainActor
    final class FrontmostStub {
        var pid: pid_t?
    }

    @MainActor
    final class CallbackCounter {
        private(set) var value = 0

        func increment() {
            value += 1
        }
    }

    // MARK: - Policy di highlight

    func testToggleOffIsNoOpAndIgnoresInput() async {
        let harness = makeHarness(enabled: false, frontmostPID: 42)
        let documentID = UUID()

        await harness.controller.begin(documentID: documentID, sourcePID: 42)
        let outcome = await harness.controller.update(
            range: SourceTextRange(location: 10, length: 5),
            documentID: documentID
        )

        XCTAssertNil(outcome)
        let writes = await harness.highlighter.writes
        XCTAssertTrue(writes.isEmpty)

        harness.monitor.send(.keyDown)
        XCTAssertEqual(harness.counter.value, 0)

        await harness.controller.end()
    }

    func testUpdateForAnotherDocumentIsNoOp() async {
        let harness = makeHarness(frontmostPID: 42)
        let currentDocument = UUID()
        let otherDocument = UUID()

        await harness.controller.begin(documentID: currentDocument, sourcePID: 42)
        let outcome = await harness.controller.update(
            range: SourceTextRange(location: 5, length: 3),
            documentID: otherDocument
        )

        XCTAssertNil(outcome)
        let writes = await harness.highlighter.writes
        XCTAssertTrue(writes.isEmpty)

        await harness.controller.end()
    }

    func testSourceNotFrontmostSuspendsWithoutWriting() async {
        let harness = makeHarness(frontmostPID: 99)
        let documentID = UUID()

        await harness.controller.begin(documentID: documentID, sourcePID: 42)
        let outcome = await harness.controller.update(
            range: SourceTextRange(location: 20, length: 10),
            documentID: documentID
        )

        XCTAssertEqual(outcome, .suspended)
        let writes = await harness.highlighter.writes
        XCTAssertTrue(writes.isEmpty)

        await harness.controller.end()
    }

    func testFrontmostSourceWritesExpectedRange() async {
        let harness = makeHarness(frontmostPID: 42)
        let documentID = UUID()
        let range = SourceTextRange(location: 20, length: 10)

        await harness.controller.begin(documentID: documentID, sourcePID: 42)
        let outcome = await harness.controller.update(range: range, documentID: documentID)

        XCTAssertEqual(outcome, .applied)
        let writes = await harness.highlighter.writes
        XCTAssertEqual(writes, [range])
        let ids = await harness.highlighter.writtenDocumentIDs
        XCTAssertEqual(ids, [documentID])

        await harness.controller.end()
    }

    func testActivationReappliesLastRangeOnlyWhenSourceReturnsFrontmost() async {
        let harness = makeHarness(frontmostPID: 42)
        let documentID = UUID()
        let firstRange = SourceTextRange(location: 10, length: 4)
        let secondRange = SourceTextRange(location: 30, length: 8)

        await harness.controller.begin(documentID: documentID, sourcePID: 42)
        _ = await harness.controller.update(range: firstRange, documentID: documentID)

        harness.frontmost.pid = 99
        await harness.controller.handleApplicationActivation(pid: 99)
        var writes = await harness.highlighter.writes
        XCTAssertEqual(writes, [firstRange], "Il passaggio in background non deve riscrivere la selezione")

        _ = await harness.controller.update(range: secondRange, documentID: documentID)
        writes = await harness.highlighter.writes
        XCTAssertEqual(writes, [firstRange], "In background non si scrive")

        harness.frontmost.pid = 42
        await harness.controller.handleApplicationActivation(pid: 42)
        writes = await harness.highlighter.writes
        XCTAssertEqual(writes, [firstRange, secondRange], "Al ritorno frontmost si riapplica l'ultimo range")

        await harness.controller.end()
    }

    func testClearingLastRangePreventsReapplyOnActivation() async {
        let harness = makeHarness(frontmostPID: 42)
        let documentID = UUID()
        let range = SourceTextRange(location: 10, length: 4)

        await harness.controller.begin(documentID: documentID, sourcePID: 42)
        _ = await harness.controller.update(range: range, documentID: documentID)

        harness.controller.clearLastRange()
        harness.frontmost.pid = 99
        await harness.controller.handleApplicationActivation(pid: 99)
        harness.frontmost.pid = 42
        await harness.controller.handleApplicationActivation(pid: 42)

        let writes = await harness.highlighter.writes
        XCTAssertEqual(writes, [range], "Senza range corrente non si riapplica la frase precedente")

        await harness.controller.end()
    }

    // MARK: - Stop su input

    func testInputInSourceAppCallsCallbackOncePerSession() async {
        let harness = makeHarness(frontmostPID: 42)
        let documentID = UUID()

        await harness.controller.begin(documentID: documentID, sourcePID: 42)
        harness.monitor.send(.keyDown)
        harness.monitor.send(.leftMouseDown)
        harness.monitor.send(.leftMouseDragged)
        harness.monitor.send(.rightMouseDown)
        harness.monitor.send(.otherMouseDown)

        XCTAssertEqual(harness.counter.value, 1)

        let outcome = await harness.controller.update(
            range: SourceTextRange(location: 0, length: 1),
            documentID: documentID
        )
        XCTAssertNil(outcome, "Dopo l'interazione la sessione non applica più highlight")

        await harness.controller.end()
    }

    func testInputInAnotherAppDoesNotCallCallback() async {
        let harness = makeHarness(frontmostPID: 99)

        await harness.controller.begin(documentID: UUID(), sourcePID: 42)
        harness.monitor.send(.keyDown)

        XCTAssertEqual(harness.counter.value, 0)
        await harness.controller.end()
    }

    func testScrollDoesNotCallCallback() async {
        let harness = makeHarness(frontmostPID: 42)

        await harness.controller.begin(documentID: UUID(), sourcePID: 42)
        harness.monitor.send(.scrollWheel)

        XCTAssertEqual(harness.counter.value, 0)
        await harness.controller.end()
    }

    func testObserverSelectionChangeCallsCallbackOnce() async {
        let harness = makeHarness(frontmostPID: 42)
        let documentID = UUID()

        await harness.controller.begin(documentID: documentID, sourcePID: 42)
        let observeCount = await harness.highlighter.observeCallCount
        XCTAssertEqual(observeCount, 1)

        await harness.highlighter.fireUserSelectionChange()
        await harness.highlighter.fireUserSelectionChange()

        XCTAssertEqual(harness.counter.value, 1)
        await harness.controller.end()
    }

    // MARK: - Sessione singola e chiusura

    func testBeginReplacesPreviousSessionAndEndsIt() async {
        let harness = makeHarness(frontmostPID: 42)
        let firstDocument = UUID()
        let secondDocument = UUID()

        await harness.controller.begin(documentID: firstDocument, sourcePID: 42)
        await harness.controller.begin(documentID: secondDocument, sourcePID: 42)

        let ended = await harness.highlighter.endedDocumentIDs
        XCTAssertEqual(ended, [firstDocument])

        _ = await harness.controller.update(
            range: SourceTextRange(location: 3, length: 2),
            documentID: secondDocument
        )
        let ids = await harness.highlighter.writtenDocumentIDs
        XCTAssertEqual(ids, [secondDocument])

        await harness.controller.end()
    }

    func testEndStopsMonitorAndReleasesHighlightWithoutWriting() async {
        let harness = makeHarness(frontmostPID: 42)
        let documentID = UUID()

        await harness.controller.begin(documentID: documentID, sourcePID: 42)
        await harness.controller.end()

        XCTAssertGreaterThanOrEqual(harness.monitor.stopCount, 1)
        let ended = await harness.highlighter.endedDocumentIDs
        XCTAssertEqual(ended, [documentID])
        let writes = await harness.highlighter.writes
        XCTAssertTrue(writes.isEmpty, "La chiusura non deve deselezionare né scrivere")
    }

    // MARK: - Ritaglio UTF-16

    func testLeadingTrimCountUsesUTF16Units() {
        let raw = "  \nFrase 😀 finale."
        XCTAssertEqual(SourceTextTrimming.leadingUTF16Count(of: raw), 3)

        let noTrim = "Frase 😀 finale."
        XCTAssertEqual(SourceTextTrimming.leadingUTF16Count(of: noTrim), 0)
    }

    func testTrimmedSelectionRangeAdvancesBaseAndKeepsUTF16Length() {
        let selectedText = "  😀 ciao  "
        let selection = SourceTextRange(location: 100, length: 20)
        let trimmed = SourceTextTrimming.trimmedRange(
            selection: selection,
            selectedText: selectedText
        )

        XCTAssertEqual(trimmed.location, 102)
        XCTAssertEqual(trimmed.length, ("😀 ciao" as NSString).length)
    }

    // MARK: - Compatibilità metadati

    func testContinuousCaptureStartDefaultsAndSourceMetadata() {
        let legacy = ContinuousCaptureStart(text: "Testo.", selectedText: "")
        XCTAssertNil(legacy.sourceDocumentID)
        XCTAssertNil(legacy.sourceRange)
        XCTAssertNil(legacy.sourcePID)

        let documentID = UUID()
        let range = SourceTextRange(location: 42, length: 8)
        let mapped = ContinuousCaptureStart(
            text: "Testo.",
            selectedText: "",
            sourceDocumentID: documentID,
            sourceRange: range,
            sourcePID: 123
        )

        XCTAssertEqual(mapped.sourceDocumentID, documentID)
        XCTAssertEqual(mapped.sourceRange, range)
        XCTAssertEqual(mapped.sourcePID, 123)
    }

    // MARK: - Helper

    private struct Harness {
        let controller: SourceSelectionController
        let highlighter: FakeSourceHighlighter
        let monitor: FakeInputMonitor
        let frontmost: FrontmostStub
        let counter: CallbackCounter
    }

    private func makeHarness(
        enabled: Bool = true,
        frontmostPID: pid_t?
    ) -> Harness {
        let highlighter = FakeSourceHighlighter()
        let monitor = FakeInputMonitor()
        let frontmost = FrontmostStub()
        frontmost.pid = frontmostPID
        let counter = CallbackCounter()
        let isolatedCenter = NotificationCenter()

        let controller = SourceSelectionController(
            highlighter: highlighter,
            frontmostPID: { frontmost.pid },
            isEnabled: { enabled },
            onUserInteraction: { counter.increment() },
            inputMonitor: monitor,
            activationCenter: isolatedCenter
        )

        return Harness(
            controller: controller,
            highlighter: highlighter,
            monitor: monitor,
            frontmost: frontmost,
            counter: counter
        )
    }
}
