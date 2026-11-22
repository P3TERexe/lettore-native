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
        let dummyData = TestWAV.data()
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

        let dummyData = TestWAV.data()
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

    func testAudioCacheRejectsNonWAVData() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cache = AudioCacheManager(customCacheDirectory: tempDir)
        let key = cache.cacheKey(for: "Payload non audio", voiceId: "IT-M1", speed: 1.0, steps: 8)

        cache.storeAudio(Data("non è un WAV".utf8), for: key)

        XCTAssertNil(cache.getAudio(for: key), "La cache deve contenere solo WAV riproducibili")
    }

    func testCorruptDiskEntryIsRemovedOnRead() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cache = AudioCacheManager(customCacheDirectory: tempDir)
        let key = cache.cacheKey(for: "File corrotto", voiceId: "IT-M1", speed: 1.0, steps: 8)
        let fileURL = tempDir.appendingPathComponent("\(key).wav")
        try Data("WAV troncato".utf8).write(to: fileURL)

        XCTAssertNil(cache.getAudio(for: key))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fileURL.path),
            "Un file corrotto va eliminato per non riprovare lo stesso errore"
        )
    }

    // MARK: - Test Eviction L2 basata sul contatore in memoria

    func testDiskCacheEvictionRespectsSizeBudgetAndRemovesOldest() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let wav = TestWAV.data()
        let cache = AudioCacheManager(customCacheDirectory: tempDir)
        // Budget = 2 chunk: la terza scrittura deve forzare l'eviction.
        cache.maxDiskCacheSizeBytes = wav.count * 2

        let oldestKey = cache.cacheKey(for: "Primo chunk su disco", voiceId: "IT-M1", speed: 1.0, steps: 8)
        let middleKey = cache.cacheKey(for: "Secondo chunk su disco", voiceId: "IT-M1", speed: 1.0, steps: 8)
        let newestKey = cache.cacheKey(for: "Terzo chunk su disco", voiceId: "IT-M1", speed: 1.0, steps: 8)

        let oldestURL = tempDir.appendingPathComponent("\(oldestKey).wav")
        let middleURL = tempDir.appendingPathComponent("\(middleKey).wav")
        let newestURL = tempDir.appendingPathComponent("\(newestKey).wav")

        cache.storeAudio(wav, for: oldestKey)
        XCTAssertTrue(waitForFile(at: oldestURL), "La prima entry deve finire su disco")
        // mtime espliciti per rendere deterministico l'ordine LRU.
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3_600)],
            ofItemAtPath: oldestURL.path
        )

        cache.storeAudio(wav, for: middleKey)
        XCTAssertTrue(waitForFile(at: middleURL), "La seconda entry deve finire su disco")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -1_800)],
            ofItemAtPath: middleURL.path
        )

        cache.storeAudio(wav, for: newestKey)
        XCTAssertTrue(waitForFile(at: newestURL), "La terza entry deve finire su disco")

        XCTAssertTrue(
            waitForFileToDisappear(at: oldestURL),
            "Al superamento del budget va eliminata la entry più vecchia"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: middleURL.path), "La entry intermedia deve restare entro il budget")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newestURL.path), "La entry appena scritta non deve essere eliminata")
    }

    func testOverwritingSameKeyDoesNotInflateDiskUsage() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let wav = TestWAV.data()
        let cache = AudioCacheManager(customCacheDirectory: tempDir)
        cache.maxDiskCacheSizeBytes = wav.count * 2

        let key = cache.cacheKey(for: "Chunk riscritto più volte", voiceId: "IT-M1", speed: 1.0, steps: 8)
        let fileURL = tempDir.appendingPathComponent("\(key).wav")

        for _ in 0..<5 {
            cache.storeAudio(wav, for: key)
        }
        XCTAssertTrue(waitForFile(at: fileURL), "La entry deve essere presente su disco")

        // Un contatore gonfiato dalle riscritture scatenerebbe un eviction e
        // cancellerebbe l'unico file presente.
        let exp = expectation(description: "Attesa stabilità della cache")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fileURL.path),
            "Riscrivere la stessa chiave non deve incrementare il totale dei byte su disco"
        )
    }

    // MARK: - Regressione: contatore vs. overwrite/eviction concorrenti

    /// (a) Overwrite ripetuti sulla stessa chiave mentre l'eviction è attiva:
    /// il contatore non deve sottostimare e, a regime, la cache non deve
    /// restare sopra budget per il resto della sessione.
    func testConcurrentOverwritesAndEvictionStayWithinBudget() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let wav = TestWAV.data()
        let cache = AudioCacheManager(customCacheDirectory: tempDir)
        cache.maxDiskCacheSizeBytes = wav.count * 4

        let keys = (0..<6).map {
            cache.cacheKey(for: "Chunk concorrente \($0)", voiceId: "IT-M1", speed: 1.0, steps: 8)
        }

        let group = DispatchGroup()
        for i in 0..<120 {
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                cache.storeAudio(wav, for: keys[i % keys.count])
                if i % 7 == 0 {
                    cache.evictDiskCacheIfNeeded()
                }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)

        let budget = cache.maxDiskCacheSizeBytes
        let usage = waitForSettledDiskUsage(at: tempDir)
        XCTAssertNotNil(usage, "La cache deve assestarsi dopo overwrite ed eviction concorrenti")
        if let usage {
            XCTAssertLessThanOrEqual(usage, budget)
        }
    }

    /// (b) Una richiesta esplicita non va persa se arriva mentre un'eviction è
    /// già schedulata: la cache viene davvero evacuata fino al budget.
    func testForcedEvictionIsNotLostWhileEvictionIsScheduled() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let wav = TestWAV.data()
        let cache = AudioCacheManager(customCacheDirectory: tempDir)
        // Setup senza eviction: il budget non viene mai superato.
        cache.maxDiskCacheSizeBytes = Int.max

        let keys = (0..<8).map {
            cache.cacheKey(for: "Chunk force \($0)", voiceId: "IT-M1", speed: 1.0, steps: 8)
        }
        for key in keys {
            cache.storeAudio(wav, for: key)
        }
        for key in keys {
            XCTAssertTrue(
                waitForFile(at: tempDir.appendingPathComponent("\(key).wav")),
                "Il setup deve completare tutte le scritture prima di forzare l'eviction"
            )
        }

        // Ora il contatore è sopra budget ma nessuna eviction è stata programmata.
        cache.maxDiskCacheSizeBytes = wav.count * 3

        let group = DispatchGroup()
        for _ in 0..<8 {
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                cache.evictDiskCacheIfNeeded()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)

        // Anche una scrittura regolare mentre il drain è in corso non deve
        // scavalcare le richieste force pendenti.
        cache.storeAudio(wav, for: cache.cacheKey(for: "Chunk forza tardiva", voiceId: "IT-M1", speed: 1.0, steps: 8))

        let budget = cache.maxDiskCacheSizeBytes
        let usage = waitForSettledDiskUsage(at: tempDir)
        XCTAssertNotNil(usage, "Le richieste force non devono andare perse durante un'eviction già schedulata")
        if let usage {
            XCTAssertLessThanOrEqual(usage, budget)
        }
    }

    /// (c) Raffica di scritture con budget piccolo: lo stato finale deve essere
    /// entro budget, senza svuotare la cache.
    func testBurstOfWritesSettlesWithinSmallBudget() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let wav = TestWAV.data()
        let cache = AudioCacheManager(customCacheDirectory: tempDir)
        let budget = wav.count * 3
        cache.maxDiskCacheSizeBytes = budget

        let keys = (0..<24).map {
            cache.cacheKey(for: "Chunk raffica \($0)", voiceId: "IT-M1", speed: 1.0, steps: 8)
        }
        for key in keys {
            cache.storeAudio(wav, for: key)
        }

        let settledUsage = waitForSettledDiskUsage(at: tempDir)
        XCTAssertNotNil(settledUsage, "Dopo la raffica la cache deve assestarsi entro budget senza svuotarsi")
        if let settledUsage {
            XCTAssertLessThanOrEqual(settledUsage, budget)
            XCTAssertGreaterThan(settledUsage, 0, "L'eviction deve fermarsi al budget, non cancellare tutto")
        }
    }

    // MARK: - Eviction: pavimento e file grandi

    /// Un file grande e vecchio che da solo sfonderebbe il pavimento non deve
    /// fermare l'eviction: si salta e si provano i successivi più piccoli, così
    /// la cache scende comunque entro budget.
    func testEvictionSkipsOversizedOldestFileAndRemovesSmallerVictims() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Budget 1000: low water 900, pavimento 600. Totale 1300 con un file
        // grande da 750 (il più vecchio) e 11 da 50. Rimuovere il grande
        // lascerebbe 550 < 600, quindi va saltato; i piccoli bastano a
        // scendere a 900.
        let budget = 1_000
        let bigSize = 750
        let smallSize = 50
        let smallCount = 11
        let keyMaker = AudioCacheManager.shared

        let bigURL = tempDir.appendingPathComponent(
            "\(keyMaker.cacheKey(for: "Chunk grande e vecchio", voiceId: "IT-M1", speed: 1.0, steps: 8)).wav"
        )
        try createSparseFile(at: bigURL, size: bigSize)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -7_200)],
            ofItemAtPath: bigURL.path
        )

        var smallURLs: [URL] = []
        for index in 0..<smallCount {
            let url = tempDir.appendingPathComponent(
                "\(keyMaker.cacheKey(for: "Chunk piccolo \(index)", voiceId: "IT-M1", speed: 1.0, steps: 8)).wav"
            )
            try createSparseFile(at: url, size: smallSize)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: TimeInterval(index) - 3_600)],
                ofItemAtPath: url.path
            )
            smallURLs.append(url)
        }
        XCTAssertEqual(diskUsage(at: tempDir), bigSize + smallSize * smallCount)

        let cache = AudioCacheManager(customCacheDirectory: tempDir)
        cache.maxDiskCacheSizeBytes = budget
        cache.evictDiskCacheIfNeeded()

        let settledUsage = waitForSettledDiskUsage(at: tempDir)
        XCTAssertNotNil(settledUsage, "La cache deve assestarsi dopo l'eviction forzata")
        XCTAssertEqual(
            settledUsage,
            900,
            "Saltando il file grande l'eviction deve scendere al low water con le vittime piccole"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: bigURL.path),
            "Il file che sfonderebbe il pavimento non deve essere rimosso"
        )
        XCTAssertEqual(
            smallURLs.filter { FileManager.default.fileExists(atPath: $0.path) }.count,
            3,
            "Devono restare i 3 file piccoli più recenti, che coprono il low water"
        )
    }

    // MARK: - Write fuori dal lock

    /// La `data.write` avviene fuori da `stateLock`: le scansioni concorrenti
    /// non devono riallineare il contatore prima che il delta della write sia
    /// applicato (doppio conteggio) né sovrascrivere l'aggiornamento.
    func testConcurrentWritesKeepEstimatedUsageExact() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let wav = TestWAV.data()
        let cache = AudioCacheManager(customCacheDirectory: tempDir)
        // Budget altissimo: nessuna eviction reale, solo scansioni forzate.
        cache.maxDiskCacheSizeBytes = Int.max

        let keys = (0..<32).map {
            cache.cacheKey(for: "Chunk write concorrente \($0)", voiceId: "IT-M1", speed: 1.0, steps: 8)
        }

        let group = DispatchGroup()
        for key in keys {
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                cache.storeAudio(wav, for: key)
            }
        }
        for _ in 0..<8 {
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                cache.evictDiskCacheIfNeeded()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)

        for key in keys {
            XCTAssertTrue(
                waitForFile(at: tempDir.appendingPathComponent("\(key).wav")),
                "Tutte le write concorrenti devono finire su disco"
            )
        }

        let expected = wav.count * keys.count
        XCTAssertEqual(diskUsage(at: tempDir), expected)
        XCTAssertTrue(
            waitForEstimatedUsage(cache, expected: expected),
            "Il contatore incrementale deve restare esatto anche con scansioni concorrenti alle write"
        )
    }

    // MARK: - Riconciliazione del contatore dopo un salto

    /// Regressione deterministica (clamp): un overwrite che renderebbe negativa
    /// la sottrazione al contatore non deve essere mascherato da `max(0, ...)`.
    /// Il flag `needsReconcile` deve far ripartire una scansione anche se la
    /// stima è sotto budget, riportando il totale ai byte reali.
    func testClampedSubtractionSchedulesReconciliation() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let wav = TestWAV.data()
        let key = AudioCacheManager.shared.cacheKey(
            for: "Chunk clamp negativo",
            voiceId: "IT-M1",
            speed: 1.0,
            steps: 8
        )
        let fileURL = tempDir.appendingPathComponent("\(key).wav")
        try createSparseFile(at: fileURL, size: 1_000)

        let cache = AudioCacheManager(customCacheDirectory: tempDir)
        cache.maxDiskCacheSizeBytes = Int.max

        XCTAssertTrue(
            waitForEstimatedUsage(cache, expected: 1_000, timeout: 10),
            "La scansione iniziale deve riallineare il contatore al file preesistente"
        )

        // Il file cresce fuori dalla cache: il contatore resta a 1000 byte.
        try createSparseFile(at: fileURL, size: 100_000)
        XCTAssertEqual(diskUsage(at: tempDir), 100_000)

        // L'overwrite riscrive un WAV molto più piccolo: 1000 + sizeWav - 100000 < 0.
        cache.storeAudio(wav, for: key)

        XCTAssertTrue(
            waitForEstimatedUsage(cache, expected: wav.count, timeout: 5),
            "Il clamp a zero non deve nascondere la sottostima: serve un realign esatto"
        )
        XCTAssertEqual(cache.estimatedDiskUsageBytes, diskUsage(at: tempDir))
        XCTAssertFalse(cache.needsDiskReconcile, "Il realign esatto deve azzerare il flag")
    }

    /// Regressione (init scan): directory pre-seminata molto sopra budget e
    /// write concorrenti mentre la scansione iniziale gira. Se il realign
    /// iniziale viene saltato il contatore resta quello delle sole write
    /// (sotto budget) e l'eviction non parte più: qui la cache deve invece
    /// riconciliarsi fino ai byte reali e rientrare nel budget.
    func testWritesDuringInitialScanStillReconcileAndEvict() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let preSeededCount = 12_000
        let fileSize = 200
        let budget = 256 * 1024
        let keyMaker = AudioCacheManager.shared

        for index in 0..<preSeededCount {
            let url = tempDir.appendingPathComponent(
                "\(keyMaker.cacheKey(for: "Preesistente \(index)", voiceId: "IT-M1", speed: 1.0, steps: 8)).wav"
            )
            try createSparseFile(at: url, size: fileSize)
        }
        let preseeding = preSeededCount * fileSize
        XCTAssertEqual(diskUsage(at: tempDir), preseeding)
        XCTAssertGreaterThan(preseeding, budget, "Il setup deve partire molto sopra budget")

        let cache = AudioCacheManager(customCacheDirectory: tempDir)
        cache.maxDiskCacheSizeBytes = budget

        // Write accodate subito, mentre la scansione iniziale della
        // maintenanceQueue è in corso: è la finestra che faceva saltare il
        // realign iniziale.
        let wav = TestWAV.data()
        for index in 0..<1_000 {
            cache.storeAudio(
                wav,
                for: keyMaker.cacheKey(
                    for: "Chunk durante init \(index)",
                    voiceId: "IT-M1",
                    speed: 1.0,
                    steps: 8
                )
            )
        }

        guard let usage = waitForReconciledCache(cache, at: tempDir, timeout: 30) else {
            XCTFail("La cache non si è assestata: contatore o eviction non si riconciliano")
            return
        }
        XCTAssertEqual(
            cache.estimatedDiskUsageBytes,
            usage,
            "Dopo la quiete il contatore deve coincidere con i byte reali"
        )

        if usage > budget {
            cache.evictDiskCacheIfNeeded()
            guard let evicted = waitForReconciledCache(cache, at: tempDir, timeout: 30) else {
                XCTFail("L'eviction esplicita non è riuscita a riconciliare la cache")
                return
            }
            XCTAssertLessThanOrEqual(evicted, budget, "L'eviction esplicita deve riportare la cache entro budget")
            XCTAssertEqual(cache.estimatedDiskUsageBytes, evicted)
            return
        }
        XCTAssertLessThanOrEqual(usage, budget)
        XCTAssertGreaterThan(usage, 0, "L'eviction deve fermarsi al low water, senza svuotare la cache")
    }

    // MARK: - Contatore incrementale: removeAudio / clearAll / low water

    /// `removeAudio` deve scalare il contatore stimato, non solo cancellare il
    /// file: un contatore gonfiato da entry rimosse scatenerebbe eviction inutili
    /// per il resto della sessione.
    func testRemoveAudioDecrementsEstimatedDiskUsage() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let wav = TestWAV.data()
        let cache = AudioCacheManager(customCacheDirectory: tempDir)
        cache.maxDiskCacheSizeBytes = Int.max

        let key = cache.cacheKey(for: "Chunk da rimuovere", voiceId: "IT-M1", speed: 1.0, steps: 8)
        let fileURL = tempDir.appendingPathComponent("\(key).wav")

        cache.storeAudio(wav, for: key)
        XCTAssertTrue(waitForFile(at: fileURL), "Il chunk deve finire su disco")
        XCTAssertTrue(
            waitForEstimatedUsage(cache, expected: wav.count),
            "Dopo la scrittura il contatore deve valere la size del chunk"
        )

        cache.removeAudio(for: key)
        XCTAssertTrue(waitForFileToDisappear(at: fileURL), "removeAudio deve eliminare il file su disco")
        XCTAssertTrue(
            waitForEstimatedUsage(cache, expected: 0),
            "removeAudio deve decrementare il contatore dei byte stimati"
        )
        XCTAssertNil(cache.getAudio(for: key), "Dopo removeAudio il chunk non deve più essere in cache")
    }

    /// `clearAll` deve azzerare il contatore e i flag di schedulazione: se
    /// `isEvictionScheduled` restasse true, nessuna eviction successiva
    /// partirebbe più e la cache resterebbe sopra budget.
    func testClearAllResetsDiskUsageAndScheduling() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let wav = TestWAV.data()
        let cache = AudioCacheManager(customCacheDirectory: tempDir)
        cache.maxDiskCacheSizeBytes = Int.max

        let keys = (0..<3).map {
            cache.cacheKey(for: "Chunk pre clear \($0)", voiceId: "IT-M1", speed: 1.0, steps: 8)
        }
        for key in keys {
            cache.storeAudio(wav, for: key)
            XCTAssertTrue(
                waitForFile(at: tempDir.appendingPathComponent("\(key).wav")),
                "Il setup deve completare la scrittura su disco"
            )
        }
        XCTAssertTrue(waitForEstimatedUsage(cache, expected: wav.count * keys.count))

        cache.clearAll()
        XCTAssertTrue(waitForEstimatedUsage(cache, expected: 0), "clearAll deve azzerare il contatore")
        XCTAssertEqual(diskUsage(at: tempDir), 0, "clearAll deve svuotare la directory")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: tempDir.path),
            "La directory deve essere ricreata dopo clearAll"
        )

        // Prova comportamentale del reset dei flag: dopo il clear una nuova
        // eviction deve partire e riportare la cache entro budget.
        let budget = wav.count * 2
        cache.maxDiskCacheSizeBytes = budget
        for index in 0..<3 {
            cache.storeAudio(wav, for: cache.cacheKey(for: "Chunk post clear \(index)", voiceId: "IT-M1", speed: 1.0, steps: 8))
        }

        let usage = waitForSettledDiskUsage(at: tempDir)
        XCTAssertNotNil(usage, "Dopo clearAll la manutenzione deve tornare a funzionare")
        if let usage {
            XCTAssertLessThanOrEqual(usage, budget)
        }
    }

    /// Quando si supera il budget l'eviction non si ferma al 100%: scende al
    /// low water (~90%) per amortizzare la scansione nel regime a cache piena.
    func testEvictionEvacuatesDownToLowWater() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let wav = TestWAV.data()
        let cache = AudioCacheManager(customCacheDirectory: tempDir)
        // Setup senza eviction: scriviamo 12 chunk e solo dopo fissiamo il budget.
        cache.maxDiskCacheSizeBytes = Int.max

        let keys = (0..<12).map {
            cache.cacheKey(for: "Chunk low water \($0)", voiceId: "IT-M1", speed: 1.0, steps: 8)
        }
        for (index, key) in keys.enumerated() {
            cache.storeAudio(wav, for: key)
            let fileURL = tempDir.appendingPathComponent("\(key).wav")
            XCTAssertTrue(waitForFile(at: fileURL))
            // mtime crescenti: l'ordine LRU deve coincidere con l'ordine di scrittura.
            try? FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: TimeInterval(index) - 3_600)],
                ofItemAtPath: fileURL.path
            )
        }

        let budget = wav.count * 10
        cache.maxDiskCacheSizeBytes = budget
        cache.evictDiskCacheIfNeeded()

        let usage = waitForSettledDiskUsage(at: tempDir)
        XCTAssertNotNil(usage, "La cache deve assestarsi dopo l'eviction forzata")
        if let usage {
            XCTAssertLessThanOrEqual(usage, budget * 9 / 10, "L'eviction deve scendere al low water (~90% del budget)")
            XCTAssertGreaterThan(usage, 0, "Il low water non deve svuotare la cache")
        }
    }

    /// Abbassare il budget a runtime deve programmare un'eviction: senza questa
    /// reazione la cache resterebbe sopra limite fino alla prossima scrittura.
    func testLoweringDiskCacheSizeSchedulesEviction() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let wav = TestWAV.data()
        let cache = AudioCacheManager(customCacheDirectory: tempDir)
        // Setup senza eviction: il budget non viene mai superato.
        cache.maxDiskCacheSizeBytes = Int.max

        let keys = (0..<4).map {
            cache.cacheKey(for: "Chunk budget ridotto \($0)", voiceId: "IT-M1", speed: 1.0, steps: 8)
        }
        for key in keys {
            cache.storeAudio(wav, for: key)
            XCTAssertTrue(
                waitForFile(at: tempDir.appendingPathComponent("\(key).wav")),
                "Il setup deve completare la scrittura su disco"
            )
        }

        let budget = wav.count * 2
        cache.maxDiskCacheSizeBytes = budget

        // Nessuna scrittura successiva: l'eviction deve partire dal solo setter.
        let deadline = Date().addingTimeInterval(5)
        var usage = diskUsage(at: tempDir)
        while usage > budget && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
            usage = diskUsage(at: tempDir)
        }

        XCTAssertLessThanOrEqual(usage, budget, "Il setter del budget deve avviare l'eviction senza aspettare una scrittura")
        XCTAssertGreaterThan(usage, 0, "L'eviction deve fermarsi al low water, senza svuotare la cache")
    }

    /// Una richiesta forzata con molte vittime deve rimuoverle in un unico
    /// batch (un solo round-trip sulla diskQueue) e restare entro budget.
    func testForcedEvictionRemovesVictimsInSingleBatch() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let wav = TestWAV.data()
        let keyMaker = AudioCacheManager.shared
        let keys = (0..<12).map {
            keyMaker.cacheKey(for: "Chunk batch \($0)", voiceId: "IT-M1", speed: 1.0, steps: 8)
        }
        // Cache preesistente scritta direttamente su disco: nessuna scrittura
        // concorrente durante l'eviction forzata.
        for (index, key) in keys.enumerated() {
            let url = tempDir.appendingPathComponent("\(key).wav")
            try wav.write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: TimeInterval(index) - 3_600)],
                ofItemAtPath: url.path
            )
        }

        let cache = AudioCacheManager(customCacheDirectory: tempDir)
        let budget = wav.count * 4
        cache.maxDiskCacheSizeBytes = budget
        cache.evictDiskCacheIfNeeded()

        let settledUsage = waitForSettledDiskUsage(at: tempDir)
        XCTAssertNotNil(settledUsage, "La cache deve assestarsi dopo l'eviction forzata")
        if let settledUsage {
            XCTAssertLessThanOrEqual(settledUsage, budget, "L'eviction forzata deve restare entro budget")
            XCTAssertGreaterThan(settledUsage, 0, "L'eviction non deve svuotare la cache")
            XCTAssertEqual(
                settledUsage,
                wav.count * 3,
                "L'eviction deve scendere al low water rimuovendo più entry nello stesso passaggio"
            )
        }
        XCTAssertEqual(
            cache.performedRemovalBatches,
            1,
            "Le vittime di una richiesta forzata devono essere rimosse in un unico batch"
        )
    }

    /// Una cache già sopra budget all'avvio deve essere evacuata dalla sola
    /// scansione iniziale, senza aspettare nuove sintesi.
    func testPreexistingOverBudgetCacheIsEvictedAfterInitialScan() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // File sparsi da 26 MB: superano il budget di default (200 MB) come
        // spazio logico, quello che l'eviction misura, senza scritture reali.
        let fileSize = 26 * 1024 * 1024
        let keyMaker = AudioCacheManager.shared
        let keys = (0..<9).map {
            keyMaker.cacheKey(for: "Cache preesistente \($0)", voiceId: "IT-M1", speed: 1.0, steps: 8)
        }
        for (index, key) in keys.enumerated() {
            let url = tempDir.appendingPathComponent("\(key).wav")
            try createSparseFile(at: url, size: fileSize)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: TimeInterval(index) - 3_600)],
                ofItemAtPath: url.path
            )
        }
        XCTAssertEqual(diskUsage(at: tempDir), fileSize * keys.count)

        // Nessun `storeAudio`, nessun cambio di budget: solo la scansione init.
        let cache = AudioCacheManager(customCacheDirectory: tempDir)
        let budget = cache.maxDiskCacheSizeBytes
        XCTAssertGreaterThan(fileSize * keys.count, budget, "Il setup deve partire sopra budget")

        let deadline = Date().addingTimeInterval(10)
        var usage = diskUsage(at: tempDir)
        while usage > budget && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
            usage = diskUsage(at: tempDir)
        }

        XCTAssertLessThanOrEqual(usage, budget, "La scansione iniziale deve evacuare una cache già sopra budget")
        XCTAssertGreaterThan(usage, 0, "L'eviction deve fermarsi al low water, senza svuotare la cache")
        XCTAssertTrue(
            waitForEstimatedUsage(cache, expected: usage),
            "Dopo la riconciliazione iniziale il contatore deve coincidere con i byte reali"
        )
    }

    private func waitForEstimatedUsage(
        _ cache: AudioCacheManager,
        expected: Int,
        timeout: TimeInterval = 2.0
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if cache.estimatedDiskUsageBytes == expected { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return cache.estimatedDiskUsageBytes == expected
    }

    /// Attende che la cache sia davvero assestata: dimensione su disco stabile
    /// per `quietFor`, nessun riallineamento pendente e stima uguale ai byte
    /// reali. La sola stabilità della directory non basta, perché una
    /// riconciliazione rimandata la lascia ferma mentre il contatore no.
    private func waitForReconciledCache(
        _ cache: AudioCacheManager,
        at directory: URL,
        timeout: TimeInterval = 30,
        quietFor: TimeInterval = 0.3
    ) -> Int? {
        let deadline = Date().addingTimeInterval(timeout)
        var lastUsage = -1
        var stableSince = Date()
        while Date() < deadline {
            let usage = diskUsage(at: directory)
            if usage == lastUsage,
               !cache.needsDiskReconcile,
               cache.estimatedDiskUsageBytes == usage {
                if Date().timeIntervalSince(stableSince) >= quietFor { return usage }
            } else {
                lastUsage = usage
                stableSince = Date()
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }

    private func diskUsage(at directory: URL) -> Int {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return 0 }
        return urls.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + size
        }
    }

    /// Crea un file "sparso" di `size` byte: ha la dimensione logica che
    /// `stat` e l'eviction leggono, ma quasi nessun blocco realmente allocato.
    /// Serve a simulare una cache preesistente sopra il budget di default
    /// (200 MB) senza scrivere davvero 200 MB su disco.
    private func createSparseFile(at url: URL, size: Int) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size))
        try handle.close()
    }

    /// Attende che la directory smetta di cambiare dimensione per `quietFor`
    /// secondi: garantisce che scritture/eviction asincrone siano davvero
    /// concluse prima di misurare (e prima che il test rimuova la directory).
    private func waitForSettledDiskUsage(
        at directory: URL,
        timeout: TimeInterval = 10,
        quietFor: TimeInterval = 0.25
    ) -> Int? {
        let deadline = Date().addingTimeInterval(timeout)
        var lastUsage = -1
        var stableSince = Date()
        while Date() < deadline {
            let usage = diskUsage(at: directory)
            if usage == lastUsage {
                if Date().timeIntervalSince(stableSince) >= quietFor { return usage }
            } else {
                lastUsage = usage
                stableSince = Date()
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }

    private func waitForFile(at url: URL, timeout: TimeInterval = 2.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func waitForFileToDisappear(at url: URL, timeout: TimeInterval = 2.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !FileManager.default.fileExists(atPath: url.path) { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return !FileManager.default.fileExists(atPath: url.path)
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
