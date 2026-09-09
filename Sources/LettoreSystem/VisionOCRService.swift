import Foundation
import Vision
import AppKit
import LettoreCore

/// Servizio nativo di riconoscimento ottico dei caratteri (OCR) basato su Apple Vision.framework.
/// Permette l'estrazione ultra-rapida e completamente offline di testo da immagini, screenshot
/// e porzioni di schermo, supportando modelli multilingua e riconoscimento automatico del layout.
public actor VisionOCRService {
    
    public enum OCRError: LocalizedError {
        case invalidImageData
        case recognitionFailed(String)
        case emptyResult
        
        public var errorDescription: String? {
            switch self {
            case .invalidImageData:
                return "Immagine non valida o impossibile estrarre CGImage."
            case .recognitionFailed(let detail):
                return "Errore durante il riconoscimento Vision: \(detail)"
            case .emptyResult:
                return "Nessun testo rilevato nell'immagine selezionata."
            }
        }
    }
    
    public init() {}
    
    /// Riconosce il testo da un'istanza `CGImage`.
    ///
    /// - Parameters:
    ///   - cgImage: L'immagine sorgente da analizzare.
    ///   - languages: Lingue preferite per il riconoscimento (default: ["it-IT", "en-US"]).
    ///   - level: Accuratezza del riconoscimento (.accurate o .fast).
    /// - Returns: Testo riconosciuto aggregato con paragrafi ordinati dall'alto verso il basso.
    public func recognizeText(
        from cgImage: CGImage,
        languages: [String] = ["it-IT", "en-US"],
        level: VNRequestTextRecognitionLevel = .accurate
    ) throws -> String {
        var recognizedLines: [(text: String, yPos: CGFloat)] = []
        
        let request = VNRecognizeTextRequest { request, error in
            if error != nil {
                return
            }
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            
            for observation in observations {
                guard let topCandidate = observation.topCandidates(1).first else { continue }
                // Coordinate normalizzate Vision (0,0 in basso a sinistra)
                let yPosition = observation.boundingBox.origin.y
                recognizedLines.append((text: topCandidate.string, yPos: yPosition))
            }
        }
        
        request.recognitionLanguages = languages
        request.recognitionLevel = level
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OCRError.recognitionFailed(error.localizedDescription)
        }
        
        guard !recognizedLines.isEmpty else {
            throw OCRError.emptyResult
        }
        
        // Ordina dall'alto verso il basso (Vision ha y=0 in basso, quindi y decrescente corrisponde a lettura naturale)
        recognizedLines.sort { $0.yPos > $1.yPos }
        
        let fullText = recognizedLines.map { $0.text }.joined(separator: "\n")
        return fullText
    }
    
    /// Riconosce il testo da un `NSImage`.
    public func recognizeText(
        from nsImage: NSImage,
        languages: [String] = ["it-IT", "en-US"]
    ) throws -> String {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.invalidImageData
        }
        return try recognizeText(from: cgImage, languages: languages)
    }
    
    /// Esegue una cattura OCR interattiva da una porzione dello schermo (rettangolo in coordinate display).
    @MainActor
    public static func captureScreenRect(_ rect: CGRect) -> CGImage? {
        guard let displayID = CGMainDisplayID() as CGDirectDisplayID? else { return nil }
        return CGDisplayCreateImage(displayID, rect: rect)
    }
}
