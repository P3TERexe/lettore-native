import XCTest
@testable import LettoreCore

final class ReadingTextPreparerTests: XCTestCase {

    private let preparer = ReadingTextPreparer()

    // MARK: - Testo manuale e selezione

    func testManualTextIsChunkedBeforeNormalization() {
        let text = "Il costo è 50 €. Poi continua."
        let reading = preparer.prepareInitial(text: text, mode: .off)

        XCTAssertEqual(reading.displayText, text)
        XCTAssertEqual(reading.chunks.map(\.text), ["Il costo è 50 euro.", "Poi continua."])
        XCTAssertTrue(reading.chunks.allSatisfy { $0.sourceRange == nil })
        XCTAssertFalse(reading.hasRemainder)
    }

    func testSelectionRangesAreAbsolute() {
        let text = "Prima frase. Seconda frase."
        let base = SourceTextRange(location: 1_000, length: text.utf16.count)
        let documentID = UUID()

        let reading = preparer.prepareInitial(
            text: text,
            sourceRange: base,
            sourceDocumentID: documentID,
            mode: .off
        )

        XCTAssertEqual(reading.chunks.count, 2)
        XCTAssertEqual(reading.chunks[0].sourceRange, SourceTextRange(location: 1_000, length: "Prima frase.".utf16.count))
        let secondOffset = (text as NSString).range(of: "Seconda frase.").location
        XCTAssertEqual(
            reading.chunks[1].sourceRange,
            SourceTextRange(location: 1_000 + secondOffset, length: "Seconda frase.".utf16.count)
        )
        XCTAssertTrue(reading.chunks.allSatisfy { $0.sourceDocumentID == documentID })
    }

    func testNormalizationDoesNotMoveSourceRanges() {
        let text = "Costa 50 € in tutto. Poi basta."
        let base = SourceTextRange(location: 7, length: text.utf16.count)

        let reading = preparer.prepareInitial(
            text: text,
            sourceRange: base,
            sourceDocumentID: UUID(),
            mode: .off
        )

        let first = reading.chunks[0]
        let expectedRange = (text as NSString).range(of: "Costa 50 € in tutto.")
        XCTAssertEqual(first.text, "Costa 50 euro in tutto.")
        XCTAssertEqual(first.rawText, "Costa 50 € in tutto.")
        XCTAssertEqual(first.sourceRange, SourceTextRange(location: 7 + expectedRange.location, length: expectedRange.length))
    }

    func testManualAndSelectionShareChunkBoundaries() {
        let text = "Es. una prima frase. Seconda frase con 50 € e un link https://example.com."
        let manual = preparer.prepareInitial(text: text, mode: .off)
        let selection = preparer.prepareInitial(
            text: text,
            sourceRange: SourceTextRange(location: 42, length: text.utf16.count),
            sourceDocumentID: UUID(),
            mode: .off
        )

        XCTAssertEqual(manual.chunks.map(\.text), selection.chunks.map(\.text))
        XCTAssertEqual(manual.chunks.count, selection.chunks.count)
    }

    // MARK: - Split iniziale e remainder

    func testInitialSplitProducesRemainderWithAbsoluteRanges() {
        let text = "Prima frase. Seconda frase. Terza frase."
        let base = SourceTextRange(location: 500, length: text.utf16.count)
        let documentID = UUID()

        let reading = preparer.prepareInitial(
            text: text,
            sourceRange: base,
            sourceDocumentID: documentID,
            mode: .off,
            maxImmediateLength: 14
        )

        XCTAssertTrue(reading.hasRemainder)
        XCTAssertFalse(reading.chunks.isEmpty)

        let remainder = preparer.prepareRemainder(of: reading)
        XCTAssertFalse(remainder.isEmpty)

        let all = reading.chunks + remainder
        XCTAssertEqual(all.map(\.text), ["Prima frase.", "Seconda frase.", "Terza frase."])

        let secondOffset = (text as NSString).range(of: "Seconda frase.").location
        let thirdOffset = (text as NSString).range(of: "Terza frase.").location
        XCTAssertEqual(all[1].sourceRange?.location, 500 + secondOffset)
        XCTAssertEqual(all[2].sourceRange?.location, 500 + thirdOffset)
        XCTAssertTrue(all.allSatisfy { $0.sourceDocumentID == documentID })
    }

    func testTextThatFitsHasNoRemainder() {
        let reading = preparer.prepareInitial(
            text: "Una sola frase.",
            mode: .off,
            maxImmediateLength: 8_000
        )

        XCTAssertFalse(reading.hasRemainder)
        XCTAssertTrue(preparer.prepareRemainder(of: reading).isEmpty)
    }

    func testNonPositiveLimitDisablesSplit() {
        let reading = preparer.prepareInitial(
            text: "Prima frase. Seconda frase.",
            mode: .off,
            maxImmediateLength: 0
        )

        XCTAssertFalse(reading.hasRemainder)
        XCTAssertEqual(reading.chunks.count, 2)
    }

    // MARK: - Filtro e paging

    func testFilteredRangesStillPointAtOriginalDocument() {
        let text = """
        Titolo corrente

        Prima frase sul documento.

        Titolo corrente

        Seconda frase sul documento.

        Titolo corrente

        Terza frase sul documento.
        """

        let reading = preparer.prepareInitial(
            text: text,
            sourceRange: SourceTextRange(location: 0, length: text.utf16.count),
            sourceDocumentID: UUID(),
            mode: .light,
            maxImmediateLength: 30
        )
        let all = reading.chunks + preparer.prepareRemainder(of: reading)

        XCTAssertFalse(all.isEmpty)
        XCTAssertFalse(all.map(\.text).joined(separator: " ").contains("Titolo corrente"))

        let nsText = text as NSString
        var searchStart = 0
        for chunk in all {
            let found = nsText.range(
                of: chunk.rawText,
                options: [],
                range: NSRange(location: searchStart, length: nsText.length - searchStart)
            )
            XCTAssertNotEqual(found.location, NSNotFound, "Frase non trovata nel documento: \(chunk.rawText)")
            XCTAssertEqual(chunk.sourceRange, SourceTextRange(found))
            searchStart = found.location + found.length
        }
    }

    func testPagePreparationCleansParagraphsAndHasNoRanges() {
        let reading = preparer.preparePage(
            text: "Titolo\r\n\r\n\r\n\r\nPrima frase. Seconda frase.",
            mode: .off
        )

        XCTAssertEqual(reading.displayText, "Titolo\n\nPrima frase. Seconda frase.")
        XCTAssertEqual(reading.chunks.first?.text, "Titolo")
        XCTAssertEqual(reading.chunks.last?.text, "Seconda frase.")
        XCTAssertTrue(reading.chunks.allSatisfy { $0.sourceRange == nil })
        XCTAssertFalse(reading.hasRemainder)
    }

    func testPagePreparationNormalizesChunksNotDisplayText() {
        let reading = preparer.preparePage(text: "Costa 50 €. Fine.", mode: .off)

        XCTAssertEqual(reading.displayText, "Costa 50 €. Fine.")
        XCTAssertEqual(reading.chunks.map(\.text), ["Costa 50 euro.", "Fine."])
    }
}
