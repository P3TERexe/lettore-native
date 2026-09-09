import Foundation
import AVFoundation
import LettoreCore

/// Protocollo per l'infrastruttura di sintesi vocale neurale.
/// Restituisce i bytes WAV grezzi per la massima compatibilità di riproduzione.
public protocol TTSPipelineProtocol: Sendable {
    var isModelLoaded: Bool { get }
    func loadModel() async throws
    func synthesize(text: String, voice: VoiceProfile, speed: Float) async throws -> Data
}

/// Pipeline di test e mock per eseguire unit tests e sviluppo UI offline senza dipendere dai pesi ONNX.
public final class MockTTSPipeline: TTSPipelineProtocol, @unchecked Sendable {
    
    public private(set) var isModelLoaded: Bool = false
    private let sampleRate: Double = 24000.0
    
    public init() {}
    
    public func loadModel() async throws {
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        self.isModelLoaded = true
    }
    
    public func synthesize(text: String, voice: VoiceProfile, speed: Float) async throws -> Data {
        if !isModelLoaded {
            try await loadModel()
        }
        
        let durationSeconds = max(0.4, Double(text.count) / 15.0 / Double(speed))
        let frameCount = Int(sampleRate * durationSeconds)
        
        // Genera WAV PCM int16 mono
        var samples = [Int16](repeating: 0, count: frameCount)
        let frequency: Float = 220.0
        for i in 0..<frameCount {
            let time = Float(i) / Float(sampleRate)
            let attack = min(1.0, Float(i) / 800.0)
            let release = min(1.0, Float(frameCount - i) / 800.0)
            let envelope = attack * release
            let value = sin(2.0 * .pi * frequency * time) * 0.15 * envelope
            samples[i] = Int16(clamping: Int(value * 32767))
        }
        
        return buildWAV(samples: samples, sampleRate: Int(sampleRate), channels: 1)
    }
    
    private func buildWAV(samples: [Int16], sampleRate: Int, channels: Int) -> Data {
        let dataSize = samples.count * 2
        let fileSize = 36 + dataSize
        
        var wav = Data()
        wav.append(contentsOf: "RIFF".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Array($0) })
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })      // PCM
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) }) // channels
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * channels * 2).littleEndian) { Array($0) }) // byte rate
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(channels * 2).littleEndian) { Array($0) }) // block align
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })      // bits per sample
        wav.append(contentsOf: "data".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })
        samples.withUnsafeBufferPointer { ptr in
            wav.append(UnsafeBufferPointer(start: UnsafeRawPointer(ptr.baseAddress!).assumingMemoryBound(to: UInt8.self), count: dataSize))
        }
        return wav
    }
}
