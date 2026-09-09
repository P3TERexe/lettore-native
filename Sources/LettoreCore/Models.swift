import Foundation
import CoreGraphics

/// Stato operativo del motore e della riproduzione vocale.
public enum PlaybackState: String, Codable, Sendable {
    case idle = "idle"
    case synthesizing = "synthesizing"
    case playing = "playing"
    case paused = "paused"
    case error = "error"
}

/// Modalità di visualizzazione dell'interfaccia utente.
public enum WindowPresentationMode: String, Codable, Sendable {
    case studio = "studio"
    case floatingPill = "floatingPill"
    case dynamicNotch = "dynamicNotch"
    case superAccessible = "superAccessible"
}

/// Orientamento responsive della pillola fluttuante (orizzontale se al centro dello schermo, verticale se ai lati).
public enum PillOrientation: String, Codable, Sendable {
    case horizontal = "horizontal"
    case vertical = "vertical"
}

/// Lato di ancoraggio della pillola sullo schermo.
public enum PillDockSide: String, Codable, Sendable {
    case left = "left"
    case center = "center"
    case right = "right"
}

/// Profilo di accessibilità visiva e cognitiva.
public enum AccessibilityProfile: String, Codable, CaseIterable, Sendable {
    case standard = "standard"
    case lowVision = "lowVision"
    case dyslexia = "dyslexia"
    
    public var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .lowVision: return "Bassa Visione (WCAG AAA)"
        case .dyslexia: return "Dislessia (Font Leggibile)"
        }
    }
}

/// Singolo frammento di testo (frase) segmentato per la sintesi vocale.
public struct ReadingChunk: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let index: Int
    public let text: String
    public let rawText: String
    public var isSpoken: Bool
    public var durationSeconds: Double?
    
    public init(
        id: UUID = UUID(),
        index: Int,
        text: String,
        rawText: String? = nil,
        isSpoken: Bool = false,
        durationSeconds: Double? = nil
    ) {
        self.id = id
        self.index = index
        self.text = text
        self.rawText = rawText ?? text
        self.isSpoken = isSpoken
        self.durationSeconds = durationSeconds
    }
}

/// Ruolo semantico di un blocco di testo identificato a schermo.
public enum SemanticBlockRole: String, Codable, Sendable {
    case heading = "heading"
    case paragraph = "paragraph"
    case listItem = "list_item"
    case quote = "quote"
    case code = "code"
    case unknown = "unknown"
}

/// Blocco testuale estratto da un'applicazione esterna tramite Accessibility (AX) o Apple Vision.
public struct ReadingBlock: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let role: SemanticBlockRole
    public let text: String
    public let bounds: CGRect
    public let confidence: Float
    
    public init(
        id: UUID = UUID(),
        role: SemanticBlockRole,
        text: String,
        bounds: CGRect = .zero,
        confidence: Float = 1.0
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.bounds = bounds
        self.confidence = confidence
    }
}

/// Profilo vocale disponibile nel motore di sintesi Supertonic 3.
public struct VoiceProfile: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let language: String
    public let gender: String
    public let isCustom: Bool
    public let sampleRate: Int
    
    public init(
        id: String,
        name: String,
        language: String = "it",
        gender: String = "neutral",
        isCustom: Bool = false,
        sampleRate: Int = 24000
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.gender = gender
        self.isCustom = isCustom
        self.sampleRate = sampleRate
    }
    
    public static let supportedLanguages: [(code: String, name: String)] = [
        ("it", "Italiano"),
        ("en", "English"),
        ("es", "Español"),
        ("fr", "Français"),
        ("de", "Deutsch")
    ]
    
    public static let standardVoices: [VoiceProfile] = [
        // Italiano
        VoiceProfile(id: "IT-M1", name: "Marco", language: "it", gender: "male"),
        VoiceProfile(id: "IT-F1", name: "Giulia", language: "it", gender: "female"),
        VoiceProfile(id: "IT-M2", name: "Luca", language: "it", gender: "male"),
        VoiceProfile(id: "IT-F2", name: "Sofia", language: "it", gender: "female"),
        // Inglese
        VoiceProfile(id: "EN-M1", name: "John", language: "en", gender: "male"),
        VoiceProfile(id: "EN-F1", name: "Emma", language: "en", gender: "female"),
        VoiceProfile(id: "EN-M2", name: "Michael", language: "en", gender: "male"),
        VoiceProfile(id: "EN-F2", name: "Sarah", language: "en", gender: "female"),
        // Spagnolo
        VoiceProfile(id: "ES-M1", name: "Carlos", language: "es", gender: "male"),
        VoiceProfile(id: "ES-F1", name: "Lucia", language: "es", gender: "female"),
        VoiceProfile(id: "ES-M2", name: "Miguel", language: "es", gender: "male"),
        VoiceProfile(id: "ES-F2", name: "Maria", language: "es", gender: "female"),
        // Francese
        VoiceProfile(id: "FR-M1", name: "Pierre", language: "fr", gender: "male"),
        VoiceProfile(id: "FR-F1", name: "Camille", language: "fr", gender: "female"),
        VoiceProfile(id: "FR-M2", name: "Lucas", language: "fr", gender: "male"),
        VoiceProfile(id: "FR-F2", name: "Chloe", language: "fr", gender: "female"),
        // Tedesco
        VoiceProfile(id: "DE-M1", name: "Klaus", language: "de", gender: "male"),
        VoiceProfile(id: "DE-F1", name: "Anna", language: "de", gender: "female"),
        VoiceProfile(id: "DE-M2", name: "Hans", language: "de", gender: "male"),
        VoiceProfile(id: "DE-F2", name: "Julia", language: "de", gender: "female")
    ]
}
