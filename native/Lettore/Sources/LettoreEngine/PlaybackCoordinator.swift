import Foundation
import AVFoundation
import LettoreCore

/// Coordinatore centrale della riproduzione vocale e avanzamento automatico della coda.
/// Esegue la sintesi vocale tramite il motore neurale Supertonic 3 originale (M1 Marco, F1 Giulia, ecc.)
/// con fallback su sintesi nativa, sincronizzando lo spettro audio a 60fps su AVAudioEngine.
@MainActor
public final class PlaybackCoordinator {
    public let appState: AppState
    public let audioEngine: AudioEngineService
    public let supertonicPipeline: SupertonicTTSPipeline
    public let speechFallback: NativeSpeechService
    
    private var isPlayingSupertonic: Bool = true
    private var isSynthesizing: Bool = false
    
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
        
        // Sincronizza lo spettro audio a 60fps da AVAudioEngine all'appState
        audioEngine.onAudioLevelsUpdate = { [weak appState] levels in
            appState?.liveWaveformLevels = levels
        }
        
        // Sincronizza livelli audio fallback
        speechFallback.onLevelsUpdate = { [weak appState] levels in
            appState?.liveWaveformLevels = levels
        }
        
        // Callback avanzamento automatico per il fallback nativo
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
        audioEngine.stop()
        speechFallback.stop()
        appState.playbackState = .idle
    }
    
    public func playCurrentChunk() {
        guard let current = appState.currentChunk else {
            appState.playbackState = .idle
            return
        }
        guard !isSynthesizing else {
            print("[PlaybackCoordinator] Sintesi già in corso, ignorata chiamata duplicata")
            return
        }
        
        appState.playbackState = .playing
        isSynthesizing = true
        
        Task {
            do {
                let buffer = try await supertonicPipeline.synthesize(
                    text: current.text,
                    voice: appState.selectedVoice,
                    speed: appState.playbackSpeed
                )
                
                print("[PlaybackCoordinator] Supertonic OK — buffer: \(buffer.format), frames: \(buffer.frameLength)")
                
                await MainActor.run {
                    self.isSynthesizing = false
                    self.isPlayingSupertonic = true
                    self.audioEngine.scheduleBuffer(buffer) {
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
                print("[PlaybackCoordinator] Supertonic ERRORE: \(error.localizedDescription). Uso fallback vocale di sistema.")
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
        playCurrentChunk()
    }
}
