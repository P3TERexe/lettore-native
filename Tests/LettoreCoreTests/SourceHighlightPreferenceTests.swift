import XCTest
@testable import LettoreCore

final class SourceHighlightPreferenceTests: XCTestCase {

    func testSourceHighlightDefaultsToTrueAndPersists() {
        let suiteName = "LettoreTests.Highlight.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = PreferencesStore(defaults: defaults)
        XCTAssertTrue(preferences.isSourceHighlightEnabled, "Default attivo")

        preferences.isSourceHighlightEnabled = false
        XCTAssertFalse(preferences.isSourceHighlightEnabled)

        let reloaded = PreferencesStore(defaults: defaults)
        XCTAssertFalse(reloaded.isSourceHighlightEnabled, "La preferenza sopravvive a una nuova istanza")
    }

    func testAppStateLoadsAndPersistsTheSourceHighlightToggle() {
        let suiteName = "LettoreTests.Highlight.State.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = PreferencesStore(defaults: defaults)
        preferences.isSourceHighlightEnabled = false

        let state = AppState(preferences: preferences)
        XCTAssertFalse(state.isSourceHighlightEnabled)
        XCTAssertNil(state.sourceHighlightNotice)

        state.isSourceHighlightEnabled = true
        XCTAssertEqual(
            defaults.object(forKey: PreferencesStore.Key.sourceHighlightEnabled) as? Bool,
            true
        )

        let second = AppState(preferences: preferences)
        XCTAssertTrue(second.isSourceHighlightEnabled)
    }

    func testTrimmedCaptureResultAdvancesTheAbsoluteRange() {
        let result = CapturedSelection(
            text: "  😀 ciao  ",
            sourceRange: SourceTextRange(location: 100, length: 20)
        )

        XCTAssertEqual(result.trimmedText, "😀 ciao")
        let range = result.trimmedSourceRange
        XCTAssertEqual(range?.location, 102, "Due spazi iniziali valgono due unità UTF-16")
        XCTAssertEqual(range?.length, ("😀 ciao" as NSString).length)
        XCTAssertEqual(
            range?.end,
            102 + ("😀 ciao" as NSString).length
        )
    }

    func testCaptureWithoutRangeKeepsTrimmedRangeNil() {
        let result = CapturedSelection(text: "  Testo senza mappa  ")
        XCTAssertEqual(result.trimmedText, "Testo senza mappa")
        XCTAssertNil(result.trimmedSourceRange)
    }

    func testOffsettingSourceRangeMovesOnlyMappedChunks() {
        let documentID = UUID()
        let mapped = ReadingChunk(
            index: 0,
            text: "Frase.",
            sourceDocumentID: documentID,
            sourceRange: SourceTextRange(location: 10, length: 6)
        )
        let moved = mapped.offsettingSourceRange(by: 500)

        XCTAssertEqual(moved.sourceRange, SourceTextRange(location: 510, length: 6))
        XCTAssertEqual(moved.sourceDocumentID, documentID)

        let manual = ReadingChunk(index: 1, text: "Manuale.")
        XCTAssertNil(manual.offsettingSourceRange(by: 500).sourceRange)
    }
}
