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
    /// Chiamata all'inizio di uno stop esplicito dell'utente
    /// (`stopAndClearQueue`): invalida catture e preparazioni ancora in volo,
    /// così una richiesta partita prima dello stop non ripopola la coda appena
    /// svuotata. Non viene chiamata dagli stop interni di skip/jump né dalla
    /// fine naturale della coda.
    public var onExplicitStop: (() -> Void)?

    private var pagingTask: Task<Void, Never>?
    private var isFetchingMoreText = false
    private var pendingPlayAfterFetch = false
    /// Evita `onPlaybackEnded` duplicati per lo stesso stop o fine coda.
    private var didNotifyPlaybackEnd = false
    /// Evita `onSessionEnded` duplicati: la sessione si chiude una sola volta,
    /// sia per fine coda sia per stop esplicito (anche ripetuto).
    private var didNotifySessionEnd = false
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
        // Durante la sintesi non esiste una pausa reale: riavviare qui
        // cancellerebbe la richiesta in volo e rimanderebbe l'audio a ogni tap.
        guard appState.playbackState != .synthesizing else { return }
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

    /// Dimentica i fallimenti di preload dopo un reconnect riuscito al
    /// backend, così il prossimo play prova davvero la sintesi neurale.
    public func clearSynthesisFailures() {
        speechOutput.clearSynthesisFailures()
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
        if endingSession {
            speechOutput.cancelAll()
        } else {
            // Skip/jump: il prefetch resta vivo, così il chunk nuovo può
            // riusare la sintesi già avviata invece di rifarla.
            speechOutput.cancelPlayback()
        }
        if endingSession {
            // Uno skip/jump interno non deve interrompere una richiesta di
            // pagina già in volo: la coda continua a vivere.
            pagingTask?.cancel()
            pagingTask = nil
            isFetchingMoreText = false
            pendingPlayAfterFetch = false
        }
        appState.playbackState = .idle
        appState.liveWaveformLevels = AudioEngineService.idleWaveformLevels
        if appState.currentChunk == nil {
            appState.playbackProgress = 0.0
        }
        if endingSession {
            notifySessionEnded()
            notifyPlaybackEnded()
        }
    }

    /// Ferma la lettura e svuota la coda in un'unica azione esplicita.
    ///
    /// `stop(endingSession:)` interrompe audio, sintesi, prefetch, paging e
    /// fallback vocale, oltre a chiudere la sessione continua. `clearQueue`
    /// azzera coda, chunk corrente e progresso senza toccare il documento o
    /// la bozza di input. La fine sessione è già emessa da `stop` e
    /// `notifyPlaybackEnded` è idempotente: arriva una sola volta anche se lo
    /// stop viene ripetuto o la coda era terminata.
    ///
    /// `onExplicitStop` arriva per primo: invalida catture e preparazioni in
    /// volo, altrimenti una richiesta partita prima dello stop potrebbe
    /// ripopolare la coda subito dopo averla svuotata.
    public func stopAndClearQueue() {
        onExplicitStop?()
        stop(endingSession: true)
        appState.clearQueue()
        // Lo stop esplicito chiude la sessione: il badge "voce di sistema"
        // descriveva l'audio appena interrotto, non la coda svuotata. Senza
        // questo azzeramento resterebbe visibile fino al play successivo.
        appState.isUsingSpeechFallback = false
        appState.speechFallbackNotice = nil
        // Anche il banner della cattura descriveva una richiesta che lo stop
        // ha abbandonato: senza questo azzeramento resterebbe a schermo fino
        // alla cattura successiva. Le telemetrie di latenza restano intatte:
        // sono misure storiche, non stato della sessione.
        appState.continuationNotice = nil
        appState.playbackProgress = 0.0
        appState.liveWaveformLevels = AudioEngineService.idleWaveformLevels
        notifyPlaybackEnded()
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
            let chunk = appState.readingQueue[idx]
            // Il prefetch parte da current+1 e non vede mai il chunk 0, quindi
            // richiede sempre gli step pieni. Il boost del primo chunk resta al
            // play, che ricalcola gli step (e la chiave di cache) sul chunk
            // corrente se un salto lo rende il primo della sessione.
            let steps = Self.effectiveSteps(
                total: appState.synthesisSteps,
                isFirstChunk: false,
                boostEnabled: appState.isFirstChunkBoostEnabled
            )
            requests.append(SpeechRequest(
                chunk: chunk,
                voice: appState.selectedVoice,
                speed: appState.playbackSpeed,
                steps: steps
            ))
        }
        speechOutput.preload(requests)
    }

    // MARK: - Orchestrazione Riproduzione & Latenza (PERF-1, PERF-3)

    /// Step di sintesi effettivi per un chunk.
    ///
    /// Il boost del primo chunk riduce la qualità solo sul preset bilanciato:
    /// la decisione spetta a `SynthesisQuality.isBoostApplicable(steps:)`, unica
    /// policy condivisa con la UI. Con Turbo (5) e Hi-Fi (12) non si tocca
    /// nulla, altrimenti il primo chunk suonerebbe diverso dal resto e la
    /// qualità scelta dall'utente non sarebbe reale.
    public nonisolated static func effectiveSteps(
        total: Int,
        isFirstChunk: Bool,
        boostEnabled: Bool
    ) -> Int {
        guard isFirstChunk, boostEnabled else { return total }
        guard SynthesisQuality.isBoostApplicable(steps: total) else { return total }
        return min(total, SynthesisQuality.firstChunkBoostSteps)
    }

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

        // Un chunk esiste: un eventuale Play rimasto in attesa della pagina è
        // stato soddisfatto da questo play (skip, jump o nuova sessione). Senza
        // questo azzeramento la fetch in volo riavvierebbe o chiuderebbe la
        // coda appena avviata.
        pendingPlayAfterFetch = false

        // Segnala il chunk prima della sintesi: il cambio copre play, skip,
        // jump e avanzamento automatico, senza toccare l'highlight a ogni
        // aggiornamento di progresso.
        didNotifyPlaybackEnd = false
        didNotifySessionEnd = false
        onCurrentChunkChanged?(current)

        // Pianifica il caricamento della pagina successiva quando restano
        // pochi chunk. La richiesta è idempotente e non blocca la sintesi.
        requestMoreTextIfNeeded()

        if playRequestedTime == 0 {
            playRequestedTime = CFAbsoluteTimeGetCurrent()
        }

        // Gli step effettivi devono entrare nella chiave di cache: altrimenti
        // un audio a 5 step verrebbe riusato come se fosse stato prodotto a 8.
        let isFirst = current.index == 0 || appState.playbackProgress == 0.0
        let effectiveSteps = Self.effectiveSteps(
            total: appState.synthesisSteps,
            isFirstChunk: isFirst,
            boostEnabled: appState.isFirstChunkBoostEnabled
        )

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
            // Durante il silenzio arriva lo stesso array 20 volte al secondo:
            // riassegnarlo invalida WaveformBarsView inutilmente.
            if levels != appState.liveWaveformLevels {
                appState.liveWaveformLevels = levels
            }

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
                self.notifySessionEnded()
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
        notifySessionEnded()
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
        didNotifySessionEnd = false
        onCurrentChunkChanged?(current)
    }

    /// `onSessionEnded` deve arrivare una sola volta per sessione: stop
    /// ripetuti o una fine coda seguita da stop non devono richiudere la
    /// sessione continua.
    private func notifySessionEnded() {
        guard !didNotifySessionEnd else { return }
        didNotifySessionEnd = true
        onSessionEnded?()
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
