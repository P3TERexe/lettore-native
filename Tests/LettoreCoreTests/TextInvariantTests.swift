import XCTest
@testable import LettoreCore

final class TextInvariantTests: XCTestCase {

    private let chunker = SentenceChunker()

    // MARK: - Limite dei chunk

    func testChunkerNeverExceedsLimitWithoutPunctuation() {
        let text = String(repeating: "parola ", count: 200)

        let chunks = chunker.chunk(text: text)

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.text.count <= SentenceChunker.defaultMaxChunkLength })
    }

    func testChunkerSplitsASingleWordLongerThanTheLimit() {
        let text = String(repeating: "a", count: 1_000)

        let chunks = chunker.chunk(text: text)

        XCTAssertFalse(chunks.isEmpty)
        XCTAssertTrue(chunks.allSatisfy { $0.text.count <= SentenceChunker.defaultMaxChunkLength })
    }

    func testChunkerSplitsClausesThatAreEachLongerThanTheLimit() {
        let clause = String(repeating: "b", count: 300)
        let text = [clause, clause, clause].joined(separator: ", ")

        let chunks = chunker.chunk(text: text)

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.text.count <= SentenceChunker.defaultMaxChunkLength })
    }

    func testChunkerLimitCountsCharactersNotUTF16Units() {
        let text = String(repeating: "😀", count: 500)

        let chunks = chunker.chunk(text: text)

        XCTAssertFalse(chunks.isEmpty)
        XCTAssertTrue(chunks.allSatisfy { $0.text.count <= SentenceChunker.defaultMaxChunkLength })
    }

    func testNormalizationCannotPushAChunkOverTheLimit() {
        let preparer = ReadingTextPreparer()
        // Ogni "Es. " diventa "ad esempio ", allungando il testo oltre 240.
        let text = String(repeating: "Es. ", count: 60)

        let reading = preparer.prepareInitial(text: text, mode: .off)

        XCTAssertGreaterThan(reading.chunks.count, 1)
        XCTAssertTrue(
            reading.chunks.allSatisfy { $0.text.count <= SentenceChunker.defaultMaxChunkLength },
            "La normalizzazione non deve violare il contratto dei 240 caratteri"
        )
        XCTAssertTrue(
            reading.chunks.map(\.text).joined(separator: " ").contains("ad esempio"),
            "Le parti devono conservare il testo normalizzato"
        )
    }

    // MARK: - Overlap di pagina

    func testSingleCharacterCoincidenceIsNotTreatedAsOverlap() {
        let old = "Il treno arriva a"
        let new = "a Roma domani."

        XCTAssertEqual(DocumentPageOverlap.textAfterOverlap(old, new), new)
    }

    func testShortAccidentalCoincidenceIsNotTreatedAsOverlap() {
        let old = "Il testo termina con la lettera e"
        let new = "ecco la pagina nuova."

        XCTAssertEqual(DocumentPageOverlap.textAfterOverlap(old, new), new)
    }

    func testGenuineOverlapAtTheThresholdIsStillRemoved() {
        let old = "Prima parte, coda."
        let new = "coda. Parte nuova."

        XCTAssertEqual(DocumentPageOverlap.textAfterOverlap(old, new), " Parte nuova.")
    }
}
