import Foundation
import LettoreCore

/// Coordinatore della riproduzione vocale e dell'avanzamento automatico della
/// coda. Possiede sessione, paging e callback verso `AppState`; sintesi, cache,
/// prefetch, fallback e metering vivono in `SpeechOutput`.
@MainActor
public final class PlaybackCoordinator {
    public let appState: AppState
    public let audioEngine: AudioEngineService

    /// Superficie pubblica usata dallo Studio per verificare il backend.
    /// Il coordinatore non chiama direttamente la pipeline.
    public var supertonicPipeline: any TTSPipelineProtocol {
        speechOutput.supertonicPipeline
    }

    private let speechOutput: SpeechOutput
    private var speechEventsTask: Task<Void, Never>?
    /// Identifica il play corrente: gli eventi di una richiesta cancellata non
    /// possono far avanzare la coda della richiesta nuova.
    private var activeSpeechRequestID: UUID?

    // MARK: - Lettura continua (DSA-11)
    /// Chiamata quando la coda sta per esaurirsi. Restituisce `true` se sono
    /// stati accodati nuovi chunk.
    public var onQueueLow: (() async -> Bool)?
    /// Chiamata quando la sessione di riproduzione termina (coda finita o
    /// stop esplicito dell'utente).
    public var onSessionEnded: (() -> Void)?
    /// Chiamata all'inizio di ogni `playCurrentChunk`, prima della sintesi:
    /// copre play, skip, jump, avanzamento automatico e ripresa da pausa.
    /// Non viene chiamata a ogni aggiornamento di progresso audio.
    public var onCurrentChunkChanged: ((ReadingChunk) -> Void)?
    /// Chiamata una sola volta quando la sessione di riproduzione finisce
    /// davvero: stop esplicito, coda esaurita, pagina finale senza nuovi chunk
    /// o assenza di un chunk corrente.
    public var onPlaybackEnded: (() -> Void)?

    private var pagingTask: Task<Void, Never>?
    private var isFetchingMoreText = false
    private var pendingPlayAfterFetch = false
    /// Evita `onPlaybackEnded` duplicati per lo stesso stop o fine coda.
    private var didNotifyPlaybackEnd = false
    private var playRequestedTime: CFAbsoluteTime = 0

    public init(
        appState: AppState,
        audioEngine: AudioEngineService,
        supertonicPipeline: any TTSPipelineProtocol = SupertonicTTSPipeline(),
        speechFallback: NativeSpeechService = NativeSpeechService()
    ) {
        self.appState = appState
        self.audioEngine = audioEngine

        let output = SpeechOutput(
            audioEngine: audioEngine,
            supertonicPipeline: supertonicPipeline,
            speechFallback: speechFallback
        )
        self.speechOutput = output

        self.speechEventsTask = Task { [weak self, events = output.events] in
            for await event in events {
                guard let self else { return }
                self.handle(event)
            }
        }
    }

    isolated deinit {
        speechEventsTask?.cancel()
    }

    public func togglePlayPause() {
        if appState.playbackState == .playing {
            pause()
        } else {
            play()
        }
    }

    public func play() {
        if appState.playbackState == .paused {
            resume()
        } else {
            playRequestedTime = CFAbsoluteTimeGetCurrent()
            playCurrentChunk()
        }
    }

    public func resume() {
        guard appState.playbackState == .paused else { return }
        speechOutput.resume()
        appState.playbackState = .playing
        // La selezione resta dov'è durante la pausa: alla ripresa si
        // rivaluta il chunk corrente, che potrebbe essere cambiato.
        notifyCurrentChunkChanged()
    }

    public func pause() {
        speechOutput.pause()
        appState.playbackState = .paused
    }

    public func setSpeed(_ speed: Float) {
        appState.setSpeed(speed)
        speechOutput.setSpeed(appState.playbackSpeed)
    }

    /// Ferma la riproduzione.
    ///
    /// `endingSession` è `false` per gli stop interni di skip/jump: in quel
    /// caso la sessione di lettura continua resta aperta, perché l'utente si
    /// sta solo muovendo dentro la coda già catturata.
    public func stop(endingSession: Bool = true) {
        activeSpeechRequestID = nil
        playRequestedTime = 0
        speechOutput.cancelAll()
        if endingSession {
            // Uno skip/jump interno non deve interrompere una richiesta di
            // pagina già in volo: la coda continua a vivere.
            pagingTask?.cancel()
            pagingTask = nil
            isFetchingMoreText = false
            pendingPlayAfterFetch = false
        }
        appState.playbackState = .idle
        if appState.currentChunk == nil {
            appState.playbackProgress = 0.0
        }
        if endingSession {
            onSessionEnded?()
            notifyPlaybackEnded()
        }
    }

    // MARK: - Prefetch (PERF-2)

    private func preloadUpcomingChunks() {
        guard let current = appState.currentChunk,
              let currentIndex = appState.index(of: current) else {
            speechOutput.preload([])
            return
        }

        let depth = max(1, appState.preloadDepth)
        // Se il chunk immediatamente successivo è molto breve (< 25 caratteri), allarga il prefetch
        // a +1 chunk per prevenire buffer starvation su sequenze rapide.
        let nextIdx = currentIndex + 1
        let isNextShort = nextIdx < appState.readingQueue.count && appState.readingQueue[nextIdx].text.count < 25
        let effectiveDepth = isNextShort ? depth + 1 : depth

        let startIdx = currentIndex + 1
        let endIdx = min(currentIndex + effectiveDepth, appState.readingQueue.count - 1)
        guard startIdx <= endIdx else {
            speechOutput.preload([])
            return
        }

        var requests: [SpeechRequest] = []
        requests.reserveCapacity(endIdx - startIdx + 1)
        for idx in startIdx...endIdx {
            requests.append(SpeechRequest(
                chunk: appState.readingQueue[idx],
                voice: appState.selectedVoice,
                speed: appState.playbackSpeed,
                steps: appState.synthesisSteps
            ))
        }
        speechOutput.preload(requests)
    }

    // MARK: - Orchestrazione Riproduzione & Latenza (PERF-1, PERF-3)

    public func playCurrentChunk() {
        guard let current = appState.currentChunk else {
            // Una pagina può essere già in volo: in quel caso la sessione non è
            // finita e il Play deve attendere i nuovi chunk, non chiudere
            // l'highlight prima che arrivino.
            if isFetchingMoreText {
                pendingPlayAfterFetch = true
                appState.playbackState = .synthesizing
                return
            }
            appState.playbackState = .idle
            notifyPlaybackEnded()
            return
        }

        // Segnala il chunk prima della sintesi: il cambio copre play, skip,
        // jump e avanzamento automatico, senza toccare l'highlight a ogni
        // aggiornamento di progresso.
        didNotifyPlaybackEnd = false
        onCurrentChunkChanged?(current)

        // Pianifica il caricamento della pagina successiva quando restano
        // pochi chunk. La richiesta è idempotente e non blocca la sintesi.
        requestMoreTextIfNeeded()

        if playRequestedTime == 0 {
            playRequestedTime = CFAbsoluteTimeGetCurrent()
        }

        // Il boost del primo chunk deve entrare nella chiave di cache: altrimenti
        // un audio a 5 step verrebbe riusato come se fosse stato prodotto a 8.
        let isFirst = current.index == 0 || appState.playbackProgress == 0.0
        let effectiveSteps = (isFirst && appState.isFirstChunkBoostEnabled)
            ? min(appState.synthesisSteps, 5)
            : appState.synthesisSteps

        let request = SpeechRequest(
            chunk: current,
            voice: appState.selectedVoice,
            speed: appState.playbackSpeed,
            steps: effectiveSteps
        )
        activeSpeechRequestID = request.id
        appState.playbackState = .synthesizing
        speechOutput.play(request)
    }

    private func recordFirstChunkLatency() {
        guard playRequestedTime > 0 else { return }
        let latencyMs = (CFAbsoluteTimeGetCurrent() - playRequestedTime) * 1000.0
        appState.lastFirstChunkLatencyMs = latencyMs
        playRequestedTime = 0
        print("[PlaybackCoordinator] Telemetria First-Chunk Latency: \(String(format: "%.1f", latencyMs))ms")
    }

    private func updatePlaybackProgress(_ chunkProgress: Double) {
        let total = Double(appState.readingQueue.count)
        guard total > 0 else {
            appState.playbackProgress = 0.0
            return
        }
        let currentIdx = Double(appState.currentChunk?.index ?? 0)
        let overall = (currentIdx + chunkProgress) / total
        appState.playbackProgress = min(1.0, max(0.0, overall))
    }

    // MARK: - Eventi di SpeechOutput

    private func handle(_ event: SpeechEvent) {
        switch event {
        case .started(let started):
            guard started.requestID == activeSpeechRequestID else { return }

            appState.playbackState = .playing
            if started.source == .neural {
                appState.isUsingSpeechFallback = false
                appState.speechFallbackNotice = nil
                if let synthesisDurationMs = started.synthesisDurationMs {
                    appState.lastSynthesisLatencyMs = synthesisDurationMs
                }
                recordFirstChunkLatency()
                preloadUpcomingChunks()
            } else {
                appState.isUsingSpeechFallback = true
                appState.speechFallbackNotice = started.notice
                playRequestedTime = 0
            }

        case .progress(let requestID, let fraction):
            guard requestID == activeSpeechRequestID else { return }
            updatePlaybackProgress(fraction)

        case .levels(let requestID, let levels):
            guard requestID == activeSpeechRequestID else { return }
            appState.liveWaveformLevels = levels

        case .finished(let requestID):
            guard requestID == activeSpeechRequestID else { return }
            activeSpeechRequestID = nil
            handleChunkFinished()

        case .synthesisFailed(let requestID, let message):
            guard requestID == activeSpeechRequestID else { return }
            print("[PlaybackCoordinator] Sintesi neurale fallita: \(message). Fallback in corso.")
        }
    }

    // MARK: - Continuazione della coda

    /// Richiede nuove pagine quando mancano al massimo 3 chunk alla fine.
    /// Se la coda è già esaurita, `handleChunkFinished` attende la richiesta
    /// in corso prima di dichiarare finita la sessione.
    private func requestMoreTextIfNeeded() {
        guard let current = appState.currentChunk,
              let currentIndex = appState.index(of: current),
              appState.readingQueue.count - currentIndex <= 3,
              !isFetchingMoreText,
              let onQueueLow else {
            return
        }

        isFetchingMoreText = true
        pagingTask = Task { [weak self, onQueueLow] in
            let appended = await onQueueLow()
            guard let self else { return }
            guard !Task.isCancelled else { return }

            self.isFetchingMoreText = false
            self.pagingTask = nil

            if appended {
                self.preloadUpcomingChunks()
                if self.pendingPlayAfterFetch, self.appState.currentChunk != nil {
                    self.pendingPlayAfterFetch = false
                    self.playCurrentChunk()
                }
            } else if self.pendingPlayAfterFetch {
                self.pendingPlayAfterFetch = false
                self.appState.playbackState = .idle
                self.notifyPlaybackEnded()
                self.onSessionEnded?()
            }
        }
    }

    private func handleChunkFinished() {
        if appState.advanceChunk() != nil {
            playCurrentChunk()
            return
        }

        // La coda è finita, ma una pagina potrebbe essere in arrivo: non
        // dichiarare conclusa la sessione prima di saperlo.
        if isFetchingMoreText {
            pendingPlayAfterFetch = true
            appState.playbackState = .synthesizing
            return
        }

        appState.playbackState = .idle
        notifyPlaybackEnded()
        onSessionEnded?()
    }

    public func skipForward() {
        stop(endingSession: false)
        playRequestedTime = CFAbsoluteTimeGetCurrent()
        if appState.advanceChunk() != nil {
            playCurrentChunk()
        } else {
            handleChunkFinished()
        }
    }

    public func skipBackward() {
        stop(endingSession: false)
        playRequestedTime = CFAbsoluteTimeGetCurrent()
        if appState.rewindChunk() != nil {
            playCurrentChunk()
        }
    }

    public func jumpToChunk(_ chunk: ReadingChunk) {
        stop(endingSession: false)
        guard appState.selectChunk(id: chunk.id) != nil else { return }
        playRequestedTime = CFAbsoluteTimeGetCurrent()
        playCurrentChunk()
    }

    // MARK: - Callback sessione

    private func notifyCurrentChunkChanged() {
        guard let current = appState.currentChunk else { return }
        didNotifyPlaybackEnd = false
        onCurrentChunkChanged?(current)
    }

    /// `onPlaybackEnded` deve arrivare una sola volta per sessione: stop
    /// ripetuti o una fine coda seguita da stop non devono duplicarlo.
    private func notifyPlaybackEnded() {
        guard !didNotifyPlaybackEnd else { return }
        didNotifyPlaybackEnd = true
        onPlaybackEnded?()
    }
}

// MARK: - Lettura continua (DSA-11)

/// Il coordinatore reale è il sink usato in produzione dal
/// `ContinuousReadingController`; nei test viene sostituito da un finto.
extension PlaybackCoordinator: ContinuousPlaybackSink {}
