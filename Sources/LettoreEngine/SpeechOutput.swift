import Foundation
import AVFoundation
import LettoreCore

/// Richiesta di riproduzione di un chunk.
///
/// `id` identifica la singola esecuzione, non il chunk: due play dello stesso
/// testo hanno id diversi, così un completamento tardivo della prima non può
/// chiudere la seconda. `speed` è la velocità di ascolto applicata dal player;
/// la sintesi resta a velocità neutra per non frammentare la cache.
public struct SpeechRequest: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let chunk: ReadingChunk
    public let voice: VoiceProfile
    public let speed: Float
    public let steps: Int

    public init(
        id: UUID = UUID(),
        chunk: ReadingChunk,
        voice: VoiceProfile,
        speed: Float = 1.0,
        steps: Int = 8
    ) {
        self.id = id
        self.chunk = chunk
        self.voice = voice
        self.speed = speed
        self.steps = steps
    }
}

/// Motore che ha prodotto l'audio in riproduzione.
public enum VoiceSource: Sendable, Equatable {
    case neural
    case system
}

public struct SpeechStarted: Sendable, Equatable {
    public let requestID: UUID
    public let chunkID: UUID
    public let source: VoiceSource
    /// Tempo di sintesi misurato solo quando l'audio è stato appena generato.
    /// È `nil` per cache hit, preload consumato e voce di sistema.
    public let synthesisDurationMs: Double?
    /// Avviso da mostrare quando si usa la voce di sistema.
    public let notice: String?

    public init(
        requestID: UUID,
        chunkID: UUID,
        source: VoiceSource,
        synthesisDurationMs: Double? = nil,
        notice: String? = nil
    ) {
        self.requestID = requestID
        self.chunkID = chunkID
        self.source = source
        self.synthesisDurationMs = synthesisDurationMs
        self.notice = notice
    }
}

/// Eventi osservabili di una richiesta. `cancelAll` non emette `finished`.
public enum SpeechEvent: Sendable, Equatable {
    case started(SpeechStarted)
    case progress(requestID: UUID, fraction: Double)
    case levels(requestID: UUID, levels: [Float])
    case finished(requestID: UUID)
    case synthesisFailed(requestID: UUID, message: String)
}

/// Output vocale profondo: possiede sintesi, cache L1/L2, prefetch, fallback
/// alla voce di sistema, metering e serializzazione delle richieste.
///
/// `PlaybackCoordinator` fornisce solo la richiesta (chunk, voce, velocità,
/// step) e consuma gli eventi per orchestrare coda e sessione.
@MainActor
public final class SpeechOutput {
    public let supertonicPipeline: any TTSPipelineProtocol
    private let speechFallback: NativeSpeechService

    private let audio: any SpeechAudioBackend
    private let cacheManager: AudioCacheManager
    /// Il backend sintetizza a velocità neutra; la velocità di ascolto è
    /// applicata dal player, così un cambio di velocità non invalida la cache.
    private let synthesisSpeed: Float = 1.0

    private let eventsStream: AsyncStream<SpeechEvent>
    private let eventsContinuation: AsyncStream<SpeechEvent>.Continuation

    private enum Resolution {
        case audio(Data, synthesisDurationMs: Double?)
        case failed(Error)
        case cancelled
    }

    /// Esito di un prefetch. Un fallimento va distinto dalla cancellazione:
    /// il play che stava aspettando il prefetch deve fallire subito, senza
    /// ripetere la sintesi e sommare un secondo timeout.
    private enum PreloadOutcome {
        case success(Data)
        case failure(Error)
        case cancelled
    }

    /// Identifica la richiesta corrente: ogni play apre una generazione nuova
    /// e i callback della precedente vengono ignorati.
    private var generation: UInt64 = 0
    private var activeRequest: SpeechRequest?
    private var activeVoiceSource: VoiceSource?
    private var playbackTask: Task<Void, Never>?
    /// Ultima velocità richiesta dall'utente. Il player la applica all'avvio
    /// della riproduzione, così un cambio durante la sintesi vale subito per
    /// il chunk che sta per partire.
    private var currentSpeed: Float = 1.0

    private var preloadTasks: [String: Task<PreloadOutcome, Never>] = [:]
    private var preloadTokens: [String: UUID] = [:]

    public var events: AsyncStream<SpeechEvent> { eventsStream }

    public convenience init(
        audioEngine: AudioEngineService,
        supertonicPipeline: any TTSPipelineProtocol = SupertonicTTSPipeline(),
        speechFallback: NativeSpeechService = NativeSpeechService()
    ) {
        self.init(
            audio: SystemSpeechAudioBackend(
                audioEngine: audioEngine,
                speechFallback: speechFallback
            ),
            supertonicPipeline: supertonicPipeline,
            speechFallback: speechFallback,
            cacheManager: .shared
        )
    }

    /// Inizializzatore interno per i test: sostituisce l'uscita audio reale con
    /// un fake, senza allargare l'API pubblica.
    init(
        audio: any SpeechAudioBackend,
        supertonicPipeline: any TTSPipelineProtocol,
        speechFallback: NativeSpeechService,
        cacheManager: AudioCacheManager
    ) {
        self.audio = audio
        self.supertonicPipeline = supertonicPipeline
        self.speechFallback = speechFallback
        self.cacheManager = cacheManager

        let (stream, continuation) = AsyncStream.makeStream(of: SpeechEvent.self)
        self.eventsStream = stream
        self.eventsContinuation = continuation

        audio.onLevelsUpdate = { [weak self] levels in
            self?.emitLevels(levels)
        }
        audio.onProgressUpdate = { [weak self] fraction in
            self?.emitProgress(fraction)
        }
    }

    isolated deinit {
        playbackTask?.cancel()
        preloadTasks.values.forEach { $0.cancel() }
        eventsContinuation.finish()
    }

    // MARK: - API

    public func play(_ request: SpeechRequest) {
        generation &+= 1
        let generation = self.generation

        playbackTask?.cancel()
        playbackTask = nil
        activeRequest = nil
        activeVoiceSource = nil
        audio.stop()

        activeRequest = request
        currentSpeed = request.speed
        let key = cacheKey(for: request)

        playbackTask = Task { [weak self] in
            guard let self else { return }
            let resolution = await self.resolveAudio(
                for: request,
                key: key,
                generation: generation
            )
            guard self.isCurrent(request, generation: generation), !Task.isCancelled else {
                return
            }

            switch resolution {
            case .audio(let data, let synthesisDurationMs):
                self.startNeuralPlayback(
                    data,
                    for: request,
                    generation: generation,
                    synthesisDurationMs: synthesisDurationMs
                )
            case .failed(let error):
                self.startSystemVoiceFallback(
                    for: request,
                    generation: generation,
                    error: error
                )
            case .cancelled:
                break
            }
        }
    }

    /// Scalda cache e prefetch senza riprodurre. Le richieste fuori dalla
    /// finestra passata dal coordinator vengono cancellate; il dato pronto
    /// resta nella cache L1, quindi non serve una seconda mappa di risultati.
    public func preload(_ requests: [SpeechRequest]) {
        let wantedKeys = Set(requests.map { cacheKey(for: $0) })

        for key in preloadTasks.keys where !wantedKeys.contains(key) {
            preloadTasks[key]?.cancel()
            preloadTasks.removeValue(forKey: key)
            preloadTokens.removeValue(forKey: key)
        }

        var scheduled = Set<String>()
        for request in requests {
            let key = cacheKey(for: request)
            guard scheduled.insert(key).inserted, preloadTasks[key] == nil else { continue }
            startPreload(for: request, key: key)
        }
    }

    /// Ferma sintesi, prefetch, riproduzione neurale e voce di sistema senza
    /// emettere `finished` per la richiesta interrotta.
    public func cancelAll() {
        generation &+= 1
        playbackTask?.cancel()
        playbackTask = nil
        activeRequest = nil
        activeVoiceSource = nil

        for task in preloadTasks.values {
            task.cancel()
        }
        preloadTasks.removeAll()
        preloadTokens.removeAll()

        audio.stop()
    }

    public func pause() {
        audio.pause(source: activeVoiceSource ?? .neural)
    }

    public func resume() {
        audio.resume(source: activeVoiceSource ?? .neural)
    }

    public func setSpeed(_ speed: Float) {
        currentSpeed = speed
        audio.setSpeed(speed)
    }

    // MARK: - Risoluzione audio

    private func resolveAudio(
        for request: SpeechRequest,
        key: String,
        generation: UInt64
    ) async -> Resolution {
        if let cached = await cacheManager.getAudioAsync(for: key) {
            return .audio(cached.data, synthesisDurationMs: nil)
        }

        guard isCurrent(request, generation: generation), !Task.isCancelled else {
            return .cancelled
        }

        if let activePreload = preloadTasks[key] {
            switch await activePreload.value {
            case .success(let data):
                guard isCurrent(request, generation: generation), !Task.isCancelled else {
                    return .cancelled
                }
                return .audio(data, synthesisDurationMs: nil)
            case .failure(let error):
                guard isCurrent(request, generation: generation), !Task.isCancelled else {
                    return .cancelled
                }
                return .failed(error)
            case .cancelled:
                break
            }
        }

        // Un preload può essersi completato tra la prima lettura e questa:
        // il suo dato è in L1, non in una mappa separata.
        if let cached = await cacheManager.getAudioAsync(for: key) {
            return .audio(cached.data, synthesisDurationMs: nil)
        }

        guard isCurrent(request, generation: generation), !Task.isCancelled else {
            return .cancelled
        }

        let startedAt = CFAbsoluteTimeGetCurrent()
        do {
            let data = try await supertonicPipeline.synthesize(
                text: request.chunk.text,
                voice: request.voice,
                speed: synthesisSpeed,
                steps: request.steps
            )
            guard isCurrent(request, generation: generation), !Task.isCancelled else {
                return .cancelled
            }

            let durationMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000.0
            cacheManager.storeAudio(data, for: key)
            return .audio(data, synthesisDurationMs: durationMs)
        } catch {
            guard isCurrent(request, generation: generation), !Task.isCancelled else {
                return .cancelled
            }
            return .failed(error)
        }
    }

    // MARK: - Prefetch

    private func startPreload(for request: SpeechRequest, key: String) {
        let token = UUID()
        preloadTokens[key] = token

        let text = request.chunk.text
        let voice = request.voice
        let steps = request.steps

        let task = Task<PreloadOutcome, Never> { [weak self] in
            guard let self else { return .cancelled }

            let outcome: PreloadOutcome
            if let cached = await self.cacheManager.getAudioAsync(for: key) {
                outcome = .success(cached.data)
            } else if Task.isCancelled {
                outcome = .cancelled
            } else {
                do {
                    let synthesized = try await self.supertonicPipeline.synthesize(
                        text: text,
                        voice: voice,
                        speed: self.synthesisSpeed,
                        steps: steps
                    )
                    if Task.isCancelled {
                        outcome = .cancelled
                    } else {
                        self.cacheManager.storeAudio(synthesized, for: key)
                        outcome = .success(synthesized)
                    }
                } catch {
                    outcome = Task.isCancelled || error is CancellationError
                        ? .cancelled
                        : .failure(error)
                }
            }

            guard self.preloadTokens[key] == token else { return outcome }

            self.preloadTasks.removeValue(forKey: key)
            self.preloadTokens.removeValue(forKey: key)
            return outcome
        }

        preloadTasks[key] = task
    }

    // MARK: - Riproduzione

    private func startNeuralPlayback(
        _ data: Data,
        for request: SpeechRequest,
        generation: UInt64,
        synthesisDurationMs: Double?
    ) {
        guard isCurrent(request, generation: generation) else { return }

        activeVoiceSource = .neural
        emit(.started(SpeechStarted(
            requestID: request.id,
            chunkID: request.chunk.id,
            source: .neural,
            synthesisDurationMs: synthesisDurationMs
        )))

        guard isCurrent(request, generation: generation) else { return }

        audio.play(data: data, speed: currentSpeed) { [weak self] success in
            guard let self else { return }
            guard success else {
                guard self.isCurrent(request, generation: generation) else { return }
                // Il payload è arrivato dal backend o dalla cache ma non è
                // riproducibile: invalida la chiave e usa subito la voce di
                // sistema, senza saltare il chunk in silenzio.
                self.cacheManager.removeAudio(for: self.cacheKey(for: request))
                self.startSystemVoiceFallback(
                    for: request,
                    generation: generation,
                    error: NSError(
                        domain: "SpeechOutput",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "L'audio ricevuto non è riproducibile."
                        ]
                    ),
                    notice: "L'audio neurale non è riproducibile: riproduzione con la voce di sistema macOS."
                )
                return
            }
            self.finish(request, generation: generation)
        }
    }

    private func startSystemVoiceFallback(
        for request: SpeechRequest,
        generation: UInt64,
        error: Error,
        notice: String? = nil
    ) {
        guard isCurrent(request, generation: generation) else { return }

        let message = error.localizedDescription
        emit(.synthesisFailed(requestID: request.id, message: message))

        let fallbackNotice = notice
            ?? "Motore Supertonic non raggiungibile su 127.0.0.1:7788 (\(message)). In riproduzione con la voce di sistema macOS di fallback."
        activeVoiceSource = .system
        emit(.started(SpeechStarted(
            requestID: request.id,
            chunkID: request.chunk.id,
            source: .system,
            notice: fallbackNotice
        )))

        guard isCurrent(request, generation: generation) else { return }

        audio.speakFallback(
            text: request.chunk.text,
            voice: request.voice,
            speed: currentSpeed
        ) { [weak self] in
            self?.finish(request, generation: generation)
        }
    }

    private func finish(_ request: SpeechRequest, generation: UInt64) {
        guard isCurrent(request, generation: generation) else { return }
        activeRequest = nil
        activeVoiceSource = nil
        emit(.finished(requestID: request.id))
    }

    // MARK: - Eventi e cache

    private func cacheKey(for request: SpeechRequest) -> String {
        cacheManager.cacheKey(
            for: request.chunk.text,
            voiceId: request.voice.id,
            speed: synthesisSpeed,
            steps: request.steps
        )
    }

    private func isCurrent(_ request: SpeechRequest, generation: UInt64) -> Bool {
        self.generation == generation && activeRequest?.id == request.id
    }

    private func emit(_ event: SpeechEvent) {
        eventsContinuation.yield(event)
    }

    private func emitProgress(_ fraction: Double) {
        guard let request = activeRequest else { return }
        emit(.progress(requestID: request.id, fraction: fraction))
    }

    private func emitLevels(_ levels: [Float]) {
        guard let request = activeRequest else { return }
        emit(.levels(requestID: request.id, levels: levels))
    }
}

// MARK: - Backend audio interno

@MainActor
protocol SpeechAudioBackend: AnyObject {
    var onLevelsUpdate: (([Float]) -> Void)? { get set }
    var onProgressUpdate: ((Double) -> Void)? { get set }

    func play(data: Data, speed: Float, onComplete: @escaping (Bool) -> Void)
    func speakFallback(
        text: String,
        voice: VoiceProfile,
        speed: Float,
        onComplete: @escaping () -> Void
    )
    func pause(source: VoiceSource)
    func resume(source: VoiceSource)
    func stop()
    func setSpeed(_ speed: Float)
}

/// Adapter reale: AVAudioPlayer per il neurale, AVSpeechSynthesizer per il
/// fallback. L'interfaccia resta quella dell'output, non dei due servizi.
@MainActor
final class SystemSpeechAudioBackend: SpeechAudioBackend {
    private let audioEngine: AudioEngineService
    private let speechFallback: NativeSpeechService

    var onLevelsUpdate: (([Float]) -> Void)? {
        didSet {
            audioEngine.onAudioLevelsUpdate = onLevelsUpdate
            speechFallback.onLevelsUpdate = onLevelsUpdate
        }
    }

    var onProgressUpdate: ((Double) -> Void)? {
        didSet {
            audioEngine.onProgressUpdate = onProgressUpdate
            speechFallback.onProgressUpdate = onProgressUpdate
        }
    }

    init(audioEngine: AudioEngineService, speechFallback: NativeSpeechService) {
        self.audioEngine = audioEngine
        self.speechFallback = speechFallback
    }

    func play(data: Data, speed: Float, onComplete: @escaping (Bool) -> Void) {
        audioEngine.playWAVData(data, speed: speed, onComplete: onComplete)
    }

    func speakFallback(
        text: String,
        voice: VoiceProfile,
        speed: Float,
        onComplete: @escaping () -> Void
    ) {
        speechFallback.onFinish = onComplete
        speechFallback.speak(text: text, voice: voice, speed: speed)
    }

    func pause(source: VoiceSource) {
        switch source {
        case .neural:
            audioEngine.pause()
        case .system:
            speechFallback.pause()
        }
    }

    func resume(source: VoiceSource) {
        switch source {
        case .neural:
            audioEngine.play()
        case .system:
            speechFallback.resume()
        }
    }

    func stop() {
        speechFallback.onFinish = nil
        speechFallback.stop()
        audioEngine.stop()
    }

    func setSpeed(_ speed: Float) {
        audioEngine.setSpeed(speed)
    }
}
