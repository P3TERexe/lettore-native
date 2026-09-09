import Foundation
import AVFoundation
import LettoreCore

/// Servizio audio nativo a bassissima latenza basato su AVAudioEngine.
/// Gestisce la riproduzione continua a chunk, la modulazione della velocità
/// senza alterazione del pitch e l'estrazione a 60fps dei livelli per il visualizzatore.
public final class AudioEngineService: @unchecked Sendable {
    
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    
    /// Formato standard audio TTS Supertonic: 24.000 Hz, Float32, Mono
    public let standardFormat: AVAudioFormat
    
    private var isConfigured = false
    private let lock = NSLock()
    
    /// Callback per aggiornare i livelli audio dell'onda visiva (7 barre normalizzate 0.0 - 1.0)
    public var onAudioLevelsUpdate: (([Float]) -> Void)?
    
    public init(sampleRate: Double = 44100.0) {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            fatalError("Impossibile creare AVAudioFormat per 44.1kHz Float32 Mono")
        }
        self.standardFormat = format
        setupEngine(withFormat: format)
    }
    
    deinit {
        stop()
    }
    
    private func setupEngine(withFormat format: AVAudioFormat) {
        engine.attach(playerNode)
        engine.attach(timePitch)
        
        engine.connect(playerNode, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: nil)
        
        installWaveformTap(withFormat: format)
        
        do {
            try engine.start()
            isConfigured = true
        } catch {
            print("[AudioEngineService] Errore avvio AVAudioEngine: \(error)")
        }
    }
    
    private func installWaveformTap(withFormat format: AVAudioFormat) {
        timePitch.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self, let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }
            
            var sum: Float = 0
            for i in 0..<frameCount {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frameCount))
            let normalized = min(1.0, rms * 4.5)
            
            let levels: [Float] = [
                normalized * 0.45,
                normalized * 0.75,
                normalized * 0.95,
                normalized * 1.0,
                normalized * 0.85,
                normalized * 0.60,
                normalized * 0.35
            ]
            
            DispatchQueue.main.async {
                self.onAudioLevelsUpdate?(levels)
            }
        }
    }
    
    // MARK: - Controlli Riproduzione
    
    /// Imposta la velocità di riproduzione preservando le formanti vocali (senza effetto chipmunk).
    public func setSpeed(_ speed: Float) {
        lock.lock()
        defer { lock.unlock() }
        let clamped = max(0.5, min(3.0, speed))
        timePitch.rate = clamped
    }
    
    /// Avvia o riprende la riproduzione audio.
    public func play() {
        lock.lock()
        defer { lock.unlock() }
        if !engine.isRunning {
            try? engine.start()
        }
        playerNode.play()
    }
    
    /// Mette in pausa la riproduzione corrente.
    public func pause() {
        lock.lock()
        defer { lock.unlock() }
        playerNode.pause()
    }
    
    /// Ferma completamente la riproduzione e svuota la coda interna di nodi.
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        playerNode.stop()
    }
    
    /// Accoda un buffer PCM float32 alla riproduzione gapless.
    public func scheduleBuffer(_ buffer: AVAudioPCMBuffer, onComplete: (@Sendable () -> Void)? = nil) {
        lock.lock()
        defer { lock.unlock() }
        
        let currentFormat = playerNode.outputFormat(forBus: 0)
        if currentFormat.sampleRate != buffer.format.sampleRate ||
           currentFormat.channelCount != buffer.format.channelCount {
            timePitch.removeTap(onBus: 0)
            engine.disconnectNodeOutput(playerNode)
            engine.disconnectNodeOutput(timePitch)
            
            engine.connect(playerNode, to: timePitch, format: buffer.format)
            engine.connect(timePitch, to: engine.mainMixerNode, format: nil)
            installWaveformTap(withFormat: buffer.format)
        }
        
        if !engine.isRunning {
            try? engine.start()
        }
        
        playerNode.scheduleBuffer(buffer, completionHandler: onComplete)
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }
}
