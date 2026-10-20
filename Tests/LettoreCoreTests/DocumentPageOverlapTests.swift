import XCTest
@testable import LettoreCore

final class DocumentPageOverlapTests: XCTestCase {

    func testPerfectOverlapRemovesTheRepeatedHead() {
        let old = "Alfa bravo charlie delta."
        let new = "delta. Echo foxtrot golf."

        XCTAssertEqual(DocumentPageOverlap.textAfterOverlap(old, new), " Echo foxtrot golf.")
    }

    func testNoOverlapReturnsTheWholeNewPage() {
        let old = "Alfa bravo charlie."
        let new = "Zulu yankee xray."

        XCTAssertEqual(DocumentPageOverlap.textAfterOverlap(old, new), new)
    }

    func testOverlapLargerThanLegacyFourThousandLimitIsFound() {
        // 5.000 caratteri di overlap: il vecchio cap fisso a 4.000 non lo
        // trovava e restituiva l'intera pagina duplicata.
        let shared = String(repeating: "abcdefghij", count: 500)
        let old = "testa-" + shared
        let new = shared + "-coda"

        XCTAssertEqual(DocumentPageOverlap.textAfterOverlap(old, new), "-coda")
    }

    func testExplicitMaxOverlapBoundsTheSearchWindow() {
        let shared = (0..<400).map { "riga-\($0)-contenuto" }.joined(separator: " ")
        let old = "introduzione " + shared
        let new = shared + " conclusione"

        XCTAssertEqual(DocumentPageOverlap.textAfterOverlap(old, new, maxOverlap: 4_000), new)
        XCTAssertEqual(DocumentPageOverlap.textAfterOverlap(old, new), " conclusione")
    }

    func testIdenticalPagesProduceNoNewText() {
        let page = "Una pagina identica a se stessa, con punteggiatura e numeri 123."

        XCTAssertEqual(DocumentPageOverlap.textAfterOverlap(page, page), "")
    }

    func testEmptyStrings() {
        XCTAssertEqual(DocumentPageOverlap.textAfterOverlap("", ""), "")
        XCTAssertEqual(DocumentPageOverlap.textAfterOverlap("", "pagina nuova"), "pagina nuova")
        XCTAssertEqual(DocumentPageOverlap.textAfterOverlap("pagina vecchia", ""), "")
    }

    func testSmallScrollStepKeepsTheOverlap() {
        // Passo piccolo: la nuova viewport contiene quasi tutta la vecchia.
        let shared = (0..<120).map { "riga-\($0)-testo" }.joined(separator: " ")
        let old = "apertura " + shared
        let new = String(old.suffix(400)) + " coda nuova."

        let delta = DocumentPageOverlap.textAfterOverlap(old, new)
        XCTAssertEqual(delta, " coda nuova.")
        XCTAssertFalse(delta.contains("riga-"), "L'overlap non deve essere duplicato")
    }

    func testNewPageFullyContainedInOldPage() {
        let old = "Uno due tre quattro cinque sei sette."
        let new = String(old.suffix(12))

        XCTAssertEqual(DocumentPageOverlap.textAfterOverlap(old, new), "")
    }

    func testMultilineOverlapAcrossParagraphBreaks() {
        let old = "Primo paragrafo.\n\nSecondo paragrafo con testo."
        let new = "Secondo paragrafo con testo.\n\nTerzo paragrafo."

        XCTAssertEqual(DocumentPageOverlap.textAfterOverlap(old, new), "\n\nTerzo paragrafo.")
    }
}
