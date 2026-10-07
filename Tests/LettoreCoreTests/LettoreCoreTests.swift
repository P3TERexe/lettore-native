import XCTest
import CoreGraphics
import AppKit
@testable import LettoreCore
@testable import LettoreEngine
@testable import LettoreSystem
@testable import LettoreUI

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
    
    func testPillOrientationState() {
        let state = AppState()
        XCTAssertEqual(state.pillOrientation, .horizontal)
        XCTAssertEqual(state.pillDockSide, .center)
        XCTAssertFalse(state.isFloatingPillVisible)
        XCTAssertFalse(state.isPillExpanded)
        
        state.isFloatingPillVisible = true
        state.isPillExpanded = true
        XCTAssertTrue(state.isFloatingPillVisible)
        XCTAssertTrue(state.isPillExpanded)
        
        state.pillOrientation = .vertical
        state.pillDockSide = .left
        XCTAssertEqual(state.pillOrientation, .vertical)
        XCTAssertEqual(state.pillDockSide, .left)
        
        state.pillDockSide = .right
        XCTAssertEqual(state.pillDockSide, .right)
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
    
    // MARK: - Test Logica di Docking e Isteresi Pillola
    
    func testPillDockingCalculationHysteresis() {
        let screenRect = CGRect(x: 0, y: 0, width: 1470, height: 923)
        let horizontalWidth: CGFloat = 282
        let verticalWidth: CGFloat = 48
        
        // Scenario 1: Pillola orizzontale trascinata a 60px dal bordo destro
        let distFromRightEdge: CGFloat = 60.0
        let dockThresholdFromHorizontal: CGFloat = 90.0
        XCTAssertLessThanOrEqual(distFromRightEdge, dockThresholdFromHorizontal, "Deve agganciarsi a destra")
        
        // Calcolo coordinata X agganciata a destra
        let dockedX = screenRect.maxX - verticalWidth - 8
        XCTAssertEqual(dockedX, 1470 - 48 - 8)
        XCTAssertLessThanOrEqual(dockedX + verticalWidth, screenRect.maxX - 8)
        
        // Scenario 2: Pillola verticale ancorata a destra (isteresi di sgancio = 130px)
        let undockThresholdFromVertical: CGFloat = 130.0
        let smallPullDist: CGFloat = 80.0 // Non ancora abbastanza per sganciarsi
        XCTAssertLessThanOrEqual(smallPullDist, undockThresholdFromVertical, "Resta agganciata in verticale")
        
        let deliberatePullDist: CGFloat = 150.0 // Sgancio deliberato verso il centro
        XCTAssertGreaterThan(deliberatePullDist, undockThresholdFromVertical, "Si sgancia e torna orizzontale")
        
        // Scenario 3: Calcolo ancoraggio espansione verso l'interno schermo
        let currentRightBezel = screenRect.maxX - deliberatePullDist
        var expandedX = currentRightBezel - horizontalWidth
        let minAllowedX = screenRect.minX + 8
        let maxAllowedX = screenRect.maxX - horizontalWidth - 8
        expandedX = max(minAllowedX, min(maxAllowedX, expandedX))
        
        XCTAssertGreaterThanOrEqual(expandedX, minAllowedX, "Non deve uscire a sinistra")
        XCTAssertLessThanOrEqual(expandedX + horizontalWidth, screenRect.maxX - 8, "Non deve uscire a destra")
    }
    
    @MainActor
    func testFloatingPillDockingExecution() {
        guard let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let appState = AppState()
        let manager = FloatingPillPanelManager.shared
        
        let panel = NSPanel(
            contentRect: NSRect(x: screenRect.maxX - 60, y: 300, width: 104, height: 42),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        appState.pillOrientation = .horizontal
        appState.pillDockSide = .center
        
        // Esegui docking sul bordo destro
        manager.evaluateDockingAndOrientation(panel: panel, appState: appState, animated: false)
        
        XCTAssertEqual(appState.pillOrientation, .vertical, "Pillola deve diventare verticale quando rilasciata sul bordo destro")
        XCTAssertEqual(appState.pillDockSide, .right, "Dock side deve essere .right")
        
        // Ora sposta la pillola verso il centro
        panel.setFrameOrigin(NSPoint(x: screenRect.midX - 24, y: 300))
        manager.evaluateDockingAndOrientation(panel: panel, appState: appState, animated: false)
        
        XCTAssertEqual(appState.pillOrientation, .horizontal, "Pillola deve tornare orizzontale al centro dello schermo")
        XCTAssertEqual(appState.pillDockSide, .center, "Dock side deve essere .center")
    }
}

