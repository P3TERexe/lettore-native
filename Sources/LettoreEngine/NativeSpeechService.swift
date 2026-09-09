import Foundation
import AVFoundation
import LettoreCore

/// Servizio di sintesi vocale nativo basato su AVSpeechSynthesizer di Apple.
/// Esegue la lettura vocale fluida e cristallina del testo in lingua italiana senza alcuna dipendenza esterna,
/// con supporto per pause, riprese, modulazione di velocità e sincronizzazione dell'onda visiva a 60fps.
@MainActor
public final class NativeSpeechService: NSObject, AVSpeechSynthesizerDelegate {
    
    private let synthesizer = AVSpeechSynthesizer()
    private var waveformTimer: Timer?
    private var speechPhase: Float = 0.0
    
    public var onFinish: (() -> Void)?
    public var onWordHighlight: ((NSRange) -> Void)?
    public var onLevelsUpdate: (([Float]) -> Void)?
    public var onProgressUpdate: ((Double) -> Void)?
    
    public private(set) var isSpeaking: Bool = false
    public private(set) var isPaused: Bool = false
    
    public override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    // MARK: - Controlli di Riproduzione
    
    /// Legge ad alta voce il testo specificato con voce e velocità configurate.
    public func speak(text: String, voice: VoiceProfile? = nil, speed: Float = 1.05) {
        stop()
        
        let utterance = AVSpeechUtterance(string: text)
        
        // Seleziona la voce italiana migliore disponibile nel sistema
        if let voiceID = voice?.id, let specificVoice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = specificVoice
        } else {
            // Cerca prima le voci italiane di qualità premium o enhanced (es. Alice, Federica, Luca)
            let italianVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("it") }
            if let preferred = italianVoices.first(where: { $0.quality == .premium }) ??
                               italianVoices.first(where: { $0.quality == .enhanced }) ??
                               italianVoices.first {
                utterance.voice = preferred
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: "it-IT")
            }
        }
        
        // Calibra la velocità di Apple (0.0 - 1.0) centrata sul default (~0.5)
        let normalizedRate = min(1.0, max(0.1, AVSpeechUtteranceDefaultSpeechRate * (speed / 1.0)))
        utterance.rate = normalizedRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        isSpeaking = true
        isPaused = false
        startWaveformAnimation()
        synthesizer.speak(utterance)
    }
    
    /// Mette in pausa la lettura vocale.
    public func pause() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .immediate)
            isPaused = true
            isSpeaking = false
            stopWaveformAnimation()
        }
    }
    
    /// Riprende la lettura dalla pausa.
    public func resume() {
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            isPaused = false
            isSpeaking = true
            startWaveformAnimation()
        }
    }
    
    /// Ferma completamente la sintesi vocale corrente.
    public func stop() {
        stopWaveformAnimation()
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        isPaused = false
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.isPaused = false
            self.stopWaveformAnimation()
            self.onProgressUpdate?(1.0)
            self.onFinish?()
        }
    }
    
    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.isPaused = false
            self.stopWaveformAnimation()
        }
    }
    
    public nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let totalChars = utterance.speechString.count
        Task { @MainActor in
            self.onWordHighlight?(characterRange)
            if totalChars > 0 {
                let progress = min(1.0, max(0.0, Double(characterRange.location + characterRange.length) / Double(totalChars)))
                self.onProgressUpdate?(progress)
            }
        }
    }
    
    // MARK: - Simulatore Onde Vocali a 60fps
    
    private func startWaveformAnimation() {
        waveformTimer?.invalidate()
        waveformTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isSpeaking else { return }
                self.speechPhase += 0.25
                
                let p = self.speechPhase
                let baseAmp = 0.5 + 0.35 * sin(p * 1.4)
                
                let levels: [Float] = [
                    Float(max(0.15, min(1.0, baseAmp * (0.6 + 0.3 * sin(p * 2.1))))),
                    Float(max(0.20, min(1.0, baseAmp * (0.8 + 0.2 * cos(p * 1.8))))),
                    Float(max(0.25, min(1.0, baseAmp * (1.0 + 0.25 * sin(p * 2.7))))),
                    Float(max(0.30, min(1.0, baseAmp * (0.95 + 0.3 * cos(p * 3.1))))),
                    Float(max(0.20, min(1.0, baseAmp * (0.75 + 0.25 * sin(p * 1.9))))),
                    Float(max(0.15, min(1.0, baseAmp * (0.60 + 0.2 * cos(p * 2.4))))),
                    Float(max(0.10, min(1.0, baseAmp * (0.45 + 0.2 * sin(p * 3.5)))))
                ]
                
                self.onLevelsUpdate?(levels)
            }
        }
    }
    
    private func stopWaveformAnimation() {
        waveformTimer?.invalidate()
        waveformTimer = nil
        onLevelsUpdate?([0.15, 0.25, 0.4, 0.5, 0.4, 0.25, 0.15])
    }
}
