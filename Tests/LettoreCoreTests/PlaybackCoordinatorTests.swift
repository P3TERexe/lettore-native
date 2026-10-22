import XCTest
@testable import LettoreCore
@testable import LettoreEngine

@MainActor
final class PlaybackCoordinatorTests: XCTestCase {

    /// Pipeline che non produce audio: i test verificano solo i callback e
    /// cancellano la sintesi con `stop()`, senza rete né uscita audio reale.
    private final class HangingTTSPipeline: TTSPipelineProtocol, @unchecked Sendable {
        var isModelLoaded = true

        func loadModel() async throws {}

        func synthesize(
            text: String,
            voice: VoiceProfile,
            speed: Float
        ) async throws -> Data {
            try await synthesize(text: text, voice: voice, speed: speed, steps: 8)
        }

        func synthesize(
            text: String,
            voice: VoiceProfile,
            speed: Float,
            steps: Int
        ) async throws -> Data {
            try await Task.sleep(nanoseconds: 30_000_000_000)
            return Data()
        }
    }

    @MainActor
    private final class DeferredQueueLow {
        private(set) var continuation: CheckedContinuation<Bool, Never>?

        func wait() async -> Bool {
            await withCheckedContinuation { self.continuation = $0 }
        }

        func resolve(_ value: Bool) {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }

    // MARK: - Chunk corrente

    func testCurrentChunkCallbackFiresOnPlaySkipJumpAndResume() {
        let (state, cleanup) = makeState(["Uno.", "Due.", "Tre."])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        var seen: [String] = []
        coordinator.onCurrentChunkChanged = { seen.append($0.text) }

        coordinator.playCurrentChunk()
        XCTAssertEqual(seen, ["Uno."], "Il play del primo chunk notifica il cambio")

        coordinator.skipForward()
        XCTAssertEqual(seen, ["Uno.", "Due."], "Lo skip in avanti notifica il nuovo chunk")

        coordinator.jumpToChunk(state.readingQueue[2])
        XCTAssertEqual(seen, ["Uno.", "Due.", "Tre."], "Il jump dalla lista notifica il chunk scelto")

        state.playbackState = .paused
        coordinator.play()
        XCTAssertEqual(seen.last, "Tre.", "La ripresa da pausa rivaluta il chunk corrente")

        coordinator.stop()
    }

    func testCurrentChunkCallbackIsNotFiredOnAudioProgress() {
        let (state, cleanup) = makeState(["Uno.", "Due."])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        var count = 0
        coordinator.onCurrentChunkChanged = { _ in count += 1 }
        coordinator.playCurrentChunk()

        coordinator.audioEngine.onProgressUpdate?(0.5)
        coordinator.audioEngine.onProgressUpdate?(0.9)

        XCTAssertEqual(count, 1, "Il progresso audio non deve aggiornare l'highlight")
        coordinator.stop()
    }

    // MARK: - Fine sessione

    func testPlaybackEndedFiresOnceOnRepeatedStop() {
        let (state, cleanup) = makeState(["Uno."])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        var ended = 0
        coordinator.onPlaybackEnded = { ended += 1 }

        coordinator.playCurrentChunk()
        coordinator.stop()
        XCTAssertEqual(ended, 1)

        coordinator.stop()
        XCTAssertEqual(ended, 1, "Uno stop ripetuto non duplica la fine sessione")
    }

    func testPlaybackEndedFiresWhenQueueExhaustsAfterLastChunk() {
        let (state, cleanup) = makeState(["Unico."])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        var ended = 0
        coordinator.onPlaybackEnded = { ended += 1 }

        coordinator.playCurrentChunk()
        coordinator.skipForward()

        XCTAssertEqual(ended, 1, "La coda esaurita dichiara la fine una volta")

        coordinator.stop()
        XCTAssertEqual(ended, 1, "Lo stop successivo non duplica la fine")
    }

    func testPlaybackEndedFiresWithoutCurrentChunkAndResetsForANewSession() {
        let (state, cleanup) = makeState([])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        var ended = 0
        coordinator.onPlaybackEnded = { ended += 1 }

        coordinator.playCurrentChunk()
        XCTAssertEqual(ended, 1, "Senza chunk corrente la sessione è conclusa")

        coordinator.playCurrentChunk()
        XCTAssertEqual(ended, 1, "Nessun doppione senza un nuovo chunk")

        state.setQueue([ReadingChunk(index: 0, text: "Nuova sessione.")])
        coordinator.playCurrentChunk()
        coordinator.stop()
        XCTAssertEqual(ended, 2, "Una nuova sessione può terminare di nuovo")
    }

    func testPlaybackEndedWaitsForPendingFetchThatReturnsNoChunks() async {
        let (state, cleanup) = makeState(["Unico."])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        let gate = DeferredQueueLow()
        coordinator.onQueueLow = { await gate.wait() }

        var ended = 0
        coordinator.onPlaybackEnded = { ended += 1 }

        coordinator.playCurrentChunk()
        for _ in 0..<200 where gate.continuation == nil {
            await Task.yield()
        }
        XCTAssertNotNil(gate.continuation, "La fetch pagina deve essere in volo")

        coordinator.skipForward()
        XCTAssertEqual(ended, 0, "La fine non va dichiarata prima dell'esito della fetch")

        gate.resolve(false)
        for _ in 0..<200 where ended == 0 {
            await Task.yield()
        }

        XCTAssertEqual(ended, 1, "Una fetch senza chunk chiude la sessione")
        coordinator.stop()
        XCTAssertEqual(ended, 1)
    }

    func testPlayDuringPendingFetchDoesNotEndPlaybackSession() async {
        let (state, cleanup) = makeState(["Unico."])
        defer { cleanup() }
        let coordinator = makeCoordinator(state: state)

        let gate = DeferredQueueLow()
        coordinator.onQueueLow = { await gate.wait() }

        var ended = 0
        coordinator.onPlaybackEnded = { ended += 1 }

        coordinator.playCurrentChunk()
        for _ in 0..<200 where gate.continuation == nil {
            await Task.yield()
        }
        XCTAssertNotNil(gate.continuation, "La fetch pagina deve essere in volo")

        coordinator.skipForward()
        XCTAssertEqual(ended, 0)

        // Play dalla pillola mentre la pagina è in volo: non c'è un chunk
        // corrente, ma la sessione non è finita.
        coordinator.playCurrentChunk()
        XCTAssertEqual(ended, 0, "Il Play non deve chiudere la sessione con una fetch pendente")
        XCTAssertEqual(state.playbackState, .synthesizing)

        gate.resolve(false)
        for _ in 0..<200 where ended == 0 {
            await Task.yield()
        }

        XCTAssertEqual(ended, 1, "La fine arriva solo quando la fetch non produce chunk")
        coordinator.stop()
        XCTAssertEqual(ended, 1)
    }

    // MARK: - Helper

    private func makeState(_ texts: [String]) -> (AppState, () -> Void) {
        let suiteName = "LettoreTests.Playback.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let state = AppState(preferences: PreferencesStore(defaults: defaults))
        state.setQueue(texts.enumerated().map { index, text in
            ReadingChunk(index: index, text: text)
        })
        return (state, { defaults.removePersistentDomain(forName: suiteName) })
    }

    private func makeCoordinator(state: AppState) -> PlaybackCoordinator {
        PlaybackCoordinator(
            appState: state,
            audioEngine: AudioEngineService(),
            supertonicPipeline: HangingTTSPipeline()
        )
    }
}
