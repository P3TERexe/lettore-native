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
    public func getAudio(for key: String) -> (data: Data, source: AudioCacheSource)? {
        let nsKey = key as NSString
        
        // 1. Check L1 RAM
        if let cachedData = memoryCache.object(forKey: nsKey) {
            return (cachedData as Data, .memory)
        }
        
        // 2. Check L2 Disk
        let fileURL = cacheDirectoryURL.appendingPathComponent("\(key).wav")
        if fileManager.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL) {
            // Promuovi in L1 RAM per le letture successive
            memoryCache.setObject(data as NSData, forKey: nsKey, cost: data.count)
            // Aggiorna la data di modifica per la politica LRU
            touchFile(at: fileURL)
            return (data, .disk)
        }
        
        return nil
    }
    
    // MARK: - Salvataggio Cache
    
    /// Memorizza l'audio sia in L1 RAM che asincronamente in L2 su disco.
    public func storeAudio(_ data: Data, for key: String) {
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
