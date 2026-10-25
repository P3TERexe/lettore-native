import XCTest
import LettoreCore

final class ViewportTextCollectorTests: XCTestCase {

    func testCollectsBlocksSeparatedByBlankLines() {
        var collector = ViewportTextCollector()
        collector.add(role: "AXHeading", value: "Capitolo primo")
        collector.add(role: "AXStaticText", value: "  Il testo del paragrafo.  ")

        XCTAssertEqual(collector.text, "Capitolo primo\n\nIl testo del paragrafo.")
    }

    func testEmptyCollectorReturnsNil() {
        let collector = ViewportTextCollector()

        XCTAssertNil(collector.text)
    }

    func testNestedDuplicateIsIgnored() {
        var collector = ViewportTextCollector()
        collector.add(role: "AXHeading", value: "Capitolo")
        collector.add(role: "AXStaticText", value: "  capitolo  ")
        collector.add(role: "AXStaticText", value: "Testo")

        XCTAssertEqual(collector.text, "Capitolo\n\nTesto")
    }

    func testDuplicateWithDifferentWhitespaceIsIgnored() {
        var collector = ViewportTextCollector()
        collector.add(role: "AXParagraph", value: "Prima   riga\ndi testo")
        collector.add(role: "AXStaticText", value: "prima riga di testo")

        XCTAssertEqual(collector.text, "Prima   riga\ndi testo")
    }

    func testURLsAreIgnored() {
        var collector = ViewportTextCollector()
        collector.add(role: "AXStaticText", value: "https://example.com")
        collector.add(role: "AXStaticText", value: "HTTP://EXAMPLE.COM")
        collector.add(role: "AXStaticText", value: "file:///tmp/documento.txt")
        collector.add(role: "AXStaticText", value: "Testo utile")

        XCTAssertEqual(collector.text, "Testo utile")
    }

    func testOnlyListMarkersAreIgnored() {
        var collector = ViewportTextCollector()
        for marker in ["•", "◦", "▪", "‣", "-", "–", "—", "·", "•◦"] {
            collector.add(role: "AXStaticText", value: marker)
        }
        collector.add(role: "AXStaticText", value: "• Voce vera")
        collector.add(role: "AXStaticText", value: "- Altra voce")

        XCTAssertEqual(collector.text, "• Voce vera\n\n- Altra voce")
    }

    func testEmptyAndNilRolesDoNotContribute() {
        var collector = ViewportTextCollector()
        collector.add(role: nil, value: "Senza ruolo")
        collector.add(role: "", value: "Ruolo vuoto")

        XCTAssertNil(collector.text)
    }

    func testSkippedRoleDoesNotContribute() {
        var collector = ViewportTextCollector()
        collector.add(role: "AXButton", value: "Premi qui")
        collector.add(role: "AXImage", value: "Descrizione immagine")

        XCTAssertNil(collector.text)
    }

    func testTextRoleWithoutValueDoesNotContribute() {
        var collector = ViewportTextCollector()
        collector.add(role: "AXStaticText", value: nil)

        XCTAssertNil(collector.text)
    }

    func testEmptyAndWhitespaceValuesAreIgnored() {
        var collector = ViewportTextCollector()
        collector.add(role: "AXStaticText", value: "")
        collector.add(role: "AXStaticText", value: "  \n\t ")
        collector.add(role: "AXStaticText", value: "\n\n")

        XCTAssertNil(collector.text)
    }

    func testLimitStopsCollectionButKeepsTheCrossingBlockWhole() {
        var collector = ViewportTextCollector()
        let almostFull = String(repeating: "a", count: 199_999)

        collector.add(role: "AXStaticText", value: almostFull)
        XCTAssertFalse(collector.isFull)

        // Il blocco che supera il limite viene accettato intero, come nella
        // DFS storica; il limite ferma solo gli elementi successivi.
        collector.add(role: "AXStaticText", value: "bb")
        XCTAssertTrue(collector.isFull)

        collector.add(role: "AXStaticText", value: "coda ignorata")

        XCTAssertEqual(collector.text, almostFull + "\n\nbb")
    }

    func testExactLimitStopsFurtherAdditions() {
        var collector = ViewportTextCollector()
        let full = String(repeating: "x", count: ViewportTextCollector.characterLimit)

        collector.add(role: "AXStaticText", value: full)
        XCTAssertTrue(collector.isFull)

        collector.add(role: "AXStaticText", value: "oltre il limite")

        XCTAssertEqual(collector.text, full)
    }
}
