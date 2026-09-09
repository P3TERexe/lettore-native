import XCTest
import CoreGraphics
@testable import LettoreCore
@testable import LettoreEngine
@testable import LettoreSystem

final class LettoreCoreTests: XCTestCase {
    
    // MARK: - Test SentenceChunker
    
    func testChunkerDoesNotSplitOnItalianAbbreviations() {
        let chunker = SentenceChunker()
        let text = "Il Dott. Rossi ha visitato la Sig.ra Bianchi. L'esito della visita è eccellente."
        
        let chunks = chunker.chunk(text: text)
        XCTAssertEqual(chunks.count, 2, "Dovrebbe dividere in 2 frasi senza spezzare su Dott. o Sig.ra")
        XCTAssertTrue(chunks[0].text.contains("Dott. Rossi"))
        XCTAssertTrue(chunks[0].text.contains("Sig.ra Bianchi."))
        XCTAssertEqual(chunks[1].text, "L'esito della visita è eccellente.")
    }
    
    func testChunkerHandlesMultipleSentences() {
        let chunker = SentenceChunker()
        let text = "Prima frase di prova. Seconda frase con dettagli! Terza frase interrogativa?"
        
        let chunks = chunker.chunk(text: text)
        
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].index, 0)
        XCTAssertEqual(chunks[1].index, 1)
        XCTAssertEqual(chunks[2].index, 2)
    }
    
    func testChunkerEmptyString() {
        let chunker = SentenceChunker()
        let chunks = chunker.chunk(text: "   \n\t  ")
        XCTAssertTrue(chunks.isEmpty)
    }
    
    // MARK: - Test TextNormalizer
    
    func testNormalizerExpandsCurrencyAndPercentages() {
        let normalizer = TextNormalizer()
        let text = "Il prezzo è 12,50 € con lo sconto del 20%."
        
        let normalized = normalizer.normalize(text: text)
        
        XCTAssertTrue(normalized.contains("12 euro e 50 centesimi"), "Dovrebbe espandere 12,50 €")
        XCTAssertTrue(normalized.contains("20 per cento"), "Dovrebbe espandere 20%")
    }
    
    func testNormalizerExpandsWebAndEmails() {
        let normalizer = TextNormalizer()
        let text = "Visita https://lettore.app o scrivi a info@lettore.it per info."
        
        let normalized = normalizer.normalize(text: text)
        
        XCTAssertTrue(normalized.contains("link web"))
        XCTAssertTrue(normalized.contains("indirizzo email"))
        XCTAssertFalse(normalized.contains("https://"))
    }
    
    func testNormalizerFiltersExclusions() {
        let normalizer = TextNormalizer()
        let text = "Questo è il testo principale. Inviato da iPhone"
        
        let normalized = normalizer.normalize(text: text, exclusions: ["Inviato da iPhone"])
        
        XCTAssertEqual(normalized, "Questo è il testo principale.")
    }
    
    // MARK: - Test AppState
    
    func testAppStateQueueAdvancement() {
        let state = AppState()
        let chunk1 = ReadingChunk(index: 0, text: "Frase 1")
        let chunk2 = ReadingChunk(index: 1, text: "Frase 2")
        
        state.setQueue([chunk1, chunk2])
        XCTAssertEqual(state.currentChunk?.id, chunk1.id)
        XCTAssertEqual(state.playbackProgress, 0.0)
        
        let advanced = state.advanceChunk()
        XCTAssertEqual(advanced?.id, chunk2.id)
        XCTAssertEqual(state.currentChunk?.id, chunk2.id)
        XCTAssertEqual(state.playbackProgress, 0.5)
        
        let finished = state.advanceChunk()
        XCTAssertNil(finished)
        XCTAssertEqual(state.playbackState, .idle)
        XCTAssertEqual(state.playbackProgress, 1.0)
    }
    
    // MARK: - Test LettoreEngine (MockTTSPipeline)
    
    func testMockTTSPipelineBufferGeneration() async throws {
        let pipeline = MockTTSPipeline()
        let voice = VoiceProfile(id: "it_f1", name: "Chiara", language: "it", gender: "female")
        
        let wavData = try await pipeline.synthesize(text: "Frase di prova per il buffer audio.", voice: voice, speed: 1.0)
        
        XCTAssertTrue(pipeline.isModelLoaded)
        XCTAssertGreaterThan(wavData.count, 44, "WAV deve avere almeno l'header di 44 bytes")
        // Verifica magic bytes RIFF/WAVE
        let header = String(data: wavData.prefix(4), encoding: .ascii)
        XCTAssertEqual(header, "RIFF")
    }
    
    // MARK: - Test LettoreSystem (VisionOCRService)
    
    func testVisionOCRErrorHandling() async {
        let service = VisionOCRService()
        // Creazione di un'immagine bitmap vuota 1x1
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel: UInt32 = 0
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = context.makeImage() else {
            XCTFail("Impossibile creare CGImage di test")
            return
        }
        
        do {
            _ = try await service.recognizeText(from: cgImage)
            XCTFail("Dovrebbe lanciare OCRError.emptyResult su un'immagine 1x1 vuota")
        } catch let error as VisionOCRService.OCRError {
            switch error {
            case .emptyResult:
                XCTAssertTrue(true, "Ricevuto emptyResult atteso")
            default:
                XCTAssertNotNil(error.errorDescription)
            }
        } catch {
            XCTFail("Errore inatteso: \(error)")
        }
    }
}

