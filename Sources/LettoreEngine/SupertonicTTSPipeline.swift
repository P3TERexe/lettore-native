import Foundation
import AVFoundation
import LettoreCore

/// Pipeline di sintesi vocale neurale Supertonic 3.
/// Si interfaccia con il backend locale FastAPI (ONNX Runtime / CoreML)
/// e restituisce i bytes WAV grezzi per la riproduzione con AVAudioPlayer.
public final class SupertonicTTSPipeline: TTSPipelineProtocol, @unchecked Sendable {
    
    private let baseURL: URL
    private let session: URLSession
    public private(set) var isModelLoaded: Bool = false
    
    public init(baseURL: URL = URL(string: "http://127.0.0.1:7788")!) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20.0
        config.timeoutIntervalForResource = 60.0
        config.connectionProxyDictionary = [:] // Assicura chiamata diretta a 127.0.0.1 bypassando eventuali proxy
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
    
    public func synthesize(text: String, voice: VoiceProfile, speed: Float) async throws -> Data {
        return try await synthesize(text: text, voice: voice, speed: speed, steps: 8)
    }
    
    public func synthesize(text: String, voice: VoiceProfile, speed: Float, steps: Int) async throws -> Data {
        let startTime = CFAbsoluteTimeGetCurrent()
        let ttsURL = baseURL.appendingPathComponent("v1/tts")
        var req = URLRequest(url: ttsURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // L'ID della voce nel frontend è "IT-M1", "EN-F2", ecc. 
        // Il backend Python supporta M1..M5 e F1..F5.
        let baseVoiceId = voice.id.split(separator: "-").last.map(String.init)?.uppercased() ?? "M1"
        let validVoices: Set<String> = ["M1", "M2", "M3", "M4", "M5", "F1", "F2", "F3", "F4", "F5"]
        let supertonicVoiceId = validVoices.contains(baseVoiceId) ? baseVoiceId : "M1"
        
        let safeSpeed = min(2.0, max(0.7, Double(speed)))
        let clampedSteps = max(5, min(12, steps))
        
        let body: [String: Any] = [
            "text": text,
            "voice": supertonicVoiceId,
            "lang": voice.language,
            "speed": safeSpeed,
            "steps": clampedSteps
        ]
        
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: req)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        
        guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Errore sconosciuto"
            throw NSError(domain: "SupertonicTTSPipeline", code: 2, userInfo: [NSLocalizedDescriptionKey: "Errore sintesi Supertonic: \(errorText)"])
        }
        
        let backendMs = httpRes.value(forHTTPHeaderField: "X-Duration-Ms") ?? "n/a"
        print("[SupertonicTTS] Sintetizzati \(data.count) bytes WAV in \(String(format: "%.1f", elapsedMs))ms (audio backend: \(backendMs)ms, steps: \(clampedSteps)) per: \"\(text.prefix(35))...\"")
        self.isModelLoaded = true
        return data
    }
}
