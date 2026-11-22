import Foundation

/// Intervallo espresso in unità UTF-16 sulla stringa sorgente.
///
/// Gli offset UTF-16 sono quelli usati dalle Accessibility API (`NSRange`,
/// `AXValue`), quindi la mappa evita di convertire in `Character` e di perdere
/// posizioni su emoji o caratteri fuori dal BMP.
public struct SourceTextRange: Hashable, Codable, Sendable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    public init(_ range: NSRange) {
        self.location = range.location
        self.length = range.length
    }

    public var end: Int { location + length }

    public var isEmpty: Bool { length == 0 }

    public var nsRange: NSRange { NSRange(location: location, length: length) }
}

/// Testo filtrato con la mappa verso gli offset UTF-16 del testo originale.
///
/// Il filtro rimuove righe e caratteri, quindi il testo filtrato non è una
/// sottostringa contigua della sorgente. La mappa è una sequenza di segmenti
/// ordinati: ogni segmento copre un intervallo di output e il corrispondente
/// intervallo sorgente. Le parti rimosse semplicemente non compaiono e i salti
/// restano visibili come discontinuità tra un segmento e il successivo.
public struct FilteredText: Hashable, Sendable {

    public let text: String
    /// Lunghezza UTF-16 del testo filtrato, memorizzata alla costruzione.
    ///
    /// `text.utf16.count` è O(n): ricalcolarla a ogni mappatura renderebbe la
    /// conversione dei chunk quadratica sul documento.
    public let utf16Length: Int
    /// Lunghezza UTF-16 del testo originale da cui è stata costruita la mappa.
    public let sourceLength: Int

    internal let segments: [Segment]

    public init(text: String) {
        let length = text.utf16.count
        self.text = text
        self.utf16Length = length
        self.sourceLength = length
        self.segments = length == 0
            ? []
            : [Segment(outputStart: 0, outputEnd: length, sourceStart: 0, sourceEnd: length)]
    }

    /// Mappa identità: utile per `NoiseFilterMode.off` e per i test.
    public static func identity(_ text: String) -> FilteredText {
        FilteredText(text: text)
    }

    internal init(text: String, sourceLength: Int, segments: [Segment]) {
        self.text = text
        self.utf16Length = text.utf16.count
        self.sourceLength = sourceLength
        self.segments = segments
    }

    /// Offset UTF-16 sorgente corrispondente all'inizio della posizione
    /// filtrata. Per un offset in corrispondenza di testo rimosso viene
    /// restituito l'inizio del testo conservato successivo.
    public func sourceOffset(atUTF16Offset offset: Int) -> Int? {
        mapStart(offset)
    }

    /// Range sorgente di lunghezza zero per il punto di taglio filtrato.
    ///
    /// È il metodo da usare per ottenere la base del remainder dopo uno split
    /// del testo filtrato (prefisso da 8.000 unità e resto del documento).
    public func sourceRange(atUTF16Offset offset: Int) -> SourceTextRange? {
        guard let start = mapStart(offset) else { return nil }
        return SourceTextRange(location: start, length: 0)
    }

    /// Converte un range UTF-16 relativo al testo filtrato nel range UTF-16
    /// corrispondente del testo originale.
    ///
    /// Restituisce `nil` se il range non è valido o esce dal testo filtrato:
    /// un range sbagliato è peggio di nessun range.
    public func sourceRange(forRelativeRange range: SourceTextRange) -> SourceTextRange? {
        guard range.location >= 0,
              range.length >= 0,
              range.end <= utf16Length else {
            return nil
        }
        guard let start = mapStart(range.location) else { return nil }
        guard range.length > 0 else {
            return SourceTextRange(location: start, length: 0)
        }
        let end = mapEnd(range.end) ?? start
        return SourceTextRange(location: start, length: max(0, end - start))
    }

    /// Rimuove gli intervalli UTF-16 indicati dal testo filtrato, mantenendo
    /// coerente la mappa verso la sorgente.
    internal func deleting(utf16Ranges ranges: [Range<Int>]) -> FilteredText {
        let length = utf16Length
        let clamped = ranges
            .map { max(0, $0.lowerBound)..<min(length, $0.upperBound) }
            .filter { !$0.isEmpty }
            .sorted { $0.lowerBound < $1.lowerBound }

        guard !clamped.isEmpty else { return self }

        var merged: [Range<Int>] = []
        for range in clamped {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }

        var builder = FilteredTextBuilder(sourceLength: sourceLength)
        var cursor = 0
        for range in merged {
            if cursor < range.lowerBound {
                builder.append(self, range: cursor..<range.lowerBound)
            }
            cursor = max(cursor, range.upperBound)
        }
        if cursor < length {
            builder.append(self, range: cursor..<length)
        }
        return builder.build()
    }

    /// Sostituisce i caratteri mantenendo la stessa lunghezza UTF-16 e quindi
    /// la stessa mappa (usato per normalizzare i soli `\r` in `\n`).
    internal func replacingCharactersPreservingMapping(_ newText: String) -> FilteredText {
        guard newText.utf16.count == utf16Length else {
            return FilteredText(text: newText)
        }
        return FilteredText(text: newText, sourceLength: sourceLength, segments: segments)
    }

    // MARK: - Mapping interno

    internal struct Segment: Hashable, Sendable {
        let outputStart: Int
        let outputEnd: Int
        let sourceStart: Int
        let sourceEnd: Int
    }

    internal func mapStart(_ offset: Int) -> Int? {
        guard offset >= 0, offset <= utf16Length else { return nil }
        if offset == utf16Length {
            return segments.last?.sourceEnd ?? 0
        }
        guard let index = firstSegmentIndex(endingAfter: offset) else {
            return segments.last?.sourceEnd ?? 0
        }
        let segment = segments[index]
        if offset <= segment.outputStart {
            return segment.sourceStart
        }
        return scale(offset - segment.outputStart, in: segment, roundUp: false)
    }

    internal func mapEnd(_ offset: Int) -> Int? {
        guard offset >= 0, offset <= utf16Length else { return nil }
        if offset == 0 {
            return segments.first?.sourceStart ?? 0
        }
        guard let index = firstSegmentIndex(endingAtOrAfter: offset) else {
            return segments.last?.sourceEnd ?? 0
        }
        let segment = segments[index]
        if offset <= segment.outputStart {
            return index > 0 ? segments[index - 1].sourceEnd : segment.sourceStart
        }
        if offset == segment.outputEnd {
            return segment.sourceEnd
        }
        return scale(offset - segment.outputStart, in: segment, roundUp: true)
    }

    /// Indice del primo segmento con `outputEnd > offset`.
    ///
    /// I segmenti sono ordinati e non sovrapposti (invariante del builder),
    /// quindi la ricerca binaria sostituisce la scansione lineare senza
    /// cambiare la semantica di `mapStart`.
    private func firstSegmentIndex(endingAfter offset: Int) -> Int? {
        var low = 0
        var high = segments.count
        while low < high {
            let mid = low + (high - low) / 2
            if segments[mid].outputEnd > offset {
                high = mid
            } else {
                low = mid + 1
            }
        }
        return low < segments.count ? low : nil
    }

    /// Indice del primo segmento con `outputEnd >= offset`.
    private func firstSegmentIndex(endingAtOrAfter offset: Int) -> Int? {
        var low = 0
        var high = segments.count
        while low < high {
            let mid = low + (high - low) / 2
            if segments[mid].outputEnd >= offset {
                high = mid
            } else {
                low = mid + 1
            }
        }
        return low < segments.count ? low : nil
    }

    private func scale(_ localOffset: Int, in segment: Segment, roundUp: Bool) -> Int {
        let outputLength = segment.outputEnd - segment.outputStart
        let sourceLength = segment.sourceEnd - segment.sourceStart
        guard outputLength > 0 else { return segment.sourceStart }
        guard sourceLength != outputLength else {
            return segment.sourceStart + localOffset
        }

        let numerator = localOffset * sourceLength
        let quotient = numerator / outputLength
        if roundUp && numerator % outputLength != 0 {
            return segment.sourceStart + quotient + 1
        }
        return segment.sourceStart + quotient
    }
}

/// Costruisce un `FilteredText` affiancando copie mappate di testo esistente e
/// separatori sintetici (newline tra righe e blocchi).
internal struct FilteredTextBuilder {
    let sourceLength: Int

    private var pieces: [String] = []
    private var segments: [FilteredText.Segment] = []
    private var length = 0

    init(sourceLength: Int) {
        self.sourceLength = sourceLength
    }

    var utf16Length: Int { length }
    var isEmpty: Bool { length == 0 }

    mutating func append(_ text: String, mappingTo sourceRange: SourceTextRange) {
        let textLength = text.utf16.count
        guard textLength > 0 else { return }

        pieces.append(text)
        segments.append(FilteredText.Segment(
            outputStart: length,
            outputEnd: length + textLength,
            sourceStart: sourceRange.location,
            sourceEnd: sourceRange.end
        ))
        length += textLength
    }

    mutating func append(_ source: FilteredText) {
        append(source, range: 0..<source.utf16Length)
    }

    mutating func append(_ source: FilteredText, range: Range<Int>) {
        let lower = max(0, range.lowerBound)
        let upper = min(source.utf16Length, range.upperBound)
        guard lower < upper else { return }

        let nsText = source.text as NSString
        pieces.append(nsText.substring(with: NSRange(location: lower, length: upper - lower)))

        for segment in source.segments {
            let start = max(segment.outputStart, lower)
            let end = min(segment.outputEnd, upper)
            guard start < end else { continue }

            let sourceStart = source.mapStart(start) ?? segment.sourceStart
            let sourceEnd = source.mapEnd(end) ?? segment.sourceEnd
            segments.append(FilteredText.Segment(
                outputStart: length + (start - lower),
                outputEnd: length + (end - lower),
                sourceStart: sourceStart,
                sourceEnd: sourceEnd
            ))
        }
        length += upper - lower
    }

    func build() -> FilteredText {
        FilteredText(
            text: pieces.joined(),
            sourceLength: sourceLength,
            segments: segments
        )
    }
}
