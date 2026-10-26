import XCTest
import Foundation
@testable import LettoreCore
@testable import LettoreEngine

@MainActor
final class SpeechOutputTests: XCTestCase {

    // MARK: - Pipeline finta

    private final class FakeTTSPipeline: TTSPipelineProtocol, @unchecked Sendable {
        var isModelLoaded = true
        var data = Data("WAV_FAKE".utf8)
        var error: Error?
        var hangs = false
        var waitsForRelease = false

        private let lock = NSLock()
        private var releaseContinuation: CheckedContinuation<Void, Never>?
        private var _callCount = 0
        private var _completedCount = 0
        private var _cancelledCount = 0
        private var _texts: [String] = []

        var callCount: Int { lock.withLock { _callCount } }
        var completedCount: Int { lock.withLock { _completedCount } }
        var cancelledCount: Int { lock.withLock { _cancelledCount } }
        var texts: [String] { lock.withLock { _texts } }

        func release() {
            let continuation = lock.withLock {
                let pending = releaseContinuation
                releaseContinuation = nil
                return pending
            }
            continuation?.resume()
        }

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
            lock.withLock {
                _callCount += 1
                _texts.append(text)
            }

            if waitsForRelease {
                await withCheckedContinuation { continuation in
                    lock.withLock { releaseContinuation = continuation }
                }
            }

            if hangs {
                return try await withTaskCancellationHandler {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    lock.withLock { _completedCount += 1 }
                    return data
                } onCancel: {
                    self.lock.withLock { self._cancelledCount += 1 }
                }
            }

            if let error {
                throw error
            }

            lock.withLock { _completedCount += 1 }
            return data
        }
    }

    // MARK: - Uscita audio finta

    @MainActor
    private final class FakeSpeechAudio: SpeechAudioBackend {
        var onLevelsUpdate: (([Float]) -> Void)?
        var onProgressUpdate: ((Double) -> Void)?

        private(set) var playedData: [Data] = []
        private(set) var playbackSpeeds: [Float] = []
        private(set) var fallbackTexts: [String] = []
        private(set) var pauses: [VoiceSource] = []
        private(set) var resumes: [VoiceSource] = []
        private(set) var speeds: [Float] = []
        private(set) var stopCount = 0

        private var playbackCompletions: [() -> Void] = []
        private var fallbackCompletions: [() -> Void] = []

        func play(data: Data, speed: Float, onComplete: @escaping () -> Void) {
            playedData.append(data)
            playbackSpeeds.append(speed)
            playbackCompletions.append(onComplete)
        }

        func speakFallback(
            text: String,
            voice: VoiceProfile,
            speed: Float,
            onComplete: @escaping () -> Void
        ) {
            fallbackTexts.append(text)
            fallbackCompletions.append(onComplete)
        }

        func pause(source: VoiceSource) {
            pauses.append(source)
        }

        func resume(source: VoiceSource) {
            resumes.append(source)
        }

        func stop() {
            stopCount += 1
        }

        func setSpeed(_ speed: Float) {
            speeds.append(speed)
        }

        func completePlayback(at index: Int) {
            playbackCompletions[index]()
        }

        func completeFallback() {
            fallbackCompletions.last?()
        }
    }

    // MARK: - Raccolta eventi

    @MainActor
    private final class EventCollector {
        private(set) var events: [SpeechEvent] = []
        private var task: Task<Void, Never>?

        init(_ stream: AsyncStream<SpeechEvent>) {
            task = Task { [weak self] in
                for await event in stream {
                    self?.events.append(event)
                }
            }
        }

        func stop() {
            task?.cancel()
            task = nil
        }

        var started: [SpeechStarted] {
            events.compactMap {
                if case .started(let started) = $0 { return started }
                return nil
            }
        }

        func containsFinished(_ requestID: UUID) -> Bool {
            events.contains(.finished(requestID: requestID))
        }

        func containsFailed(_ requestID: UUID) -> Bool {
            events.contains {
                if case .synthesisFailed(let id, _) = $0 { return id == requestID }
                return false
            }
        }

        var kinds: [String] {
            events.map { event in
                switch event {
                case .started: return "started"
                case .progress: return "progress"
                case .levels: return "levels"
                case .finished: return "finished"
                case .synthesisFailed: return "failed"
                }
            }
        }
    }

    // MARK: - Cache miss / hit

    func testCacheMissSynthesizesOnceAndCacheHitReusesAudio() async {
        let (output, pipeline, audio, collector, cleanup) = makeSystem()
        defer {
            collector.stop()
            cleanup()
        }

        let voice = VoiceProfile.standardVoices[0]
        let first = SpeechRequest(
            chunk: ReadingChunk(index: 0, text: "Ciao mondo."),
            voice: voice,
            speed: 1.0,
            steps: 5
        )

        output.play(first)
        await assertEventually { audio.playedData.count == 1 }
        await assertEventually { collector.started.count == 1 }
        XCTAssertEqual(pipeline.callCount, 1)
        XCTAssertNotNil(collector.started.first?.synthesisDurationMs)

        audio.completePlayback(at: 0)
        await assertEventually { collector.containsFinished(first.id) }

        // Stesso testo, voce e step: la velocità di ascolto non deve rompere
        // il cache hit né invocare di nuovo il backend.
        let second = SpeechRequest(
            chunk: ReadingChunk(index: 1, text: "Ciao mondo."),
            voice: voice,
            speed: 1.5,
            steps: 5
        )
        output.play(second)
        await assertEventually { audio.playedData.count == 2 }
        await assertEventually { collector.started.count == 2 }
        XCTAssertEqual(pipeline.callCount, 1)
        XCTAssertNil(collector.started[1].synthesisDurationMs, "Il cache hit non è una sintesi")

        audio.completePlayback(at: 1)
        await assertEventually { collector.containsFinished(second.id) }
    }

    // MARK: - Preload

    func testFallbackVoiceUsesTheSelectedLanguage() {
        XCTAssertEqual(
            NativeSpeechService.systemLanguage(for: VoiceProfile.standardVoices[0]),
            "it-IT"
        )
        XCTAssertEqual(
            NativeSpeechService.systemLanguage(for: VoiceProfile(id: "EN-M1", name: "John", language: "en")),
            "en-US"
        )
        XCTAssertEqual(
            NativeSpeechService.systemLanguage(for: VoiceProfile(id: "FR-F1", name: "Camille", language: "fr")),
            "fr-FR"
        )
        XCTAssertEqual(NativeSpeechService.systemLanguage(for: nil), "it-IT")
    }

    func testSpeedChangedDuringSynthesisAppliesToTheIncomingPlayback() async {        let (output, pipeline, audio, collector, cleanup) = makeSystem()
        defer {
            collector.stop()
            cleanup()
        }

        pipeline.waitsForRelease = true
        let request = SpeechRequest(
            chunk: ReadingChunk(index: 0, text: "Velocità."),
            voice: VoiceProfile.standardVoices[0],
            speed: 1.0,
            steps: 8
        )

        output.play(request)
        await assertEventually { pipeline.callCount == 1 }

        output.setSpeed(1.75)
        pipeline.release()

        await assertEventually { audio.playbackSpeeds.count == 1 }
        XCTAssertEqual(audio.playbackSpeeds.first, 1.75)
    }

    func testPreloadDeduplicatesAndNeverPlays() async {
        let (output, pipeline, audio, collector, cleanup) = makeSystem()
        defer {
            collector.stop()
            cleanup()
        }

        let request = SpeechRequest(
            chunk: ReadingChunk(index: 0, text: "Frase da precaricare."),
            voice: VoiceProfile.standardVoices[0],
            speed: 1.0,
            steps: 8
        )

        output.preload([request])
        output.preload([request])

        await assertEventually { pipeline.completedCount == 1 }
        XCTAssertEqual(pipeline.callCount, 1, "Lo stesso preload non deve essere sintetizzato due volte")
        XCTAssertEqual(audio.playedData.count, 0, "Il preload non riproduce")
        XCTAssertTrue(collector.events.isEmpty, "Il preload non emette eventi di riproduzione")

        output.play(request)
        await assertEventually { audio.playedData.count == 1 }
        XCTAssertEqual(pipeline.callCount, 1, "Il play deve consumare il preload, non risintetizzare")

        audio.completePlayback(at: 0)
        await assertEventually { collector.containsFinished(request.id) }
    }

    func testPlayWhilePreloadIsInFlightWaitsWithoutSynthesizingAgain() async {
        let (output, pipeline, audio, collector, cleanup) = makeSystem()
        defer {
            collector.stop()
            cleanup()
        }

        let request = SpeechRequest(
            chunk: ReadingChunk(index: 0, text: "Preload in volo."),
            voice: VoiceProfile.standardVoices[0],
            speed: 1.0,
            steps: 8
        )
        pipeline.waitsForRelease = true

        output.preload([request])
        await assertEventually { pipeline.callCount == 1 }

        output.play(request)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(audio.playedData.isEmpty, "Il play aspetta il preload già in corso")

        pipeline.release()
        await assertEventually { audio.playedData.count == 1 }
        XCTAssertEqual(pipeline.callCount, 1, "Il preload in volo viene riusato, non risintetizzato")

        audio.completePlayback(at: 0)
        await assertEventually { collector.containsFinished(request.id) }
    }

    // MARK: - Cancellazione

    func testCancelAllStopsPendingSynthesisAndDoesNotEmitFinished() async {
        let (output, pipeline, audio, collector, cleanup) = makeSystem()
        defer {
            collector.stop()
            cleanup()
        }
        pipeline.hangs = true

        let request = SpeechRequest(
            chunk: ReadingChunk(index: 0, text: "Sintesi lenta."),
            voice: VoiceProfile.standardVoices[0],
            speed: 1.0,
            steps: 8
        )

        output.play(request)
        await assertEventually { pipeline.callCount == 1 }
        output.cancelAll()

        await assertEventually { pipeline.cancelledCount == 1 }
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(audio.playedData.isEmpty)
        XCTAssertFalse(collector.containsFinished(request.id))
        XCTAssertEqual(collector.kinds.filter { $0 == "finished" }.count, 0)
    }

    func testCompletionOfCancelledRequestDoesNotFinishNextRequest() async {
        let (output, pipeline, audio, collector, cleanup) = makeSystem()
        defer {
            collector.stop()
            cleanup()
        }

        let first = SpeechRequest(
            chunk: ReadingChunk(index: 0, text: "Prima richiesta."),
            voice: VoiceProfile.standardVoices[0]
        )
        let second = SpeechRequest(
            chunk: ReadingChunk(index: 1, text: "Seconda richiesta."),
            voice: VoiceProfile.standardVoices[0]
        )

        output.play(first)
        await assertEventually { audio.playedData.count == 1 }

        output.play(second)
        await assertEventually { audio.playedData.count == 2 }
        XCTAssertEqual(pipeline.callCount, 2)

        // Il player della prima richiesta completa in ritardo: non deve
        // chiudere né la prima né la seconda.
        audio.completePlayback(at: 0)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(collector.containsFinished(first.id))
        XCTAssertFalse(collector.containsFinished(second.id))

        audio.completePlayback(at: 1)
        await assertEventually { collector.containsFinished(second.id) }
        XCTAssertFalse(collector.containsFinished(first.id))
    }

    // MARK: - Ordine eventi

    func testPlaybackEventsArriveInOrder() async {
        let (output, _, audio, collector, cleanup) = makeSystem()
        defer {
            collector.stop()
            cleanup()
        }

        let request = SpeechRequest(
            chunk: ReadingChunk(index: 0, text: "Ordine degli eventi."),
            voice: VoiceProfile.standardVoices[0]
        )

        output.play(request)
        await assertEventually { audio.playedData.count == 1 }

        audio.onLevelsUpdate?([0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7])
        audio.onProgressUpdate?(0.4)
        audio.onProgressUpdate?(1.0)
        audio.completePlayback(at: 0)

        await assertEventually { collector.containsFinished(request.id) }
        XCTAssertEqual(
            collector.kinds,
            ["started", "levels", "progress", "progress", "finished"]
        )

        for event in collector.events {
            switch event {
            case .started(let started):
                XCTAssertEqual(started.requestID, request.id)
            case .progress(let requestID, _):
                XCTAssertEqual(requestID, request.id)
            case .levels(let requestID, _):
                XCTAssertEqual(requestID, request.id)
            case .finished(let requestID):
                XCTAssertEqual(requestID, request.id)
            case .synthesisFailed(let requestID, _):
                XCTFail("Nessun fallimento atteso, ricevuto \(requestID)")
            }
        }
    }

    // MARK: - Fallback

    func testPipelineFailureFallsBackToSystemVoice() async {
        let (output, pipeline, audio, collector, cleanup) = makeSystem()
        defer {
            collector.stop()
            cleanup()
        }
        pipeline.error = NSError(
            domain: "SpeechOutputTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "backend offline"]
        )

        let request = SpeechRequest(
            chunk: ReadingChunk(index: 0, text: "Testo di fallback."),
            voice: VoiceProfile.standardVoices[0],
            speed: 1.2,
            steps: 8
        )

        output.play(request)
        await assertEventually { audio.fallbackTexts.count == 1 }
        await assertEventually { collector.started.last?.source == .system }

        XCTAssertTrue(audio.playedData.isEmpty)
        XCTAssertEqual(audio.fallbackTexts.first, request.chunk.text)
        XCTAssertTrue(collector.containsFailed(request.id))

        let started = collector.started.last
        XCTAssertEqual(started?.chunkID, request.chunk.id)
        XCTAssertNotNil(started?.notice)

        audio.completeFallback()
        await assertEventually { collector.containsFinished(request.id) }
    }

    // MARK: - Cache asincrona

    func testAsyncCacheReadReturnsDiskHitAndPromotesToRAM() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LettoreSpeechOutputTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let writer = AudioCacheManager(customCacheDirectory: tempDirectory)
        let data = Data("AUDIO_SU_DISCO".utf8)
        let key = writer.cacheKey(for: "Cache su disco.", voiceId: "IT-M1", speed: 1.0, steps: 8)
        writer.storeAudio(data, for: key)

        let fileURL = tempDirectory.appendingPathComponent("\(key).wav")
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: fileURL.path) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let reader = AudioCacheManager(customCacheDirectory: tempDirectory)
        let diskHit = await reader.getAudioAsync(for: key)
        XCTAssertEqual(diskHit?.source, .disk)
        XCTAssertEqual(diskHit?.data, data)

        let ramHit = await reader.getAudioAsync(for: key)
        XCTAssertEqual(ramHit?.source, .memory)
    }

    // MARK: - Helper

    private func makeSystem() -> (
        SpeechOutput,
        FakeTTSPipeline,
        FakeSpeechAudio,
        EventCollector,
        () -> Void
    ) {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LettoreSpeechOutputTests.\(UUID().uuidString)", isDirectory: true)
        let cache = AudioCacheManager(customCacheDirectory: tempDirectory)
        let pipeline = FakeTTSPipeline()
        let audio = FakeSpeechAudio()
        let output = SpeechOutput(
            audio: audio,
            supertonicPipeline: pipeline,
            speechFallback: NativeSpeechService(),
            cacheManager: cache
        )
        let collector = EventCollector(output.events)
        return (output, pipeline, audio, collector, {
            try? FileManager.default.removeItem(at: tempDirectory)
        })
    }

    private func assertEventually(
        timeout: TimeInterval = 2.0,
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let reached = await waitUntil(timeout: timeout, condition)
        XCTAssertTrue(reached, "Condizione non raggiunta entro \(timeout)s", file: file, line: line)
    }

    @discardableResult
    private func waitUntil(
        timeout: TimeInterval = 2.0,
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return condition()
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
