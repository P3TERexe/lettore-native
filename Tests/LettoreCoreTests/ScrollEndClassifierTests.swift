import XCTest
import LettoreCore

final class ScrollEndClassifierTests: XCTestCase {

    func testMissingScrollBarIsUnknown() {
        XCTAssertEqual(
            ScrollEndClassifier.classify(value: nil, minValue: nil, maxValue: nil),
            .unknown
        )
    }

    func testMissingRangeValueIsUnknown() {
        XCTAssertEqual(
            ScrollEndClassifier.classify(value: 0.5, minValue: nil, maxValue: 1),
            .unknown
        )
        XCTAssertEqual(
            ScrollEndClassifier.classify(value: 0.5, minValue: 0, maxValue: nil),
            .unknown
        )
        XCTAssertEqual(
            ScrollEndClassifier.classify(value: nil, minValue: 0, maxValue: 1),
            .unknown
        )
    }

    func testZeroRangeIsUnknown() {
        XCTAssertEqual(
            ScrollEndClassifier.classify(value: 0, minValue: 0, maxValue: 0),
            .unknown
        )
    }

    func testInvertedRangeIsUnknown() {
        XCTAssertEqual(
            ScrollEndClassifier.classify(value: 0.5, minValue: 1, maxValue: 0),
            .unknown
        )
    }

    func testValueAtMaximumIsAtEnd() {
        XCTAssertEqual(
            ScrollEndClassifier.classify(value: 1, minValue: 0, maxValue: 1),
            .atEnd
        )
        XCTAssertEqual(
            ScrollEndClassifier.classify(value: 42, minValue: 10, maxValue: 42),
            .atEnd
        )
    }

    func testValueBelowMaximumIsNotAtEnd() {
        XCTAssertEqual(
            ScrollEndClassifier.classify(value: 0.5, minValue: 0, maxValue: 1),
            .notAtEnd
        )
        XCTAssertEqual(
            ScrollEndClassifier.classify(value: 0, minValue: 0, maxValue: 1),
            .notAtEnd
        )
    }

    func testToleranceAbsorbsRoundingNearMaximum() {
        // Range 1.000: tolleranza 1 (0,1%).
        XCTAssertEqual(
            ScrollEndClassifier.classify(value: 999.5, minValue: 0, maxValue: 1_000),
            .atEnd
        )
        XCTAssertEqual(
            ScrollEndClassifier.classify(value: 999, minValue: 0, maxValue: 1_000),
            .atEnd
        )
        XCTAssertEqual(
            ScrollEndClassifier.classify(value: 998.9, minValue: 0, maxValue: 1_000),
            .notAtEnd
        )
    }

    func testToleranceHasAnAbsoluteFloorOnTinyRanges() {
        // Range 0,01: lo 0,1% vale 0,00001, sotto il minimo assoluto 0,0001.
        XCTAssertEqual(
            ScrollEndClassifier.classify(value: 0.00995, minValue: 0, maxValue: 0.01),
            .atEnd
        )
        XCTAssertEqual(
            ScrollEndClassifier.classify(value: 0.00985, minValue: 0, maxValue: 0.01),
            .notAtEnd
        )
    }
}
