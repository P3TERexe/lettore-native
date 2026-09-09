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
    
    // Cache per il preloading del chunk successivo
    private var preloadedWAVs: [UUID: Data] = [:]
    private var preloadTask: Task<Void, Never>? = nil
    
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
        preloadTask?.cancel()
        preloadTask = nil
        preloadedWAVs.removeAll()
        audioEngine.stop()
        speechFallback.stop()
        appState.playbackState = .idle
        if appState.currentChunk == nil {
            appState.playbackProgress = 0.0
        }
    }
    
    private func preloadNextChunk() {
        guard let current = appState.currentChunk,
              let currentIndex = appState.readingQueue.firstIndex(where: { $0.id == current.id }) else {
            return
        }
        
        let nextIndex = currentIndex + 1
        guard nextIndex < appState.readingQueue.count else { return }
        
        let nextChunk = appState.readingQueue[nextIndex]
        if preloadedWAVs[nextChunk.id] != nil { return } // Già in cache
        
        preloadTask?.cancel()
        preloadTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let wavData = try await self.supertonicPipeline.synthesize(
                    text: nextChunk.text,
                    voice: self.appState.selectedVoice,
                    speed: self.appState.playbackSpeed
                )
                
                if !Task.isCancelled {
                    await MainActor.run {
                        self.preloadedWAVs[nextChunk.id] = wavData
                        print("[PlaybackCoordinator] Preload completato in background per chunk \(nextIndex)")
                    }
                }
            } catch {
                print("[PlaybackCoordinator] Errore preloading chunk \(nextIndex): \(error.localizedDescription)")
            }
        }
    }
    
    public func playCurrentChunk() {
        guard let current = appState.currentChunk else {
            appState.playbackState = .idle
            return
        }
        
        appState.playbackState = .playing
        
        if let cachedWAV = preloadedWAVs[current.id] {
            print("[PlaybackCoordinator] Hit cache locale per chunk corrente (nessuna attesa)!")
            preloadedWAVs.removeValue(forKey: current.id)
            isSynthesizing = false
            isPlayingSupertonic = true
            
            preloadNextChunk() // Avvia il preload del successivo mentre suona
            
            audioEngine.playWAVData(cachedWAV, speed: appState.playbackSpeed) {
                Task { @MainActor in
                    if self.appState.advanceChunk() != nil {
                        self.playCurrentChunk()
                    } else {
                        self.appState.playbackState = .idle
                    }
                }
            }
            return
        }
        
        guard !isSynthesizing else {
            print("[PlaybackCoordinator] Sintesi già in corso, ignorata")
            return
        }
        
        isSynthesizing = true
        print("[PlaybackCoordinator] Cache miss, sintetizzo chunk corrente...")
        
        Task {
            do {
                let wavData = try await supertonicPipeline.synthesize(
                    text: current.text,
                    voice: appState.selectedVoice,
                    speed: appState.playbackSpeed
                )
                
                print("[PlaybackCoordinator] Supertonic OK — \(wavData.count) bytes WAV")
                
                await MainActor.run {
                    self.isSynthesizing = false
                    self.isPlayingSupertonic = true
                    
                    self.preloadNextChunk() // Avvia il preload del successivo mentre suona
                    
                    self.audioEngine.playWAVData(wavData, speed: self.appState.playbackSpeed) {
                        Task { @MainActor in
                            if self.appState.advanceChunk() != nil {
                                self.playCurrentChunk()
                            } else {
                                self.appState.playbackState = .idle
                            }
                        }
                    }
                }
            } catch {
                print("[PlaybackCoordinator] Supertonic ERRORE: \(error.localizedDescription). Uso fallback.")
                await MainActor.run {
                    self.isSynthesizing = false
                    self.isPlayingSupertonic = false
                    self.speechFallback.speak(
                        text: current.text,
                        voice: self.appState.selectedVoice,
                        speed: self.appState.playbackSpeed
                    )
                }
            }
        }
    }
    
    public func skipForward() {
        stop()
        if appState.advanceChunk() != nil {
            playCurrentChunk()
        } else {
            appState.playbackState = .idle
        }
    }
    
    public func skipBackward() {
        stop()
        if appState.rewindChunk() != nil {
            playCurrentChunk()
        }
    }
    
    public func jumpToChunk(_ chunk: ReadingChunk) {
        stop()
        appState.currentChunk = chunk
        let total = Double(appState.readingQueue.count)
        if total > 0 {
            appState.playbackProgress = Double(chunk.index) / total
        }
        playCurrentChunk()
    }
}
