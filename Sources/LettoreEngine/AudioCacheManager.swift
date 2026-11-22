import Foundation
import CryptoKit

/// Origine del dato audio recuperato dalla cache.
public enum AudioCacheSource: String, Sendable {
    case memory = "L1_RAM"
    case disk = "L2_Disk"
}

/// Gestore di cache audio a due livelli per Lettore.
/// L1: RAM volatile ad altissima velocità via NSCache (thread-safe, zero latenza).
/// L2: Cache persistente su disco in ~/Library/Caches/Lettore/audio_cache/ indicizzata via SHA-256.
public final class AudioCacheManager: @unchecked Sendable {
    
    public static let shared = AudioCacheManager()
    
    private let memoryCache = NSCache<NSString, NSData>()
    private let fileManager = FileManager.default
    private let cacheDirectoryURL: URL
    private let diskQueue = DispatchQueue(label: "it.lettore.audiocache.disk", qos: .utility)
    /// Marcatore della `diskQueue`: serve a chi deve serializzare una rimozione
    /// senza rischiare un `sync` verso la coda su cui sta già girando.
    /// Vive per istanza, non staticamente: con una chiave condivisa un thread
    /// che gira sulla coda di un'altra cache verrebbe scambiato per "già sulla
    /// coda" e salterebbe il `sync` necessario.
    private let diskQueueKey = DispatchSpecificKey<UInt8>()
    /// Coda dedicata alla manutenzione: un eviction non deve mai mettersi in
    /// coda davanti alle letture di playback sulla diskQueue.
    private let maintenanceQueue = DispatchQueue(label: "it.lettore.audiocache.maintenance", qos: .background)
    /// Coda dedicata ai touch LRU (`setAttributes`): accodare il touch sulla
    /// `diskQueue` faceva pagare `stat` + `setAttributes` alla prima lettura
    /// successiva di ogni chiave, perché il blocco finiva davanti al read.
    private let touchQueue = DispatchQueue(label: "it.lettore.audiocache.touch", qos: .utility)
    private let stateLock = NSLock()

    /// Byte totali stimati su disco. Evita una scansione completa della
    /// directory a ogni scrittura: viene inizializzato una sola volta e poi
    /// aggiornato incrementalmente su write/remove. Il contatore non è MAI
    /// l'unica fonte di verità: ogni passaggio di eviction riparte dalla
    /// scansione reale, così un eventuale errore non resta per la sessione.
    private var totalDiskBytes = 0
    private var isEvictionScheduled = false
    /// Una richiesta di eviction arrivata mentre un passaggio è in volo non va
    /// persa: il ciclo di drain la consuma in un secondo passaggio.
    private var pendingEviction = false
    /// Richiesta esplicita (`evictDiskCacheIfNeeded`): deve sempre produrre una
    /// scansione, anche se il contatore stimato dice che siamo sotto budget.
    private var pendingForcedEviction = false
    /// Contatore monotono delle mutazioni (write/remove): permette all'eviction
    /// di capire se può riallineare il totale senza perdere aggiornamenti.
    private var diskMutationCount = 0
    /// Write su disco in corso (I/O fuori da `stateLock`): finché è > 0 una
    /// scansione non può riallineare il totale, perché il listing può già
    /// includere il file mentre il suo delta arriverà dopo.
    private var inFlightWrites = 0
    /// Vero solo dopo che una scansione completa ha davvero riallineato il
    /// contatore. Finché è falso una mutazione riprova il riallineamento: se la
    /// scansione iniziale fallisce (directory non leggibile), il contatore non
    /// può restare a zero per tutta la sessione e l'eviction non partirebbe mai.
    private var didInitializeDiskUsage = false
    /// Vero quando un riallineamento esatto è stato rimandato: write in volo,
    /// generazione cambiata durante la scansione, oppure un clamp a zero che
    /// nasconde una sottrazione negativa. Finché è acceso il contatore stimato
    /// non è affidabile e la manutenzione deve ri-scandire la directory anche
    /// se la stima dice che siamo sotto budget. Si spegne solo quando il totale
    /// viene riallineato ai byte reali.
    private var needsReconcile = false
    /// Diagnostica (test): quanti batch di rimozione non vuoti ha eseguito
    /// l'eviction in questa sessione. Un solo batch = una richiesta forzata ha
    /// raggruppato tutte le vittime in un unico round-trip sulla `diskQueue`.
    private var removalBatchCount = 0
    /// Obiettivo di evacuazione quando si supera il budget: ~90% del budget.
    /// Lasciare margine evita una scansione a ogni singola scrittura nel
    /// regime a cache piena.
    private static let evictionLowWaterRatio = 0.9
    /// Pavimento dell'eviction: non si scende sotto il 60% del budget, così una
    /// cache piccola (pochi file grandi) non viene svuotata per un solo chunk
    /// di troppo. I file che sfonderebbero il pavimento vengono saltati, non
    /// usati come stop: se un file grande è troppo vecchio ma non rimovibile,
    /// l'eviction prova comunque con i successivi più piccoli.
    private static let evictionFloorRatio = 0.6
    /// Ultimo touch registrato per chiave, per non eseguire un setAttributes
    /// (syscall) a ogni hit L2.
    private var lastTouchDates: [String: Date] = [:]
    private let touchInterval: TimeInterval = 60 * 60

    /// Storage del budget. Vive dietro `stateLock`: chi legge o scrive già
    /// dentro una sezione lockata deve usare SOLO questo campo, perché NSLock
    /// non è ricorsivo (un accessor pubblico dentro il lock andrebbe in deadlock).
    private var _maxDiskCacheSizeBytes: Int = 200 * 1024 * 1024

    /// Dimensione massima della cache su disco in bytes (default: 200 MB).
    ///
    /// Accessor protetto da `stateLock`: la proprietà è modificabile a runtime
    /// (test e tuning), quindi la lettura non può essere un semplice campo
    /// condiviso senza sincronizzazione.
    public var maxDiskCacheSizeBytes: Int {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _maxDiskCacheSizeBytes
        }
        set {
            stateLock.lock()
            _maxDiskCacheSizeBytes = newValue
            stateLock.unlock()
            // Abbassare il budget può rendere la cache subito fuori budget:
            // senza questa richiesta l'eviction partirebbe solo alla prossima
            // scrittura e la cache resterebbe sopra limite. Fuori dal lock
            // perché `scheduleEviction` lo riacquisisce (NSLock non ricorsivo).
            scheduleEviction(force: false)
        }
    }

    /// Byte stimati attualmente occupati su disco (diagnostica e test).
    /// La verità resta la scansione reale fatta dall'eviction.
    var estimatedDiskUsageBytes: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return totalDiskBytes
    }

    /// Numero di batch di rimozione non vuoti eseguiti dall'eviction
    /// (diagnostica e test: verifica che le vittime siano raggruppate).
    var performedRemovalBatches: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return removalBatchCount
    }

    /// Vero quando l'ultimo riallineamento esatto è stato rimandato e il
    /// contatore stimato non è affidabile (diagnostica e test).
    var needsDiskReconcile: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return needsReconcile
    }
    
    public init(customCacheDirectory: URL? = nil) {
        if let custom = customCacheDirectory {
            self.cacheDirectoryURL = custom
        } else {
            let baseCaches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.cacheDirectoryURL = baseCaches.appendingPathComponent("Lettore/audio_cache", isDirectory: true)
        }
        
        // Configura limiti memoria L1 (32 elementi massimi o ~30MB)
        memoryCache.countLimit = 32
        memoryCache.totalCostLimit = 30 * 1024 * 1024
        
        // La directory viene creata qui; le scritture non la ricontrollano nel
        // percorso felice, ma la ricreano se una write fallisce perché è
        // sparita a runtime (vedi `storeAudio`).
        createCacheDirectoryIfNeeded()

        diskQueue.setSpecific(key: diskQueueKey, value: 1)

        // Unica scansione completa dei byte su disco. Gira sulla
        // maintenanceQueue, NON sulla diskQueue: accodata davanti alle prime
        // letture L2 le farebbe attendere l'intero listing (millisecondi con
        // migliaia di file). Le mutazioni concorrenti sono rilevate dal
        // contatore (vedi `initializeDiskUsage`), quindi la scansione non ha
        // bisogno di essere serializzata con le letture.
        maintenanceQueue.async { [weak self] in
            self?.initializeDiskUsage()
        }
    }
    
    private func createCacheDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: cacheDirectoryURL.path) {
            try? fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Generazione Chiave Hash Determinismo (SHA-256)
    
    /// Calcola la chiave hash SHA-256 univoca per la combinazione di testo, voce, velocità e step.
    public func cacheKey(for text: String, voiceId: String, speed: Float, steps: Int) -> String {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let roundedSpeed = String(format: "%.2f", speed)
        let rawKey = "\(normalizedText)|\(voiceId.uppercased())|\(roundedSpeed)|\(steps)"
        
        let inputData = Data(rawKey.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Recupero Cache L1 / L2
    
    /// Cerca l'audio per la chiave data. Ritorna il Data e la sorgente (RAM o Disco), o nil se cache miss.
    ///
    /// La chiamata resta sincrona (blocca il chiamante fino al risultato), ma
    /// l'I/O su disco viene eseguito sulla `diskQueue`: così una `fileExists` +
    /// lettura non può cadere in mezzo a un'eviction concorrente e produrre un
    /// cache miss spurio. Per il percorso di riproduzione usare `getAudioAsync`,
    /// che non blocca il MainActor.
    public func getAudio(for key: String) -> (data: Data, source: AudioCacheSource)? {
        let nsKey = key as NSString
        
        // 1. Check L1 RAM
        if let cachedData = validMemoryData(for: nsKey) {
            return (cachedData, .memory)
        }
        
        // 2. Check L2 Disk
        let fileURL = cacheDirectoryURL.appendingPathComponent("\(key).wav")
        if let data = readFromDiskSerialized(at: fileURL) {
            promote(data, for: nsKey, at: fileURL)
            return (data, .disk)
        }
        
        return nil
    }

    /// Variante asincrona usata dal playback: L1 resta immediata, l'I/O su
    /// disco viene eseguito sulla coda dedicata e non blocca il MainActor.
    func getAudioAsync(for key: String) async -> (data: Data, source: AudioCacheSource)? {
        let nsKey = key as NSString

        if let cachedData = validMemoryData(for: nsKey) {
            return (cachedData, .memory)
        }

        let fileURL = cacheDirectoryURL.appendingPathComponent("\(key).wav")
        let data: Data? = await withCheckedContinuation { continuation in
            diskQueue.async { [weak self] in
                continuation.resume(returning: self?.readFromDisk(at: fileURL))
            }
        }

        guard let data else { return nil }
        promote(data, for: nsKey, at: fileURL)
        return (data, .disk)
    }

    /// Un dato non WAV non deve mai uscire dalla cache: viene rimosso da L1
    /// e il chiamante lo tratta come cache miss, così può risintetizzare.
    private func validMemoryData(for key: NSString) -> Data? {
        guard let cachedData = memoryCache.object(forKey: key) else { return nil }
        let data = cachedData as Data
        guard WAVValidator.isValid(data) else {
            memoryCache.removeObject(forKey: key)
            return nil
        }
        return data
    }

    /// Legge il file di cache. Va invocata SOLO sulla `diskQueue`: le rimozioni
    /// (eviction compresa) usano la stessa coda seriale, quindi un `removeItem`
    /// non può cadere in mezzo a `fileExists` + `Data(contentsOf:)`.
    private func readFromDisk(at fileURL: URL) -> Data? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL),
              WAVValidator.isValid(data) else {
            // Un file troncato o corrotto non è recuperabile: eliminarlo evita
            // di riprovare lo stesso errore a ogni replay. La rimozione passa
            // dal lock condiviso, così il contatore scala la size reale anche
            // se un'eviction ha già toccato lo stesso file.
            removeDiskFile(at: fileURL)
            return nil
        }
        return data
    }

    /// Variante per chi non gira sulla `diskQueue` (il percorso sincrono
    /// `getAudio`): sposta l'I/O sulla coda seriale di letture/scritture.
    /// La guardia su `getSpecific` evita il deadlock se il chiamante è già
    /// sulla coda.
    private func readFromDiskSerialized(at fileURL: URL) -> Data? {
        if DispatchQueue.getSpecific(key: diskQueueKey) != nil {
            return readFromDisk(at: fileURL)
        }
        return diskQueue.sync { readFromDisk(at: fileURL) }
    }

    private func promote(_ data: Data, for key: NSString, at fileURL: URL) {
        memoryCache.setObject(data as NSData, forKey: key, cost: data.count)
        touchFileIfStale(key: key as String, at: fileURL)
    }
    
    // MARK: - Salvataggio Cache
    
    /// Memorizza l'audio sia in L1 RAM che asincronamente in L2 su disco.
    /// I payload non WAV vengono ignorati: la cache deve contenere solo audio
    /// riproducibile.
    public func storeAudio(_ data: Data, for key: String) {
        guard WAVValidator.isValid(data) else {
            print("[AudioCacheManager] Ignoro un payload non WAV per \(key)")
            return
        }

        let nsKey = key as NSString
        // Salva subito in L1 RAM
        memoryCache.setObject(data as NSData, forKey: nsKey, cost: data.count)
        
        // Scrittura asincrona su disco
        diskQueue.async { [weak self] in
            guard let self = self else { return }
            let fileURL = self.cacheDirectoryURL.appendingPathComponent("\(key).wav")
            // Size letta sotto lock (write e remove sono serializzate dalla
            // diskQueue, quindi nessun altro tocca il file nel frattempo), ma
            // la `data.write` resta fuori: su 96 KB sono ~0,29 ms in cui il
            // lock bloccherebbe accessor e bookkeeping delle altre operazioni.
            // `inFlightWrites` impedisce a una scansione concorrente di
            // riallineare il totale prima che il delta sia applicato.
            self.stateLock.lock()
            let previousSize = Self.fileSize(at: fileURL) ?? 0
            self.inFlightWrites += 1
            self.stateLock.unlock()

            var didWrite = self.writeCacheFile(data, to: fileURL)
            if !didWrite {
                // La directory può sparire a runtime (pulizia del sistema,
                // `clearAll` concorrente, cancellazione manuale). La ricreiamo
                // e ritentiamo UNA sola volta: nel percorso felice nessun
                // controllo sulla directory, quindi nessun `stat` aggiuntivo.
                self.createCacheDirectoryIfNeeded()
                didWrite = self.writeCacheFile(data, to: fileURL)
            }

            self.stateLock.lock()
            self.inFlightWrites -= 1
            if didWrite {
                let updated = self.totalDiskBytes + data.count - previousSize
                if updated < 0 {
                    // Sottrazione negativa: il contatore era più basso della
                    // size reale del file. Il clamp a zero nasconderebbe la
                    // sottostima, quindi va riconciliato con una scansione.
                    self.needsReconcile = true
                }
                self.totalDiskBytes = max(0, updated)
                self.diskMutationCount += 1
                // La scrittura ha già aggiornato il mtime: il touch registrato non serve più.
                self.lastTouchDates.removeValue(forKey: key)
            }
            // Una write fallita non deve lasciare acceso `needsReconcile`:
            // nessun altro completamento riproverebbe la riconciliazione.
            let mustReconcile = self.needsReconcile
            self.stateLock.unlock()

            // L'eviction parte solo se il budget è superato (o se la prima
            // scansione non è ancora riuscita), su una coda separata: niente
            // scansione della directory a ogni chunk. Lo stesso vale per una
            // riconciliazione rimasta in sospeso.
            if didWrite || mustReconcile {
                self.scheduleEviction(force: false)
            }
        }
    }

    /// Scrive il file su disco. Non tocca lo stato condiviso: `previousSize` e
    /// l'aggiornamento del totale restano responsabilità del chiamante, che li
    /// esegue sotto `stateLock` prima e dopo la syscall.
    private func writeCacheFile(_ data: Data, to fileURL: URL) -> Bool {
        do {
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            print("[AudioCacheManager] Errore scrittura cache disco per \(fileURL.lastPathComponent): \(error)")
            return false
        }
    }

    /// Rimuove una singola entry da L1 e L2. Usata quando la riproduzione
    /// fallisce: il chunk torna risintetizzabile invece di restare avvelenato.
    public func removeAudio(for key: String) {
        memoryCache.removeObject(forKey: key as NSString)
        diskQueue.async { [weak self] in
            guard let self = self else { return }
            let fileURL = self.cacheDirectoryURL.appendingPathComponent("\(key).wav")
            if self.removeDiskFile(at: fileURL) {
                return
            }
            self.forgetTouch(for: key)
        }
    }
    
    // MARK: - Manutenzione & LRU Eviction

    /// Inizializza il contatore dei byte occupati su disco con una sola
    /// scansione, eseguita sulla `maintenanceQueue` (mai davanti alle letture
    /// L2). Non essendo serializzata con write/remove, un elenco letto mentre
    /// una mutazione è in corso può essere incoerente: in quel caso si tiene il
    /// massimo tra stima incrementale e listing (conservativo: meglio
    /// sovrastimare e fare un passaggio in più che sottostimare e restare sopra
    /// budget) e si accende `needsReconcile`, così la manutenzione ri-scandisce
    /// anche se il contatore è sotto budget. Senza mutazioni concorrenti il
    /// totale viene riallineato esatto.
    ///
    /// Al termine, se la cache è sopra budget si schedula l'eviction: una cache
    /// preesistente troppo grande non deve aspettare la prima sintesi.
    private func initializeDiskUsage() {
        stateLock.lock()
        let generation = diskMutationCount
        stateLock.unlock()

        guard let listing = scanDiskFiles() else { return }

        stateLock.lock()
        let hasInFlightWrite = inFlightWrites > 0
        let raced = diskMutationCount != generation
        if hasInFlightWrite {
            // La write sta per applicare il proprio delta: il listing può già
            // includere il suo file, quindi riallineare qui conterebbe due
            // volte. Si lascia il contatore com'è e si segna il riallineamento
            // come dovuto.
            needsReconcile = true
        } else if raced {
            totalDiskBytes = max(totalDiskBytes, listing.totalBytes)
            needsReconcile = true
        } else {
            totalDiskBytes = listing.totalBytes
            needsReconcile = false
        }
        didInitializeDiskUsage = true
        stateLock.unlock()

        // La riconciliazione dovuta (se la scansione ha incrociato mutazioni) e
        // la cache già sopra budget vengono schedulate da qui: `scheduleEviction`
        // guarda anche `needsReconcile`, quindi vale anche per un contatore
        // stimato sotto budget.
        scheduleEviction(force: false)
    }

    private struct DiskFileInfo {
        let url: URL
        let size: Int
        let modDate: Date
    }

    private struct DiskListing {
        let totalBytes: Int
        let files: [DiskFileInfo]
    }

    /// Unica scansione della directory: una sola `resourceValues` per file,
    /// niente doppio `stat` tra `contentsOfDirectory` e `attributesOfItem`.
    private func scanDiskFiles() -> DiskListing? {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: cacheDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return nil }

        var totalBytes = 0
        var files: [DiskFileInfo] = []
        files.reserveCapacity(urls.count)
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize else {
                continue
            }
            totalBytes += size
            files.append(DiskFileInfo(
                url: url,
                size: size,
                modDate: values.contentModificationDate ?? .distantPast
            ))
        }
        return DiskListing(totalBytes: totalBytes, files: files)
    }

    private static func fileSize(at url: URL) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.intValue
    }

    /// Rimuove un file della cache sotto `stateLock` scalando la size reale
    /// letta al momento della rimozione. È questa atomicità (insieme alla
    /// lettura della size precedente e all'update del totale di `storeAudio`,
    /// eseguiti sotto lo stesso lock) a impedire che un overwrite concorrente
    /// sulla stessa chiave sottostimi il totale: write e remove sono comunque
    /// già serializzate dalla `diskQueue`.
    ///
    /// Va eseguita SOLO sulla `diskQueue`: le letture (`readFromDisk`) usano la
    /// stessa coda seriale, così un `removeItem` non può cadere in mezzo a
    /// `fileExists` + `Data(contentsOf:)` trasformando una lettura valida in un
    /// cache miss spurio. Le rimozioni multiple passano da `removeDiskFiles`.
    @discardableResult
    private func removeDiskFile(at url: URL) -> Bool {
        assert(
            DispatchQueue.getSpecific(key: diskQueueKey) != nil,
            "removeDiskFile va eseguita sulla diskQueue: usare removeDiskFiles"
        )
        let key = url.deletingPathExtension().lastPathComponent
        var mustReconcile = false
        stateLock.lock()
        guard let size = Self.fileSize(at: url) else {
            // File già assente: niente da scalare, ma il touch è inutile.
            lastTouchDates.removeValue(forKey: key)
            stateLock.unlock()
            return false
        }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            stateLock.unlock()
            return false
        }
        let updated = totalDiskBytes - size
        if updated < 0 {
            // Il contatore era più basso del file rimosso: il clamp a zero
            // nasconderebbe la sottostima, quindi va riallineato.
            needsReconcile = true
            mustReconcile = true
        }
        totalDiskBytes = max(0, updated)
        diskMutationCount += 1
        lastTouchDates.removeValue(forKey: key)
        stateLock.unlock()
        if mustReconcile {
            scheduleEviction(force: false)
        }
        return true
    }

    private func forgetTouch(for key: String) {
        stateLock.lock()
        lastTouchDates.removeValue(forKey: key)
        stateLock.unlock()
    }

    /// Rimuove un gruppo di file con UN solo `diskQueue.sync`: l'eviction non
    /// paga più un round-trip (e un `stat`) per ogni vittima. Restituisce la
    /// size realmente sottratta al contatore, per URL rimosso.
    ///
    /// Chi gira fuori dalla coda serializza qui; chi ci gira già (o in futuro
    /// chiamasse da un blocco della diskQueue) evita il `sync`, che
    /// andrebbe in deadlock.
    private func removeDiskFiles(_ urls: [URL]) -> [URL: Int] {
        guard !urls.isEmpty else { return [:] }
        if DispatchQueue.getSpecific(key: diskQueueKey) != nil {
            return removeDiskFilesOnQueue(urls)
        }
        return diskQueue.sync { removeDiskFilesOnQueue(urls) }
    }

    /// Corpo del batch. Gira SOLO sulla `diskQueue`: write, remove e `clearAll`
    /// usano la stessa coda seriale, quindi `stat` e `removeItem` non possono
    /// incrociare un overwrite della stessa chiave. Il contatore viene
    /// aggiornato una volta sola, sotto `stateLock`, dopo le rimozioni.
    private func removeDiskFilesOnQueue(_ urls: [URL]) -> [URL: Int] {
        assert(
            DispatchQueue.getSpecific(key: diskQueueKey) != nil,
            "removeDiskFilesOnQueue va eseguita sulla diskQueue"
        )
        var removed: [URL: Int] = [:]
        removed.reserveCapacity(urls.count)
        var keysToForget: [String] = []
        keysToForget.reserveCapacity(urls.count)
        for url in urls {
            keysToForget.append(url.deletingPathExtension().lastPathComponent)
            guard let size = Self.fileSize(at: url),
                  (try? fileManager.removeItem(at: url)) != nil else {
                continue
            }
            removed[url] = size
        }

        stateLock.lock()
        var mustReconcile = false
        if !removed.isEmpty {
            let updated = totalDiskBytes - removed.values.reduce(0, +)
            if updated < 0 {
                // Clamp a zero su una sottrazione negativa: il contatore non è
                // affidabile e va riconciliato, non mascherato.
                needsReconcile = true
                mustReconcile = true
            }
            totalDiskBytes = max(0, updated)
            diskMutationCount += removed.count
            removalBatchCount += 1
        }
        for key in keysToForget {
            lastTouchDates.removeValue(forKey: key)
        }
        stateLock.unlock()
        if mustReconcile {
            // Siamo dentro il passaggio di manutenzione: la richiesta fa
            // ripartire il drain con una scansione di riallineamento.
            scheduleEviction(force: false)
        }
        return removed
    }

    /// Aggiorna il mtime solo se l'ultimo touch della chiave è più vecchio di
    /// un'ora: evita un setAttributes a ogni hit L2 mantenendo la politica LRU.
    private func touchFileIfStale(key: String, at url: URL) {
        let now = Date()
        stateLock.lock()
        if let last = lastTouchDates[key], now.timeIntervalSince(last) < touchInterval {
            stateLock.unlock()
            return
        }
        if lastTouchDates.count > 1024 {
            lastTouchDates = lastTouchDates.filter { now.timeIntervalSince($0.value) < touchInterval }
        }
        lastTouchDates[key] = now
        stateLock.unlock()

        // Fuori dalla diskQueue: il touch non deve mettersi davanti alla
        // prossima lettura L2 (era il costo che la prima lettura di ogni
        // chiave pagava).
        touchQueue.async {
            try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
        }
    }

    /// Programma un passaggio di manutenzione. `force` (API pubblica) impone
    /// una scansione anche se il contatore stimato è sotto budget.
    /// `needsReconcile` impone lo stesso quando un riallineamento esatto è
    /// stato rimandato: la stima non è affidabile e va riportata al dato reale
    /// anche se dice che siamo sotto budget. Nel percorso felice il flag è
    /// spento, quindi non si introduce nessuna scansione in più.
    ///
    /// Fuori da quei casi non si scandisce mai la directory "per scrupolo": il
    /// costo di una scansione cresce linearmente col numero di file e il
    /// contatore incrementale è tenuto esatto da write/remove sotto `stateLock`.
    /// L'anti-sottostima resta garantita perché ogni eviction riparte SEMPRE
    /// dalla scansione reale; se la prima scansione non è ancora riuscita, una
    /// mutazione la ritenta. Una richiesta che arriva mentre un passaggio è già
    /// in volo non viene scartata: resta pendente e il ciclo di drain la
    /// consuma al termine del passaggio corrente.
    private func scheduleEviction(force: Bool) {
        stateLock.lock()
        let needsInitialScan = !didInitializeDiskUsage
        let overBudget = totalDiskBytes > _maxDiskCacheSizeBytes
        if force || needsReconcile || needsInitialScan || overBudget {
            pendingEviction = true
            if force {
                pendingForcedEviction = true
            }
        }
        let shouldSchedule = pendingEviction && !isEvictionScheduled
        if shouldSchedule {
            isEvictionScheduled = true
        }
        stateLock.unlock()
        guard shouldSchedule else { return }

        maintenanceQueue.async { [weak self] in
            self?.drainEvictionRequests()
        }
    }

    /// Rimuove i file più vecchi (LRU) se la dimensione totale della cache su
    /// disco supera `maxDiskCacheSizeBytes`.
    ///
    /// L'operazione è **asincrona**: questo metodo si limita ad accodare la
    /// richiesta, che viene consumata sulla `maintenanceQueue`. Il ritorno non
    /// significa che la cache sia già entro budget; chi deve misurare lo stato
    /// finale deve attendere che la directory smetta di cambiare (o usare
    /// `estimatedDiskUsageBytes` come stima, non come garanzia).
    public func evictDiskCacheIfNeeded() {
        scheduleEviction(force: true)
    }

    /// Consuma tutte le richieste pendenti. Il flag di schedulazione viene
    /// rilasciato sotto lock solo quando non c'è più lavoro: una richiesta
    /// arrivata nel frattempo o ha già trovato `isEvictionScheduled` e quindi
    /// `pendingEviction`, oppure avvia un nuovo job dopo il rilascio.
    ///
    /// Se un passaggio ha rimandato il riallineamento esatto la riconciliazione
    /// non riparte a raffica: un retry immediato, sotto scritture continue,
    /// riscandirebbe la directory a ogni generazione cambiata. Si riprogramma
    /// dopo un breve intervallo, coalescendosi con le richieste arrivate nel
    /// frattempo.
    private func drainEvictionRequests() {
        while true {
            stateLock.lock()
            let forced = pendingForcedEviction
            pendingEviction = false
            pendingForcedEviction = false
            stateLock.unlock()

            let requiresReconcileRetry = performEvictionPass(force: forced)

            stateLock.lock()
            if requiresReconcileRetry && needsReconcile {
                // `isEvictionScheduled` resta true durante l'attesa: le write
                // che arrivano nel frattempo accodano la richiesta ma non
                // avviano una scansione ciascuna. Il job ritardato riprende il
                // drain quando la raffica si è calmata.
                stateLock.unlock()
                maintenanceQueue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.resumeScheduledEviction()
                }
                return
            }
            if !pendingEviction {
                isEvictionScheduled = false
                stateLock.unlock()
                return
            }
            stateLock.unlock()
        }
    }

    /// Riprende il drain dopo un retry posticipato della riconciliazione. Il
    /// flag di schedulazione è rimasto acceso apposta: qui si rilascia e si
    /// richiede un nuovo passaggio, che `scheduleEviction` coalesce con le
    /// richieste arrivate nel frattempo.
    private func resumeScheduledEviction() {
        stateLock.lock()
        guard isEvictionScheduled else {
            stateLock.unlock()
            return
        }
        isEvictionScheduled = false
        stateLock.unlock()
        scheduleEviction(force: false)
    }

    /// Un passaggio: scansione reale -> riallineamento del contatore -> eviction
    /// LRU -> ricontrollo. Ripete finché il totale resta sopra budget e ci sono
    /// file da rimuovere (es. rimozioni fallite o entry ricreate nel frattempo).
    ///
    /// Le vittime di un giro vengono rimosse insieme in un unico batch sulla
    /// `diskQueue`; se il giro ha rimosso qualcosa la scansione successiva è
    /// già la conferma richiesta da una richiesta esplicita, quindi non si paga
    /// un listing a vuoto.
    ///
    /// Quando si supera il budget non ci si ferma al 100%: si evacua fino al
    /// "low water" (~90%) per amortizzare la scansione nel regime a cache
    /// piena, altrimenti ogni singola scrittura riattiverebbe l'eviction.
    /// Un pavimento al 60% del budget evita di svuotare cache piccole fatte di
    /// pochi file grandi: i file che sfonderebbero il pavimento vengono
    /// saltati, non usati come motivo per fermare l'eviction, così un file
    /// grande seguito da file più piccoli non lascia la cache sopra budget.
    /// Si resta sopra budget solo quando nessuna vittima residua è rimovibile.
    ///
    /// Restituisce `true` quando il riallineamento esatto è stato rimandato da
    /// una mutazione già conclusa: il drain riprova dopo un breve intervallo.
    /// Con una write ancora in volo il retry è garantito dal completamento della
    /// write (che richiama `scheduleEviction`).
    private func performEvictionPass(force: Bool) -> Bool {
        let budget = maxDiskCacheSizeBytes
        let lowWater = Int(Double(budget) * Self.evictionLowWaterRatio)
        let floorBytes = Int(Double(budget) * Self.evictionFloorRatio)
        var didForcedConfirmationScan = false
        var didRemoveAnything = false
        var needsRetry = false

        for _ in 0..<4 {
            stateLock.lock()
            let generation = diskMutationCount
            stateLock.unlock()

            guard let listing = scanDiskFiles() else { return needsRetry }

            // Il contatore incrementale viene SEMPRE riallineato al dato reale
            // quando non ci sono mutazioni concorrenti né write in volo: un
            // eventuale errore precedente non può sopravvivere alla sessione.
            // Una write in corso ha già scritto il file ma non ancora applicato
            // il delta: riallineare adesso conterebbe due volte. In entrambi i
            // casi di salto il flag `needsReconcile` resta acceso, così il
            // riallineamento riparte anche se il contatore sembra sotto budget.
            stateLock.lock()
            if diskMutationCount == generation && inFlightWrites == 0 {
                totalDiskBytes = listing.totalBytes
                didInitializeDiskUsage = true
                needsReconcile = false
                needsRetry = false
            } else {
                needsReconcile = true
                if inFlightWrites == 0 {
                    // La mutazione ha già consumato il proprio
                    // `scheduleEviction` prima che il flag fosse acceso:
                    // senza un retry esplicito il riallineamento non
                    // ripartirebbe più.
                    needsRetry = true
                }
            }
            stateLock.unlock()

            guard listing.totalBytes > budget else {
                // Una richiesta esplicita fa una seconda scansione di conferma,
                // ma solo se il passaggio non ha già rimosso nulla: una
                // rimozione appena fatta è già la prova che lo stato era sopra
                // budget, e l'elenco corrente è la conferma.
                if force && !didForcedConfirmationScan && !didRemoveAnything {
                    didForcedConfirmationScan = true
                    continue
                }
                return needsRetry
            }

            // Vittime scelte sullo stesso listing (una sola scansione) e
            // rimosse insieme: un solo `diskQueue.sync` per l'intero batch.
            var projected = listing.totalBytes
            var victims: [URL] = []
            var skippedForFloor = false
            for item in listing.files.sorted(by: { $0.modDate < $1.modDate }) {
                if projected <= lowWater { break }
                if projected - item.size < floorBytes {
                    // File troppo grande per essere la prossima vittima senza
                    // sfondare il pavimento: non è un motivo per fermare
                    // l'eviction, perché i file successivi (più piccoli)
                    // possono comunque riportare la cache entro budget.
                    skippedForFloor = true
                    continue
                }
                victims.append(item.url)
                projected -= item.size
            }

            let removed = removeDiskFiles(victims)
            if !removed.isEmpty {
                didRemoveAnything = true
                // Stima riallineata sulle size realmente rimosse: un file
                // riscritto nel frattempo non falsa il conteggio.
                projected = listing.totalBytes - removed.values.reduce(0, +)
            }

            // Un altro giro ha senso solo se siamo ancora sopra budget e
            // qualcosa è stato rimosso; se ci ha fermati il pavimento, o se
            // tutte le vittime previste sono state rimosse e le rimanenti
            // sfonderebbero il floor, un altro passaggio ripeterebbe la stessa
            // scansione senza progresso: si esce qui. Resta il caso
            // documentato in cui nessun file è rimovibile (tutti oltre il
            // margine del pavimento) e la cache resta sopra budget.
            if removed.isEmpty || projected <= budget { return needsRetry }
            if skippedForFloor && removed.count == victims.count { return needsRetry }
        }
        return needsRetry
    }
    
    /// Svuota sia la cache in memoria che la cache su disco.
    public func clearAll() {
        memoryCache.removeAllObjects()
        diskQueue.async { [weak self] in
            guard let self = self else { return }
            try? self.fileManager.removeItem(at: self.cacheDirectoryURL)
            self.createCacheDirectoryIfNeeded()
            self.stateLock.lock()
            self.totalDiskBytes = 0
            self.diskMutationCount += 1
            self.pendingEviction = false
            self.pendingForcedEviction = false
            // Directory appena svuotata: zero è un totale esatto, non una
            // stima da riconciliare.
            self.needsReconcile = false
            self.lastTouchDates.removeAll()
            self.stateLock.unlock()
        }
    }
}
