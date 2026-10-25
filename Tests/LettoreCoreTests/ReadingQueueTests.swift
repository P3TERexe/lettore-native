import XCTest
@testable import LettoreCore

final class ReadingQueueTests: XCTestCase {

    private func chunk(_ text: String, index: Int = 0) -> ReadingChunk {
        ReadingChunk(index: index, text: text)
    }

    func testEmptyQueueHasNoCurrentAndZeroProgress() {
        let queue = ReadingQueue()

        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.current)
        XCTAssertEqual(queue.progress, 0)
    }

    func testReplaceSelectsFirstChunk() {
        var queue = ReadingQueue()
        queue.replace([chunk("Prima", index: 0), chunk("Seconda", index: 1)])

        XCTAssertEqual(queue.current?.text, "Prima")
        XCTAssertEqual(queue.progress, 0)
        XCTAssertEqual(queue.count, 2)
    }

    func testAppendReindexesPreservesIdentityAndDoesNotMoveCurrent() {
        var queue = ReadingQueue(chunks: [chunk("Prima", index: 0)])
        queue.replace([chunk("Prima", index: 0)])
        let currentID = queue.current?.id

        let appended = queue.append([chunk("Seconda", index: 0), chunk("Terza", index: 1)])

        XCTAssertEqual(appended.map(\.index), [1, 2])
        XCTAssertEqual(queue.chunks.map(\.index), [0, 1, 2])
        XCTAssertEqual(queue.current?.id, currentID)
        XCTAssertEqual(queue.progress, 0)
    }

    func testAppendAfterFinishResumesFirstNewChunk() {
        var queue = ReadingQueue()
        queue.replace([chunk("Unica", index: 0)])
        _ = queue.advance()
        XCTAssertNil(queue.current)
        XCTAssertEqual(queue.progress, 1)

        let appended = queue.append([chunk("Pagina due", index: 0)])

        XCTAssertEqual(queue.current?.id, appended[0].id)
        XCTAssertEqual(queue.current?.index, 1)
        XCTAssertEqual(queue.progress, 1.0 / 2.0, accuracy: 0.0001)
    }

    func testAdvanceAtEndClearsCurrentAndReportsFinished() {
        var queue = ReadingQueue()
        queue.replace([chunk("Prima", index: 0), chunk("Seconda", index: 1)])

        XCTAssertEqual(queue.advance()?.text, "Seconda")
        XCTAssertEqual(queue.progress, 0.5)
        XCTAssertNil(queue.advance())
        XCTAssertNil(queue.current)
        XCTAssertEqual(queue.progress, 1)
    }

    func testAdvanceOnEmptyQueueIsNoOp() {
        var queue = ReadingQueue()

        XCTAssertNil(queue.advance())
        XCTAssertEqual(queue.progress, 0)
    }

    func testRewindAtStartStaysOnFirstChunk() {
        var queue = ReadingQueue()
        queue.replace([chunk("Prima", index: 0), chunk("Seconda", index: 1)])

        XCTAssertEqual(queue.rewind()?.text, "Prima")
        XCTAssertEqual(queue.rewind()?.text, "Prima")
        XCTAssertEqual(queue.progress, 0)
    }

    func testRewindOnFinishedQueueIsNoOp() {
        var queue = ReadingQueue()
        queue.replace([chunk("Prima", index: 0)])
        _ = queue.advance()

        XCTAssertNil(queue.rewind())
        XCTAssertNil(queue.current)
    }

    func testSelectByIdAndIndex() {
        var queue = ReadingQueue()
        let first = chunk("Prima", index: 0)
        let second = chunk("Seconda", index: 1)
        queue.replace([first, second])

        XCTAssertEqual(queue.select(id: second.id)?.text, "Seconda")
        XCTAssertEqual(queue.progress, 0.5)
        XCTAssertEqual(queue.select(index: 0)?.text, "Prima")
        XCTAssertEqual(queue.progress, 0)
    }

    func testSelectUnknownIDDoesNotChangeCurrent() {
        var queue = ReadingQueue()
        queue.replace([chunk("Prima", index: 0), chunk("Seconda", index: 1)])

        XCTAssertNil(queue.select(id: UUID()))
        XCTAssertEqual(queue.current?.index, 0)
    }

    func testSelectOutOfBoundsDoesNotChangeCurrent() {
        var queue = ReadingQueue()
        queue.replace([chunk("Prima", index: 0)])

        XCTAssertNil(queue.select(index: 3))
        XCTAssertEqual(queue.current?.index, 0)
    }
}
