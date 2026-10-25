import Foundation

/// Coda di lettura con invarianti espliciti su indice e progresso.
///
/// È un value type: chi la possiede decide quando mutarla, ma non può lasciare
/// `currentIndex` fuori dai bounds o dimenticare il reindex dopo un append.
/// `AppState` la espone in sola lettura e delega i comandi di navigazione.
public struct ReadingQueue: Sendable, Equatable {

    public private(set) var chunks: [ReadingChunk]
    public private(set) var currentIndex: Int?

    public init(chunks: [ReadingChunk] = []) {
        self.chunks = chunks
        self.currentIndex = chunks.isEmpty ? nil : 0
    }

    public var current: ReadingChunk? {
        guard let currentIndex, chunks.indices.contains(currentIndex) else { return nil }
        return chunks[currentIndex]
    }

    public var count: Int { chunks.count }
    public var isEmpty: Bool { chunks.isEmpty }

    /// Progresso a granularità di chunk (0...1).
    ///
    /// Una coda non vuota senza chunk corrente è una coda terminata: il
    /// progresso è 1, non 0. La frazione dentro il chunk resta di pertinenza
    /// del playback e vive in `AppState.playbackProgress`.
    public var progress: Double {
        guard !chunks.isEmpty else { return 0 }
        guard let currentIndex else { return 1 }
        return min(1, max(0, Double(currentIndex) / Double(chunks.count)))
    }

    public func index(of id: UUID) -> Int? {
        chunks.firstIndex { $0.id == id }
    }

    public func chunk(at index: Int) -> ReadingChunk? {
        chunks.indices.contains(index) ? chunks[index] : nil
    }

    public mutating func replace(_ newChunks: [ReadingChunk]) {
        chunks = newChunks
        currentIndex = newChunks.isEmpty ? nil : 0
    }

    /// Accoda ricalcolando gli indici e preservando l'identità dei chunk.
    /// Se la coda era terminata, il primo chunk nuovo diventa il punto di
    /// ripresa senza richiedere un altro tap su Play.
    @discardableResult
    public mutating func append(_ newChunks: [ReadingChunk]) -> [ReadingChunk] {
        guard !newChunks.isEmpty else { return [] }

        let base = chunks.count
        let reindexed = newChunks.enumerated().map { offset, chunk in
            chunk.reindexed(base + offset)
        }
        chunks.append(contentsOf: reindexed)

        if currentIndex == nil {
            currentIndex = base
        }
        return reindexed
    }

    @discardableResult
    public mutating func advance() -> ReadingChunk? {
        guard let currentIndex, chunks.indices.contains(currentIndex) else { return nil }

        let next = currentIndex + 1
        guard chunks.indices.contains(next) else {
            self.currentIndex = nil
            return nil
        }

        self.currentIndex = next
        return chunks[next]
    }

    @discardableResult
    public mutating func rewind() -> ReadingChunk? {
        guard let currentIndex, chunks.indices.contains(currentIndex) else { return nil }

        let previous = max(0, currentIndex - 1)
        self.currentIndex = previous
        return chunks[previous]
    }

    @discardableResult
    public mutating func select(id: UUID) -> ReadingChunk? {
        guard let index = index(of: id) else { return nil }
        currentIndex = index
        return chunks[index]
    }

    @discardableResult
    public mutating func select(index: Int) -> ReadingChunk? {
        guard chunks.indices.contains(index) else { return nil }
        currentIndex = index
        return chunks[index]
    }
}
