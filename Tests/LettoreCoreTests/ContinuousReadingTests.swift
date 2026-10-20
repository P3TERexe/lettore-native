import XCTest
@testable import LettoreCore

final class ContinuousReadingTests: XCTestCase {

    // MARK: - Filtro rumore

    func testNoiseFilterRemovesPageNumbersAndRepeatedRunningHeaders() {
        let filter = DocumentNoiseFilter()
        let text = """
        Introduzione al capitolo.

        Pagina 1

        Questa è una frase spezzata a metà pa-
        gina che deve essere unita.

        2

        Una nota importante.[1]

        Titolo corrente

        Altra pagina del documento.

        Titolo corrente

        Terza pagina del documento.

        Titolo corrente

        Fine.
        """

        let cleaned = filter.filter(text, mode: .light)

        XCTAssertFalse(cleaned.contains("Pagina 1"))
        XCTAssertFalse(cleaned.contains("\n2\n"))
        XCTAssertFalse(cleaned.contains("Titolo corrente"))
        XCTAssertTrue(cleaned.contains("pagina che deve essere unita"))
        XCTAssertTrue(cleaned.contains("nota importante.[1]"), "Le note e le citazioni non devono essere rimosse")
        XCTAssertTrue(cleaned.contains("Fine."))
    }

    func testNoiseFilterOffLeavesTextUntouched() {
        let filter = DocumentNoiseFilter()
        let text = "Pagina 1\n\nTitolo corrente\n\nTesto."

        XCTAssertEqual(filter.filter(text, mode: .off), text)
    }

    func testNoiseFilterKeepsMeaningfulLines() {
        let filter = DocumentNoiseFilter()
        let text = """
        Capitolo primo

        Il contenuto continues qui.

        Capitolo secondo

        Altro contenuto.
        """

        let cleaned = filter.filter(text, mode: .light)
        XCTAssertTrue(cleaned.contains("Capitolo primo"))
        XCTAssertTrue(cleaned.contains("Capitolo secondo"))
    }

    // MARK: - SentenceCarryBuffer

    func testCarryBufferDoesNotSplitSentencesAcrossPages() {
        var buffer = SentenceCarryBuffer()

        let first = buffer.append("Frase uno. Frase due incom", isFinal: false)
        XCTAssertEqual(first, "Frase uno. ")
        XCTAssertEqual(buffer.pendingText, "Frase due incom")

        let second = buffer.append("pleta. Frase tre incom", isFinal: false)
        XCTAssertEqual(second, "Frase due incompleta. ")
        XCTAssertEqual(buffer.pendingText, "Frase tre incom")

        let final = buffer.append(" fine.", isFinal: true)
        XCTAssertEqual(final, "Frase tre incom fine.")
        XCTAssertTrue(buffer.pendingText.isEmpty)
    }

    func testCarryBufferFlushesLongTextWithoutPunctuation() {
        var buffer = SentenceCarryBuffer(maxCarryLength: 20)
        let text = String(repeating: "parola ", count: 6)

        let output = buffer.append(text, isFinal: false)
        XCTAssertEqual(output, text)
        XCTAssertTrue(buffer.pendingText.isEmpty)
    }

    func testSplitPointPrefersCompleteSentence() {
        let text = "Prima frase breve. Seconda frase un po' più lunga. Terza frase."
        let split = SentenceCarryBuffer.splitPoint(in: text, targetLength: 30)

        XCTAssertEqual(String(text[..<split]), "Prima frase breve. ")
    }

    func testSplitPointKeepsFirstSentenceWholeWhenTargetFallsInsideIt() {
        let text = "Prima frase breve. Seconda frase."
        let split = SentenceCarryBuffer.splitPoint(in: text, targetLength: 5)

        XCTAssertEqual(String(text[..<split]), "Prima frase breve. ")
    }

    // MARK: - AppState append

    func testAppendChunksReindexesAndPreservesIdentity() {
        let (state, suiteName, defaults) = makeState()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = ReadingChunk(index: 0, text: "Prima.")
        let second = ReadingChunk(index: 1, text: "Seconda.")
        state.setQueue([first, second])

        let third = ReadingChunk(index: 0, text: "Terza.")
        let fourth = ReadingChunk(index: 1, text: "Quarta.")
        let appended = state.appendChunks([third, fourth])

        XCTAssertEqual(appended.map(\.index), [2, 3])
        XCTAssertEqual(state.readingQueue.map(\.index), [0, 1, 2, 3])
        XCTAssertEqual(appended[0].id, third.id)
        XCTAssertEqual(appended[1].id, fourth.id)
    }

    func testAppendChunksRestartsFromNewPageWhenQueueWasFinished() {
        let (state, suiteName, defaults) = makeState()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        state.setQueue([ReadingChunk(index: 0, text: "Unica.")])
        _ = state.advanceChunk()
        XCTAssertNil(state.currentChunk)

        state.appendChunks([ReadingChunk(index: 0, text: "Pagina due.")])

        XCTAssertEqual(state.currentChunk?.text, "Pagina due.")
        XCTAssertEqual(state.currentChunk?.index, 1)
    }

    // MARK: - Preferenze

    func testPreferencesPersistAndAppStateLoadsThem() {
        let suiteName = "LettoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PreferencesStore(defaults: defaults)
        XCTAssertFalse(store.isContinuousReadingEnabled)
        XCTAssertTrue(store.isAutoPageEnabled)
        XCTAssertEqual(store.noiseFilterMode, .light)

        store.isContinuousReadingEnabled = true
        store.isAutoPageEnabled = false
        store.noiseFilterMode = .off

        let reloaded = PreferencesStore(defaults: defaults)
        XCTAssertTrue(reloaded.isContinuousReadingEnabled)
        XCTAssertFalse(reloaded.isAutoPageEnabled)
        XCTAssertEqual(reloaded.noiseFilterMode, .off)

        let state = AppState(preferences: reloaded)
        XCTAssertTrue(state.isContinuousReadingEnabled)
        XCTAssertFalse(state.isAutoPageEnabled)
        XCTAssertEqual(state.noiseFilterMode, .off)

        state.isAutoPageEnabled = true
        XCTAssertTrue(store.isAutoPageEnabled, "Le modifiche dell'AppState devono essere persistite")
    }

    // MARK: - Helper

    private func makeState() -> (AppState, String, UserDefaults) {
        let suiteName = "LettoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let state = AppState(preferences: PreferencesStore(defaults: defaults))
        return (state, suiteName, defaults)
    }
}
