import Foundation
import AVFoundation
import LettoreCore

/// Servizio audio basato su AVAudioPlayer.
/// Riproduce WAV data direttamente, senza bisogno di AVAudioEngine
/// (che non funziona da processi swift run / CLI su macOS).
public final class AudioEngineService: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    
    private var player: AVAudioPlayer?
    private var onPlaybackComplete: (() -> Void)?
    private var meteringTimer: Timer?
    private var lastLevelsUpdate: CFAbsoluteTime = 0
    
    /// Callback per aggiornare i livelli audio dell'onda visiva (7 barre normalizzate 0.0 - 1.0)
    public var onAudioLevelsUpdate: (([Float]) -> Void)?
    
    /// Callback per aggiornare il progresso di riproduzione della frase corrente (0.0 - 1.0)
    public var onProgressUpdate: ((Double) -> Void)?
    
    /// Formato nominale (per compatibilità API)
    public let standardFormat: AVAudioFormat
    
    public init(sampleRate: Double = 44100.0) {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            fatalError("Impossibile creare AVAudioFormat")
        }
        self.standardFormat = format
        super.init()
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Controlli Riproduzione
    
    public func setSpeed(_ speed: Float) {
        guard let player = player else { return }
        player.enableRate = true
        player.rate = max(0.5, min(2.0, speed))
    }
    
    public func play() {
        player?.play()
        startMetering()
    }
    
    public func pause() {
        player?.pause()
        stopMetering()
    }
    
    public func stop() {
        player?.stop()
        player = nil
        onPlaybackComplete = nil
        stopMetering()
    }
    
    /// Riproduce dati WAV grezzi. Il callback onComplete scatta al termine della riproduzione.
    public func playWAVData(_ data: Data, speed: Float = 1.0, onComplete: (() -> Void)? = nil) {
        // Ferma la riproduzione corrente
        player?.stop()
        stopMetering()
        
        do {
            let newPlayer = try AVAudioPlayer(data: data)
            newPlayer.delegate = self
            newPlayer.enableRate = true
            newPlayer.rate = max(0.5, min(2.0, speed))
            newPlayer.isMeteringEnabled = true
            newPlayer.prepareToPlay()
            
            self.player = newPlayer
            self.onPlaybackComplete = onComplete
            
            if newPlayer.play() {
                print("[AudioPlayer] In riproduzione — durata: \(String(format: "%.2f", newPlayer.duration))s, rate: \(newPlayer.rate)")
                startMetering()
            } else {
                print("[AudioPlayer] ERRORE: play() ha restituito false")
                onComplete?()
            }
        } catch {
            print("[AudioPlayer] ERRORE inizializzazione: \(error)")
            onComplete?()
        }
    }
    
    // MARK: - AVAudioPlayerDelegate
    
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("[AudioPlayer] Riproduzione terminata (successo: \(flag))")
        stopMetering()
        let completion = onPlaybackComplete
        onPlaybackComplete = nil
        self.player = nil
        DispatchQueue.main.async {
            self.onProgressUpdate?(1.0)
            completion?()
        }
    }
    
    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("[AudioPlayer] ERRORE decodifica: \(error?.localizedDescription ?? "sconosciuto")")
        stopMetering()
        let completion = onPlaybackComplete
        onPlaybackComplete = nil
        self.player = nil
        DispatchQueue.main.async {
            completion?()
        }
    }
    
    // MARK: - Metering per Waveform
    
    private func startMetering() {
        meteringTimer?.invalidate()
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.player, player.isPlaying else { return }
            player.updateMeters()
            let power = player.averagePower(forChannel: 0)
            // power è in dB (-160 ... 0). Normalizziamo a 0.0 - 1.0
            let normalized = max(0.0, min(1.0, (power + 50.0) / 50.0))
            
            // Aggiungi variazione organica per le 7 barre
            let t = CFAbsoluteTimeGetCurrent()
            let levels: [Float] = [
                normalized * Float(0.45 + 0.15 * sin(t * 3.1)),
                normalized * Float(0.70 + 0.10 * cos(t * 2.7)),
                normalized * Float(0.90 + 0.10 * sin(t * 4.3)),
                normalized * 1.0,
                normalized * Float(0.85 + 0.10 * cos(t * 3.8)),
                normalized * Float(0.60 + 0.15 * sin(t * 2.2)),
                normalized * Float(0.35 + 0.10 * cos(t * 5.1))
            ]
            
            let chunkProgress = player.duration > 0 ? max(0.0, min(1.0, player.currentTime / player.duration)) : 0.0
            
            DispatchQueue.main.async {
                self.onAudioLevelsUpdate?(levels)
                self.onProgressUpdate?(chunkProgress)
            }
        }
    }
    
    private func stopMetering() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevelsUpdate?([0.15, 0.25, 0.4, 0.5, 0.4, 0.25, 0.15])
        }
    }
}
