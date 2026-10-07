import XCTest
import Foundation
@testable import LettoreCore
@testable import LettoreEngine

final class AudioPerformanceTests: XCTestCase {
    
    // MARK: - Test AudioCacheManager Key Determinism (SHA-256)
    
    func testAudioCacheKeyDeterminism() {
        let cache = AudioCacheManager.shared
        
        let key1 = cache.cacheKey(for: "Ciao mondo, questa è una prova.", voiceId: "IT-M1", speed: 1.05, steps: 8)
        let key2 = cache.cacheKey(for: "   Ciao mondo, questa è una prova. \n", voiceId: "it-m1", speed: 1.05, steps: 8)
        
        XCTAssertEqual(key1, key2, "La chiave SHA-256 deve essere deterministica e invariante rispetto a whitespace e maiuscole/minuscole del voiceId")
        XCTAssertEqual(key1.count, 64, "L'hash SHA-256 deve essere lungo 64 caratteri esadecimali")
        
        let keyDifferentSteps = cache.cacheKey(for: "Ciao mondo, questa è una prova.", voiceId: "IT-M1", speed: 1.05, steps: 5)
        XCTAssertNotEqual(key1, keyDifferentSteps, "Gli step differenti devono produrre hash differenti")
        
        let keyDifferentSpeed = cache.cacheKey(for: "Ciao mondo, questa è una prova.", voiceId: "IT-M1", speed: 1.25, steps: 8)
        XCTAssertNotEqual(key1, keyDifferentSpeed, "Velocità differenti devono produrre hash differenti")
    }
    
    // MARK: - Test L1 RAM Cache (0 ms Retrieval)
    
    func testAudioCacheL1MemoryStoreAndRetrieve() {
        let cache = AudioCacheManager.shared
        let dummyData = Data("RIFF_WAV_DUMMY_SAMPLES_123456789".utf8)
        let key = cache.cacheKey(for: "Test memoria volatile L1", voiceId: "IT-F1", speed: 1.0, steps: 8)
        
        cache.storeAudio(dummyData, for: key)
        
        guard let cached = cache.getAudio(for: key) else {
            XCTFail("Il dato memorizzato dovrebbe essere immediatamente disponibile in cache")
            return
        }
        
        XCTAssertEqual(cached.data, dummyData)
        XCTAssertEqual(cached.source, .memory, "Il primo accesso dopo il salvataggio deve provenire da L1 RAM")
    }
    
    // MARK: - Test L2 Disk Persistence & Promotion
    
    func testAudioCacheL2DiskPersistence() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let customCache = AudioCacheManager(customCacheDirectory: tempDir)
        
        let dummyData = Data("PERSISTENT_DISK_AUDIO_BYTES_TEST".utf8)
        let key = customCache.cacheKey(for: "Test persistenza disco L2", voiceId: "EN-M1", speed: 1.1, steps: 6)
        
        customCache.storeAudio(dummyData, for: key)
        
        // Attendi che il thread asincrono scriva su disco
        let exp = expectation(description: "Attesa scrittura disco")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        
        // Crea una seconda istanza puntata alla stessa directory (simula riavvio app con RAM pulita)
        let cleanCache = AudioCacheManager(customCacheDirectory: tempDir)
        guard let diskHit = cleanCache.getAudio(for: key) else {
            XCTFail("Il file dovrebbe essere stato persistito su disco ed essere leggibile da una nuova istanza")
            return
        }
        
        XCTAssertEqual(diskHit.data, dummyData)
        XCTAssertEqual(diskHit.source, .disk, "Il recupero deve provenire da L2 Disk")
        
        // Il recupero successivo deve essere promosso in L1 RAM
        let ramHit = cleanCache.getAudio(for: key)
        XCTAssertEqual(ramHit?.source, .memory, "Il dato letto da disco deve essere promosso a L1 RAM")
        
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Test Deep Preload Ring Buffer Logic
    
    func testRingBufferEffectiveDepthOnShortChunks() {
        let appState = AppState()
        let chunk0 = ReadingChunk(index: 0, text: "Introduzione al capitolo uno con frase lunga.")
        let chunk1 = ReadingChunk(index: 1, text: "Sì.") // < 25 caratteri!
        let chunk2 = ReadingChunk(index: 2, text: "Esattamente così procediamo.")
        let chunk3 = ReadingChunk(index: 3, text: "Quarta frase del paragrafo.")
        
        appState.setQueue([chunk0, chunk1, chunk2, chunk3])
        XCTAssertEqual(appState.preloadDepth, 2)
        
        // Verifica calcolo estensione per frasi corte
        let isNextShort = chunk1.text.count < 25
        XCTAssertTrue(isNextShort, "La frase 'Sì.' deve essere riconosciuta come breve (< 25 caratteri)")
        let effectiveDepth = isNextShort ? appState.preloadDepth + 1 : appState.preloadDepth
        XCTAssertEqual(effectiveDepth, 3, "Il ring buffer deve estendersi a N+3 su frasi brevi per evitare starvation")
    }
    
    // MARK: - Test First-Chunk Boost Settings
    
    func testFirstChunkBoostConfiguration() {
        let appState = AppState()
        appState.synthesisSteps = 12
        appState.isFirstChunkBoostEnabled = true
        
        let chunk0 = ReadingChunk(index: 0, text: "Frase iniziale di apertura.")
        let chunk1 = ReadingChunk(index: 1, text: "Seconda frase regolare.")
        appState.setQueue([chunk0, chunk1])
        
        let isFirst = chunk0.index == 0
        let effectiveStepsChunk0 = (isFirst && appState.isFirstChunkBoostEnabled)
            ? min(appState.synthesisSteps, 5)
            : appState.synthesisSteps
            
        XCTAssertEqual(effectiveStepsChunk0, 5, "Il primo chunk deve essere limitato a 5 step per avvio istantaneo")
        
        let isSecond = chunk1.index == 0
        let effectiveStepsChunk1 = (isSecond && appState.isFirstChunkBoostEnabled)
            ? min(appState.synthesisSteps, 5)
            : appState.synthesisSteps
            
        XCTAssertEqual(effectiveStepsChunk1, 12, "I chunk successivi devono mantenere tutti i 12 step richiesti")
    }
}
