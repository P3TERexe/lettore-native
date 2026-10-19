import Foundation
import AVFoundation
import LettoreCore

/// Coordinatore centrale della riproduzione vocale e avanzamento automatico della coda.
/// Esegue la sintesi vocale tramite il motore neurale Supertonic 3 originale (M1 Marco, F1 Giulia, ecc.)
/// con fallback su sintesi nativa, sincronizzando lo spettro audio a 20fps su AVAudioPlayer.
@MainActor
public final class PlaybackCoordinator {
    public let appState: AppState
    public let audioEngine: AudioEngineService
    public let supertonicPipeline: SupertonicTTSPipeline
    public let speechFallback: NativeSpeechService
    
    private var isPlayingSupertonic: Bool = true
    private var isSynthesizing: Bool = false
    private var synthesisTask: Task<Void, Never>?

    private struct PreloadedAudio {
        let cacheKey: String
        let data: Data
    }

    private struct ActivePreload {
        let cacheKey: String
        let task: Task<Void, Never>
    }

    /// Il backend sintetizza a velocità neutra. La velocità viene applicata una
    /// sola volta dal player: i cambi sono immediati e la cache non si fragmenta.
    private let synthesisSpeed: Float = 1.0
    
    // Cache e Coda Preload Ring Buffer (PERF-2, PERF-3)
    private let cacheManager: AudioCacheManager = AudioCacheManager.shared
    private var preloadedWAVs: [UUID: PreloadedAudio] = [:]
    private var activePreloadTasks: [UUID: ActivePreload] = [:]
    private var playRequestedTime: CFAbsoluteTime = 0
    
    public init(
        appState: AppState,
        audioEngine: AudioEngineService,
        supertonicPipeline: SupertonicTTSPipeline = SupertonicTTSPipeline(),
        speechFallback: NativeSpeechService = NativeSpeechService()
    ) {
        self.appState = appState
        self.audioEngine = audioEngine
        self.supertonicPipeline = supertonicPipeline
        self.speechFallback = speechFallback
        
        audioEngine.onAudioLevelsUpdate = { [weak appState] levels in
            appState?.liveWaveformLevels = levels
        }
        
        audioEngine.onProgressUpdate = { [weak appState] chunkProgress in
            guard let appState = appState else { return }
            let total = Double(appState.readingQueue.count)
            guard total > 0 else {
                appState.playbackProgress = 0.0
                return
            }
            let currentIdx = Double(appState.currentChunk?.index ?? 0)
            let overall = (currentIdx + chunkProgress) / total
            appState.playbackProgress = min(1.0, max(0.0, overall))
        }
        
        speechFallback.onLevelsUpdate = { [weak appState] levels in
            appState?.liveWaveformLevels = levels
        }
        
        speechFallback.onProgressUpdate = { [weak appState] chunkProgress in
            guard let appState = appState else { return }
            let total = Double(appState.readingQueue.count)
            guard total > 0 else {
                appState.playbackProgress = 0.0
                return
            }
            let currentIdx = Double(appState.currentChunk?.index ?? 0)
            let overall = (currentIdx + chunkProgress) / total
            appState.playbackProgress = min(1.0, max(0.0, overall))
        }
        
        speechFallback.onFinish = { [weak self] in
            guard let self = self else { return }
            if self.appState.advanceChunk() != nil {
                self.playCurrentChunk()
            } else {
                self.appState.playbackState = .idle
            }
        }
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
            if isPlayingSupertonic {
                audioEngine.play()
                appState.playbackState = .playing
            } else {
                speechFallback.resume()
                appState.playbackState = .playing
            }
        } else {
            playRequestedTime = CFAbsoluteTimeGetCurrent()
            playCurrentChunk()
        }
    }
    
    public func pause() {
        if isPlayingSupertonic {
            audioEngine.pause()
        } else {
            speechFallback.pause()
        }
        appState.playbackState = .paused
    }
    
    public func stop() {
        synthesisTask?.cancel()
        synthesisTask = nil
        isSynthesizing = false
        playRequestedTime = 0
        activePreloadTasks.values.forEach { $0.task.cancel() }
        activePreloadTasks.removeAll()
        preloadedWAVs.removeAll()
        audioEngine.stop()
        speechFallback.stop()
        appState.playbackState = .idle
        if appState.currentChunk == nil {
            appState.playbackProgress = 0.0
        }
    }
    
    // MARK: - Deep Preload Ring Buffer (PERF-2)
    
    private func managePreloadRingBuffer() {
        guard let current = appState.currentChunk,
              let currentIndex = appState.readingQueue.firstIndex(where: { $0.id == current.id }) else {
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
        guard startIdx <= endIdx else { return }
        
        var targetChunkIds = Set<UUID>()
        
        for idx in startIdx...endIdx {
            let chunk = appState.readingQueue[idx]
            targetChunkIds.insert(chunk.id)

            let cacheKey = cacheManager.cacheKey(
                for: chunk.text,
                voiceId: appState.selectedVoice.id,
                speed: synthesisSpeed,
                steps: appState.synthesisSteps
            )
            
            // Già in RAM volatile del coordinator, ma solo se prodotta con le
            // stesse impostazioni: un cambio voce/step deve invalidare il preload.
            if let preloaded = preloadedWAVs[chunk.id] {
                if preloaded.cacheKey == cacheKey {
                    continue
                }
                preloadedWAVs.removeValue(forKey: chunk.id)
            }

            // Verifica in AudioCacheManager (L1 RAM globale o L2 Disco)
            if let cached = cacheManager.getAudio(for: cacheKey) {
                print("[PlaybackCoordinator] Hit cache \(cached.source.rawValue) (0ms latenza) per prefetch chunk \(idx)")
                preloadedWAVs[chunk.id] = PreloadedAudio(cacheKey: cacheKey, data: cached.data)
                continue
            }
            
            // Prefetch asincrono se non già in corso con la stessa chiave.
            if let active = activePreloadTasks[chunk.id] {
                if active.cacheKey == cacheKey {
                    continue
                }
                active.task.cancel()
                activePreloadTasks.removeValue(forKey: chunk.id)
            }

            let chunkText = chunk.text
            let voice = appState.selectedVoice
            let steps = appState.synthesisSteps
            let chunkId = chunk.id

            let task = Task { [weak self] in
                guard let self = self else { return }
                do {
                    let wavData = try await self.supertonicPipeline.synthesize(
                        text: chunkText,
                        voice: voice,
                        speed: self.synthesisSpeed,
                        steps: steps
                    )

                    if !Task.isCancelled {
                        self.cacheManager.storeAudio(wavData, for: cacheKey)
                        await MainActor.run {
                            // Se voce o step sono cambiati nel frattempo, scarta
                            // il risultato invece di sovrascrivere il prefetch nuovo.
                            guard self.activePreloadTasks[chunkId]?.cacheKey == cacheKey else { return }
                            self.preloadedWAVs[chunkId] = PreloadedAudio(
                                cacheKey: cacheKey,
                                data: wavData
                            )
                            self.activePreloadTasks.removeValue(forKey: chunkId)
                            print("[PlaybackCoordinator] Ring buffer prefetch completato per chunk \(idx)")
                        }
                    }
                } catch {
                    if !Task.isCancelled {
                        await MainActor.run {
                            guard self.activePreloadTasks[chunkId]?.cacheKey == cacheKey else { return }
                            self.activePreloadTasks.removeValue(forKey: chunkId)
                            print("[PlaybackCoordinator] Errore prefetch chunk \(idx): \(error.localizedDescription)")
                        }
                    }
                }
            }
            activePreloadTasks[chunkId] = ActivePreload(cacheKey: cacheKey, task: task)
        }
        
        // Cancella task fuori dalla finestra attiva per risparmiare risorse
        let toCancel = activePreloadTasks.filter { !targetChunkIds.contains($0.key) }
        for (id, active) in toCancel {
            active.task.cancel()
            activePreloadTasks.removeValue(forKey: id)
        }
    }
    
    // MARK: - Orchestrazione Riproduzione & Latenza (PERF-1, PERF-3)
    
    public func playCurrentChunk() {
        guard let current = appState.currentChunk else {
            appState.playbackState = .idle
            return
        }
        
        let playStartTime = CFAbsoluteTimeGetCurrent()
        if playRequestedTime == 0 {
            playRequestedTime = playStartTime
        }

        // Il boost del primo chunk deve entrare nella chiave di cache: altrimenti
        // un audio a 5 step verrebbe riusato come se fosse stato prodotto a 8.
        let isFirst = current.index == 0 || appState.playbackProgress == 0.0
        let effectiveSteps = (isFirst && appState.isFirstChunkBoostEnabled)
            ? min(appState.synthesisSteps, 5)
            : appState.synthesisSteps
        let cacheKey = cacheManager.cacheKey(
            for: current.text,
            voiceId: appState.selectedVoice.id,
            speed: synthesisSpeed,
            steps: effectiveSteps
        )
        
        // 1. Hit preloadedWAVs (RAM locale), solo con la stessa chiave.
        if let preloaded = preloadedWAVs[current.id] {
            preloadedWAVs.removeValue(forKey: current.id)
            if preloaded.cacheKey == cacheKey {
                print("[PlaybackCoordinator] Hit RAM locale per chunk \(current.index) (0ms latenza)")
                isSynthesizing = false
                isPlayingSupertonic = true
                appState.playbackState = .playing

                recordFirstChunkLatency()
                managePreloadRingBuffer()
                playAudioData(preloaded.data)
                return
            }
            print("[PlaybackCoordinator] Preload stantio scartato per chunk \(current.index)")
        }

        // 2. Hit AudioCacheManager (L1 RAM / L2 Disco)
        if let cached = cacheManager.getAudio(for: cacheKey) {
            print("[PlaybackCoordinator] Hit cache \(cached.source.rawValue) (0ms latenza) per chunk corrente \(current.index)")
            isSynthesizing = false
            isPlayingSupertonic = true
            appState.playbackState = .playing
            
            recordFirstChunkLatency()
            managePreloadRingBuffer()
            playAudioData(cached.data)
            return
        }

        // Un prefetch del chunk corrente con impostazioni vecchie non serve più:
        // annullalo prima di sintetizzare con la chiave nuova.
        if let active = activePreloadTasks[current.id], active.cacheKey != cacheKey {
            active.task.cancel()
            activePreloadTasks.removeValue(forKey: current.id)
        }

        // 3. Se il chunk corrente era già in prefetch, attendi quel task invece
        // di inviare una seconda richiesta identica al backend.
        if let active = activePreloadTasks[current.id], active.cacheKey == cacheKey {
            print("[PlaybackCoordinator] Attendo il prefetch in corso per chunk \(current.index)...")
            if isSynthesizing {
                synthesisTask?.cancel()
                synthesisTask = nil
            }
            isSynthesizing = true
            appState.playbackState = .synthesizing
            synthesisTask = Task { [weak self] in
                await active.task.value
                guard !Task.isCancelled, let self = self else { return }
                await MainActor.run {
                    self.synthesisTask = nil
                    self.isSynthesizing = false
                    if let preloaded = self.preloadedWAVs[current.id],
                       preloaded.cacheKey == cacheKey {
                        self.preloadedWAVs.removeValue(forKey: current.id)
                        self.isPlayingSupertonic = true
                        self.appState.isUsingSpeechFallback = false
                        self.appState.speechFallbackNotice = nil
                        self.appState.playbackState = .playing
                        self.recordFirstChunkLatency()
                        self.managePreloadRingBuffer()
                        self.playAudioData(preloaded.data)
                    } else {
                        // Prefetch fallito o invalidato: riparti dalla sintesi normale.
                        self.playCurrentChunk()
                    }
                }
            }
            return
        }
        
        if isSynthesizing {
            // Una nuova richiesta di riproduzione ha la precedenza: annulla la
            // sintesi in volo invece di ignorare il click, che all'utente
            // sembrerebbe un pulsante morto.
            print("[PlaybackCoordinator] Nuova richiesta di play: preempt della sintesi in corso")
            synthesisTask?.cancel()
            synthesisTask = nil
        }
        
        isSynthesizing = true
        appState.playbackState = .synthesizing
        
        print("[PlaybackCoordinator] Sintesi chunk \(current.index) (steps: \(effectiveSteps), firstChunkBoost: \(isFirst && appState.isFirstChunkBoostEnabled))...")
        
        let text = current.text
        let voice = appState.selectedVoice
        
        synthesisTask = Task {
            let synthStart = CFAbsoluteTimeGetCurrent()
            do {
                let wavData = try await supertonicPipeline.synthesize(
                    text: text,
                    voice: voice,
                    speed: synthesisSpeed,
                    steps: effectiveSteps
                )
                guard !Task.isCancelled else { return }
                let synthDurationMs = (CFAbsoluteTimeGetCurrent() - synthStart) * 1000.0
                cacheManager.storeAudio(wavData, for: cacheKey)
                
                await MainActor.run {
                    self.synthesisTask = nil
                    self.isSynthesizing = false
                    self.isPlayingSupertonic = true
                    self.appState.isUsingSpeechFallback = false
                    self.appState.speechFallbackNotice = nil
                    self.appState.playbackState = .playing
                    self.appState.lastSynthesisLatencyMs = synthDurationMs
                    
                    self.recordFirstChunkLatency()
                    self.managePreloadRingBuffer()
                    self.playAudioData(wavData)
                }
            } catch {
                // Cancellazione volontaria (preempt): nessun fallback vocale.
                guard !Task.isCancelled else { return }
                let notice = "Motore Supertonic non raggiungibile su 127.0.0.1:7788 (\(error.localizedDescription)). In riproduzione con la voce di sistema macOS di fallback."
                print("[PlaybackCoordinator] Supertonic ERRORE: \(error.localizedDescription). Uso fallback.")
                await MainActor.run {
                    self.synthesisTask = nil
                    self.isSynthesizing = false
                    self.isPlayingSupertonic = false
                    self.appState.isUsingSpeechFallback = true
                    self.appState.speechFallbackNotice = notice
                    self.appState.playbackState = .playing
                    self.playRequestedTime = 0
                    self.speechFallback.speak(
                        text: current.text,
                        voice: self.appState.selectedVoice,
                        speed: self.appState.playbackSpeed
                    )
                }
            }
        }
    }
    
    private func recordFirstChunkLatency() {
        guard playRequestedTime > 0 else { return }
        let latencyMs = (CFAbsoluteTimeGetCurrent() - playRequestedTime) * 1000.0
        appState.lastFirstChunkLatencyMs = latencyMs
        playRequestedTime = 0
        print("[PlaybackCoordinator] Telemetria First-Chunk Latency: \(String(format: "%.1f", latencyMs))ms")
    }
    
    private func playAudioData(_ data: Data) {
        audioEngine.playWAVData(data, speed: appState.playbackSpeed) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                if self.appState.advanceChunk() != nil {
                    self.playCurrentChunk()
                } else {
                    self.appState.playbackState = .idle
                }
            }
        }
    }
    
    public func skipForward() {
        stop()
        playRequestedTime = CFAbsoluteTimeGetCurrent()
        if appState.advanceChunk() != nil {
            playCurrentChunk()
        } else {
            appState.playbackState = .idle
        }
    }
    
    public func skipBackward() {
        stop()
        playRequestedTime = CFAbsoluteTimeGetCurrent()
        if appState.rewindChunk() != nil {
            playCurrentChunk()
        }
    }
    
    public func jumpToChunk(_ chunk: ReadingChunk) {
        stop()
        playRequestedTime = CFAbsoluteTimeGetCurrent()
        appState.currentChunk = chunk
        let total = Double(appState.readingQueue.count)
        if total > 0 {
            appState.playbackProgress = Double(chunk.index) / total
        }
        playCurrentChunk()
    }
}
