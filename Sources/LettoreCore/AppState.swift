import Foundation
import Observation

/// Stato applicativo globale reattivo conforme all'Observation Framework di Swift 6.
@Observable
public final class AppState: @unchecked Sendable {
    
    // MARK: - Proprietà di Riproduzione
    public var playbackState: PlaybackState = .idle
    public var currentChunk: ReadingChunk? = nil
    public var readingQueue: [ReadingChunk] = []
    public var currentWordIndex: Int? = nil
    /// Progresso complessivo della riproduzione nella coda (0.0 ... 1.0)
    public var playbackProgress: Double = 0.0
    
    // MARK: - Impostazioni Audio & Voce
    public var playbackSpeed: Float = 1.05
    public var volume: Float = 1.0
    public var selectedLanguage: String = "it" {
        didSet {
            // Quando cambia la lingua, aggiorna automaticamente la voce selezionata
            // alla prima voce disponibile in quella lingua.
            if let firstVoice = filteredVoices.first {
                selectedVoice = firstVoice
            }
        }
    }
    public var selectedVoice: VoiceProfile = VoiceProfile.standardVoices.first(where: { $0.id == "IT-M1" }) ?? VoiceProfile.standardVoices[0]
    public var availableVoices: [VoiceProfile] = VoiceProfile.standardVoices
    
    public var filteredVoices: [VoiceProfile] {
        return availableVoices.filter { $0.language == selectedLanguage }
    }
    
    // MARK: - Performance Vocale & Telemetria (PERF-1, PERF-2, PERF-3)
    /// Precisione di generazione Supertonic (default: 8 step, turbo: 5-6 step, hi-fi: 10-12 step)
    public var synthesisSteps: Int = 8
    /// Attiva la sintesi a bassa latenza per il primo frammento audio (chunk 0) per avvio istantaneo
    public var isFirstChunkBoostEnabled: Bool = true
    /// Profondità del buffer circolare di pre-caricamento (2 = precarica N+1 e N+2)
    public var preloadDepth: Int = 2
    /// Latenza effettiva in millisecondi registrata tra il comando Play e l'emissione del primo audio
    public var lastFirstChunkLatencyMs: Double? = nil
    /// Ultimo Real-Time Factor misurato (durata_audio / tempo_sintesi; > 1.0 significa più veloce del tempo reale)
    public var lastRealTimeFactor: Double? = nil
    /// Ultimo tempo di sintesi per chunk in ms
    public var lastSynthesisLatencyMs: Double? = nil
    
    // MARK: - Finestre & Modalità
    public var presentationMode: WindowPresentationMode = .floatingPill
    public var accessibilityProfile: AccessibilityProfile = .standard
    public var isAlwaysOnTop: Bool = true
    public var isFloatingPillVisible: Bool = false
    public var isPillExpanded: Bool = false
    public var pillOrientation: PillOrientation = .horizontal
    public var pillDockSide: PillDockSide = .center
    public var isAccessibilityGranted: Bool = false
    
    // MARK: - Stato Motore Vocale & Fallback
    public var isUsingSpeechFallback: Bool = false
    public var speechFallbackNotice: String? = nil
    
    // MARK: - Spettro Audio Live (Metal & SwiftUI Waveform)
    /// 7 valori normalizzati (0.0 - 1.0) aggiornati a 60fps dal tap audio.
    public var liveWaveformLevels: [Float] = [0.15, 0.3, 0.6, 0.9, 0.7, 0.4, 0.2]
    
    // MARK: - Blocchi Universali Estratti (URLayer)
    public var detectedBlocks: [ReadingBlock] = []
    public var selectedBlockIndex: Int? = nil
    
    public init() {}
    
    // MARK: - Metodi di Mutazione Stato
    
    public func setQueue(_ chunks: [ReadingChunk]) {
        self.readingQueue = chunks
        self.currentChunk = chunks.first
        self.playbackProgress = 0.0
    }
    
    public func advanceChunk() -> ReadingChunk? {
        guard let current = currentChunk,
              let currentIndex = readingQueue.firstIndex(where: { $0.id == current.id }) else {
            return nil
        }
        
        let nextIndex = currentIndex + 1
        if nextIndex < readingQueue.count {
            let next = readingQueue[nextIndex]
            self.currentChunk = next
            self.playbackProgress = Double(nextIndex) / Double(readingQueue.count)
            return next
        } else {
            self.playbackState = .idle
            self.currentChunk = nil
            self.playbackProgress = 1.0
            return nil
        }
    }
    
    public func rewindChunk() -> ReadingChunk? {
        guard let current = currentChunk,
              let currentIndex = readingQueue.firstIndex(where: { $0.id == current.id }) else {
            return nil
        }
        
        let prevIndex = max(0, currentIndex - 1)
        let prev = readingQueue[prevIndex]
        self.currentChunk = prev
        self.playbackProgress = Double(prevIndex) / Double(readingQueue.count)
        return prev
    }
    
    public func setSpeed(_ newSpeed: Float) {
        self.playbackSpeed = max(0.5, min(3.0, newSpeed))
    }
}
