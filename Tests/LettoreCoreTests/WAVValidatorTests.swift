import XCTest
@testable import LettoreEngine

final class WAVValidatorTests: XCTestCase {

    func testAcceptsGeneratedWAV() {
        XCTAssertTrue(WAVValidator.isValid(TestWAV.data()))
    }

    func testRejectsNonWAVPayload() {
        XCTAssertFalse(WAVValidator.isValid(Data("{\"detail\":\"errore\"}".utf8)))
        XCTAssertFalse(WAVValidator.isValid(Data()))
    }

    func testRejectsTruncatedWAV() {
        var data = TestWAV.data()
        data.removeLast(8)

        XCTAssertFalse(WAVValidator.isValid(data))
    }

    func testRejectsPayloadWithoutAudioData() {
        var data = TestWAV.data()
        guard let marker = data.range(of: Data("data".utf8)) else {
            XCTFail("Chunk data non trovato nel WAV di test")
            return
        }

        // Dichiara un chunk data vuoto lasciando intatto l'header.
        let sizeStart = data.index(marker.lowerBound, offsetBy: 4)
        let sizeEnd = data.index(sizeStart, offsetBy: 4)
        data.replaceSubrange(sizeStart..<sizeEnd, with: Data(repeating: 0, count: 4))

        XCTAssertFalse(WAVValidator.isValid(data))
    }
}
