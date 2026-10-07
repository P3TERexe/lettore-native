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
    
    // Cache e Coda Preload Ring Buffer (PERF-2, PERF-3)
    private let cacheManager: AudioCacheManager = AudioCacheManager.shared
    private var preloadedWAVs: [UUID: Data] = [:]
    private var activePreloadTasks: [UUID: Task<Void, Never>] = [:]
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
        isSynthesizing = false
        playRequestedTime = 0
        activePreloadTasks.values.forEach { $0.cancel() }
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
            
            // Già in RAM volatile del coordinator
            if preloadedWAVs[chunk.id] != nil { continue }
            
            // Verifica in AudioCacheManager (L1 RAM globale o L2 Disco)
            let cacheKey = cacheManager.cacheKey(
                for: chunk.text,
                voiceId: appState.selectedVoice.id,
                speed: appState.playbackSpeed,
                steps: appState.synthesisSteps
            )
            
            if let cached = cacheManager.getAudio(for: cacheKey) {
                print("[PlaybackCoordinator] Hit cache \(cached.source.rawValue) (0ms latenza) per prefetch chunk \(idx)")
                preloadedWAVs[chunk.id] = cached.data
                continue
            }
            
            // Prefetch asincrono se non già in corso
            if activePreloadTasks[chunk.id] == nil {
                let chunkText = chunk.text
                let voice = appState.selectedVoice
                let speed = appState.playbackSpeed
                let steps = appState.synthesisSteps
                let chunkId = chunk.id
                
                activePreloadTasks[chunkId] = Task { [weak self] in
                    guard let self = self else { return }
                    do {
                        let wavData = try await self.supertonicPipeline.synthesize(
                            text: chunkText,
                            voice: voice,
                            speed: speed,
                            steps: steps
                        )
                        
                        if !Task.isCancelled {
                            self.cacheManager.storeAudio(wavData, for: cacheKey)
                            await MainActor.run {
                                self.preloadedWAVs[chunkId] = wavData
                                self.activePreloadTasks.removeValue(forKey: chunkId)
                                print("[PlaybackCoordinator] Ring buffer prefetch completato per chunk \(idx)")
                            }
                        }
                    } catch {
                        if !Task.isCancelled {
                            await MainActor.run {
                                self.activePreloadTasks.removeValue(forKey: chunkId)
                                print("[PlaybackCoordinator] Errore prefetch chunk \(idx): \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
        }
        
        // Cancella task fuori dalla finestra attiva per risparmiare risorse
        let toCancel = activePreloadTasks.filter { !targetChunkIds.contains($0.key) }
        for (id, task) in toCancel {
            task.cancel()
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
        
        // 1. Hit preloadedWAVs (RAM locale)
        if let cachedWAV = preloadedWAVs[current.id] {
            print("[PlaybackCoordinator] Hit RAM locale per chunk \(current.index) (0ms latenza)")
            preloadedWAVs.removeValue(forKey: current.id)
            isSynthesizing = false
            isPlayingSupertonic = true
            appState.playbackState = .playing
            
            recordFirstChunkLatency()
            managePreloadRingBuffer()
            playAudioData(cachedWAV)
            return
        }
        
        // 2. Hit AudioCacheManager (L1 RAM / L2 Disco)
        let cacheKey = cacheManager.cacheKey(
            for: current.text,
            voiceId: appState.selectedVoice.id,
            speed: appState.playbackSpeed,
            steps: appState.synthesisSteps
        )
        
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
        
        guard !isSynthesizing else {
            print("[PlaybackCoordinator] Sintesi già in corso, ignorata")
            return
        }
        
        isSynthesizing = true
        appState.playbackState = .synthesizing
        
        // Boost primo chunk: se abilitato e siamo a inizio lettura, usa steps ridotti (5) per avvio istantaneo
        let isFirst = current.index == 0 || appState.playbackProgress == 0.0
        let effectiveSteps = (isFirst && appState.isFirstChunkBoostEnabled)
            ? min(appState.synthesisSteps, 5)
            : appState.synthesisSteps
            
        print("[PlaybackCoordinator] Sintesi chunk \(current.index) (steps: \(effectiveSteps), firstChunkBoost: \(isFirst && appState.isFirstChunkBoostEnabled))...")
        
        let text = current.text
        let voice = appState.selectedVoice
        let speed = appState.playbackSpeed
        
        Task {
            let synthStart = CFAbsoluteTimeGetCurrent()
            do {
                let wavData = try await supertonicPipeline.synthesize(
                    text: text,
                    voice: voice,
                    speed: speed,
                    steps: effectiveSteps
                )
                let synthDurationMs = (CFAbsoluteTimeGetCurrent() - synthStart) * 1000.0
                cacheManager.storeAudio(wavData, for: cacheKey)
                
                await MainActor.run {
                    self.isSynthesizing = false
                    self.isPlayingSupertonic = true
                    self.appState.playbackState = .playing
                    self.appState.lastSynthesisLatencyMs = synthDurationMs
                    
                    self.recordFirstChunkLatency()
                    self.managePreloadRingBuffer()
                    self.playAudioData(wavData)
                }
            } catch {
                print("[PlaybackCoordinator] Supertonic ERRORE: \(error.localizedDescription). Uso fallback.")
                await MainActor.run {
                    self.isSynthesizing = false
                    self.isPlayingSupertonic = false
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
