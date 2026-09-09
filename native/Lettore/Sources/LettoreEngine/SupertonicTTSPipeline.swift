import Foundation
import AVFoundation
import LettoreCore

/// Pipeline di sintesi vocale neurale Supertonic 3.
/// Si interfaccia con il motore locale Supertonic (ONNX Runtime / CoreML)
/// per ottenere l'esatta sintesi vocale di alta qualità presente nella versione originale (M1 Marco, F1 Giulia, ecc.),
/// convertendo il flusso WAV in buffer audio PCM pronti per AVAudioEngine.
public final class SupertonicTTSPipeline: TTSPipelineProtocol, @unchecked Sendable {
    
    private let baseURL: URL
    private let session: URLSession
    public private(set) var isModelLoaded: Bool = false
    
    public init(baseURL: URL = URL(string: "http://127.0.0.1:7788")!) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        self.session = URLSession(configuration: config)
    }
    
    public func loadModel() async throws {
        let statusURL = baseURL.appendingPathComponent("v1/status")
        var req = URLRequest(url: statusURL)
        req.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: req)
        guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
            throw NSError(domain: "SupertonicTTSPipeline", code: 1, userInfo: [NSLocalizedDescriptionKey: "Supertonic engine offline su 127.0.0.1:7788"])
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ready = json["ready"] as? Bool, ready {
            self.isModelLoaded = true
        } else {
            throw NSError(domain: "SupertonicTTSPipeline", code: 1, userInfo: [NSLocalizedDescriptionKey: "Supertonic engine non pronto (ready=false)"])
        }
    }
    
    public func synthesize(text: String, voice: VoiceProfile, speed: Float) async throws -> AVAudioPCMBuffer {
        let ttsURL = baseURL.appendingPathComponent("v1/tts")
        var req = URLRequest(url: ttsURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // L'id della VoiceProfile standard è già M1, F1, M2, F2
        let validVoices: Set<String> = ["M1", "F1", "M2", "F2"]
        let supertonicVoiceId = validVoices.contains(voice.id) ? voice.id : "M1"
        
        let body: [String: Any] = [
            "text": text,
            "voice": supertonicVoiceId,
            "lang": "it",
            "speed": Double(speed),
            "steps": 8
        ]
        
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: req)
        guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Errore sconosciuto"
            throw NSError(domain: "SupertonicTTSPipeline", code: 2, userInfo: [NSLocalizedDescriptionKey: "Errore sintesi Supertonic: \(errorText)"])
        }
        
        // Decodifica il file WAV ricevuto in un AVAudioPCMBuffer
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("supertonic_\(UUID().uuidString).wav")
        try data.write(to: tempURL)
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        let audioFile = try AVAudioFile(forReading: tempURL)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "SupertonicTTSPipeline", code: 3, userInfo: [NSLocalizedDescriptionKey: "Impossibile allocare AVAudioPCMBuffer per file WAV"])
        }
        
        try audioFile.read(into: buffer)
        self.isModelLoaded = true
        return buffer
    }
}
