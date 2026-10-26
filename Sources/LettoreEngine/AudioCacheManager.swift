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
    
    /// Dimensione massima della cache su disco in bytes (default: 200 MB)
    public var maxDiskCacheSizeBytes: Int = 200 * 1024 * 1024
    
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
        
        createCacheDirectoryIfNeeded()
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
    /// La lettura del disco avviene sul thread chiamante: per il percorso di
    /// riproduzione usare `getAudioAsync`, che sposta l'I/O fuori dal MainActor.
    public func getAudio(for key: String) -> (data: Data, source: AudioCacheSource)? {
        let nsKey = key as NSString
        
        // 1. Check L1 RAM
        if let cachedData = validMemoryData(for: nsKey) {
            return (cachedData, .memory)
        }
        
        // 2. Check L2 Disk
        let fileURL = cacheDirectoryURL.appendingPathComponent("\(key).wav")
        if let data = Self.readFromDisk(at: fileURL) {
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
            diskQueue.async {
                continuation.resume(returning: Self.readFromDisk(at: fileURL))
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

    private static func readFromDisk(at fileURL: URL) -> Data? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL),
              WAVValidator.isValid(data) else {
            // Un file troncato o corrotto non è recuperabile: eliminarlo evita
            // di riprovare lo stesso errore a ogni replay.
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
        return data
    }

    private func promote(_ data: Data, for key: NSString, at fileURL: URL) {
        memoryCache.setObject(data as NSData, forKey: key, cost: data.count)
        touchFile(at: fileURL)
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
            do {
                self.createCacheDirectoryIfNeeded()
                try data.write(to: fileURL, options: .atomic)
                self.evictDiskCacheIfNeeded()
            } catch {
                print("[AudioCacheManager] Errore scrittura cache disco per \(key): \(error)")
            }
        }
    }

    /// Rimuove una singola entry da L1 e L2. Usata quando la riproduzione
    /// fallisce: il chunk torna risintetizzabile invece di restare avvelenato.
    public func removeAudio(for key: String) {
        memoryCache.removeObject(forKey: key as NSString)
        let fileURL = cacheDirectoryURL.appendingPathComponent("\(key).wav")
        diskQueue.async {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    
    // MARK: - Manutenzione & LRU Eviction
    
    private func touchFile(at url: URL) {
        diskQueue.async {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        }
    }
    
    /// Rimuove i file più vecchi se la dimensione totale della cache su disco supera maxDiskCacheSizeBytes.
    public func evictDiskCacheIfNeeded() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }
        
        var totalSize = 0
        var fileInfos: [(url: URL, size: Int, modDate: Date)] = []
        
        for file in files {
            guard let resourceValues = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = resourceValues.fileSize,
                  let modDate = resourceValues.contentModificationDate else {
                continue
            }
            totalSize += size
            fileInfos.append((url: file, size: size, modDate: modDate))
        }
        
        guard totalSize > maxDiskCacheSizeBytes else { return }
        
        // Ordina dal meno recente al più recente
        fileInfos.sort { $0.modDate < $1.modDate }
        
        for item in fileInfos {
            try? fileManager.removeItem(at: item.url)
            totalSize -= item.size
            if totalSize <= maxDiskCacheSizeBytes {
                break
            }
        }
    }
    
    /// Svuota sia la cache in memoria che la cache su disco.
    public func clearAll() {
        memoryCache.removeAllObjects()
        diskQueue.async { [weak self] in
            guard let self = self else { return }
            try? self.fileManager.removeItem(at: self.cacheDirectoryURL)
            self.createCacheDirectoryIfNeeded()
        }
    }
}
