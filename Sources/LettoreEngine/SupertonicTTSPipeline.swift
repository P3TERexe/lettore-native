import Foundation
import AVFoundation
import LettoreCore

/// Corpo JSON di `POST /v1/tts`.
///
/// È una struttura pura e `Codable` così il contratto della richiesta è
/// verificabile nei test senza rete. Il client nativo normalizza il testo una
/// sola volta in `LettoreCore`: per questo `normalizeText` vale sempre `false`.
struct TTSRequestPayload: Codable, Equatable, Sendable {
    let text: String
    let voice: String
    let lang: String
    let speed: Double
    let steps: Int
    let normalizeText: Bool

    enum CodingKeys: String, CodingKey {
        case text
        case voice
        case lang
        case speed
        case steps
        case normalizeText = "normalize_text"
    }

    init(text: String, voice: VoiceProfile, speed: Float, steps: Int) {
        // L'ID della voce nel frontend è "IT-M1", "EN-F2", ecc.
        // Il backend Python supporta M1..M5 e F1..F5.
        let baseVoiceId = voice.id.split(separator: "-").last.map(String.init)?.uppercased() ?? "M1"
        let validVoices: Set<String> = ["M1", "M2", "M3", "M4", "M5", "F1", "F2", "F3", "F4", "F5"]

        self.text = text
        self.voice = validVoices.contains(baseVoiceId) ? baseVoiceId : "M1"
        self.lang = voice.language
        self.speed = min(2.0, max(0.7, Double(speed)))
        self.steps = max(5, min(12, steps))
        self.normalizeText = false
    }
}

/// Pipeline di sintesi vocale neurale Supertonic 3.
/// Si interfaccia con il backend locale FastAPI (ONNX Runtime / CoreML)
/// e restituisce i bytes WAV grezzi per la riproduzione con AVAudioPlayer.
/// La velocità di ascolto è applicata dal player, non dalla sintesi: il client
/// chiama questo metodo con speed 1.0 per massimizzare i cache hit.
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

        let payload = TTSRequestPayload(text: text, voice: voice, speed: speed, steps: steps)
        req.httpBody = try JSONEncoder().encode(payload)
        
        let (data, response) = try await session.data(for: req)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        
        guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Errore sconosciuto"
            throw NSError(domain: "SupertonicTTSPipeline", code: 2, userInfo: [NSLocalizedDescriptionKey: "Errore sintesi Supertonic: \(errorText)"])
        }
        
        let backendMs = httpRes.value(forHTTPHeaderField: "X-Duration-Ms") ?? "n/a"
        print("[SupertonicTTS] Sintetizzati \(data.count) bytes WAV in \(String(format: "%.1f", elapsedMs))ms (audio backend: \(backendMs)ms, steps: \(payload.steps)) per: \"\(text.prefix(35))...\"")
        self.isModelLoaded = true
        return data
    }
}
