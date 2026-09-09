import Foundation
import AVFoundation
import LettoreCore

/// Protocollo per l'infrastruttura di sintesi vocale neurale.
public protocol TTSPipelineProtocol: Sendable {
    var isModelLoaded: Bool { get }
    func loadModel() async throws
    func synthesize(text: String, voice: VoiceProfile, speed: Float) async throws -> AVAudioPCMBuffer
}

/// Pipeline di test e mock per eseguire unit tests e sviluppo UI offline senza dipendere dai pesi ONNX.
public final class MockTTSPipeline: TTSPipelineProtocol, @unchecked Sendable {
    
    public private(set) var isModelLoaded: Bool = false
    private let sampleRate: Double = 24000.0
    
    public init() {}
    
    public func loadModel() async throws {
        // Simula tempo di caricamento istantaneo in-memory
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        self.isModelLoaded = true
    }
    
    public func synthesize(text: String, voice: VoiceProfile, speed: Float) async throws -> AVAudioPCMBuffer {
        if !isModelLoaded {
            try await loadModel()
        }
        
        // Calcola durata approssimata in base ai caratteri (~15 caratteri per secondo)
        let durationSeconds = max(0.4, Double(text.count) / 15.0 / Double(speed))
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "MockTTSPipeline", code: 1, userInfo: [NSLocalizedDescriptionKey: "Errore allocazione buffer"])
        }
        
        buffer.frameLength = frameCount
        
        // Genera un tono sinusoidale morbido con inviluppo per simulare una voce di test
        if let channelData = buffer.floatChannelData?[0] {
            let frequency: Float = 220.0 // La (A3)
            for i in 0..<Int(frameCount) {
                let time = Float(i) / Float(sampleRate)
                // Inviluppo morbido di attacco/rilascio
                let attack = min(1.0, Float(i) / 800.0)
                let release = min(1.0, Float(Int(frameCount) - i) / 800.0)
                let envelope = attack * release
                channelData[i] = sin(2.0 * .pi * frequency * time) * 0.15 * envelope
            }
        }
        
        return buffer
    }
}
