import XCTest
@testable import LettoreCore

final class SourceRangeMappingTests: XCTestCase {

    private let filter = DocumentNoiseFilter()
    private let chunker = SentenceChunker()
    private let normalizer = TextNormalizer()

    // MARK: - Filtro e range

    func testFilterMappingRemovesPageNumbersAndRepeatedHeadersKeepingSourceOffsets() {
        let source = """
        Titolo corrente

        Pagina 1

        Prima frase del documento.

        Titolo corrente

        Seconda frase con dettagli.

        Titolo corrente

        Terza frase finale.
        """

        let filtered = filter.filterWithMapping(source, mode: .light)
        let expected = """
        Prima frase del documento.

        Seconda frase con dettagli.

        Terza frase finale.
        """

        XCTAssertEqual(filtered.text, expected, "Il testo filtrato deve restare identico al filtro storico")
        XCTAssertFalse(filtered.text.contains("Pagina 1"))
        XCTAssertFalse(filtered.text.contains("Titolo corrente"))

        let chunks = chunker.chunk(filteredText: filtered)
        XCTAssertEqual(chunks.count, 3)
        assertChunksMapToSource(chunks, source: source)
        assertMonotonic(chunks)

        // Ogni range deve puntare esattamente alla frase originale, non alla
        // posizione che avrebbe nel testo filtrato.
        for chunk in chunks {
            let expectedRange = (source as NSString).range(of: chunk.rawText)
            XCTAssertEqual(chunk.sourceRange, SourceTextRange(expectedRange))
        }
    }

    func testFilterMappingDehyphenationKeepsOriginalSpan() {
        let source = "Il testo contiene una parola spez-\niale da leggere."
        let filtered = filter.filterWithMapping(source, mode: .light)

        XCTAssertEqual(filtered.text, "Il testo contiene una parola speziale da leggere.")

        let chunks = chunker.chunk(filteredText: filtered)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertTrue(chunks[0].rawText.contains("speziale"))

        assertChunksMapToSource(chunks, source: source, dehyphenate: true)
        XCTAssertTrue(
            slice(chunks[0].sourceRange!, in: source).contains("spez-\niale"),
            "Il range deve coprire anche trattino e newline rimossi dal filtro"
        )
        XCTAssertEqual(chunks[0].sourceRange, SourceTextRange(location: 0, length: source.utf16.count))
    }

    func testFilterMappingSkipsNoiseBeforeEmojiWithoutBreakingUTF16Offsets() {
        let source = "Pagina 1\n\nFrase 😀 finale con accenti è."
        let filtered = filter.filterWithMapping(source, mode: .light)

        XCTAssertEqual(filtered.text, "Frase 😀 finale con accenti è.")

        let chunks = chunker.chunk(filteredText: filtered)
        XCTAssertEqual(chunks.count, 1)

        let expectedLocation = ("Pagina 1\n\nFrase" as NSString).range(of: "Frase").location
        XCTAssertEqual(expectedLocation, 10, "Due newline separano la sorgente dalla frase")
        XCTAssertEqual(chunks[0].sourceRange?.location, expectedLocation)
        XCTAssertEqual(slice(chunks[0].sourceRange!, in: source), chunks[0].rawText)
    }

    func testFilterMappingNormalizesNewlinesAndCollapsesBlankLines() {
        let source = "Prima.\r\n\r\n\r\nSeconda."
        let filtered = filter.filterWithMapping(source, mode: .light)

        XCTAssertEqual(filtered.text, "Prima.\n\nSeconda.")

        let chunks = chunker.chunk(filteredText: filtered)
        XCTAssertEqual(chunks.map(\.rawText), ["Prima.", "Seconda."])
        XCTAssertEqual(chunks[1].sourceRange?.location, 12, "Offset UTF-16 nella sorgente con CRLF")
        XCTAssertEqual(slice(chunks[1].sourceRange!, in: source), "Seconda.")
    }

    func testFilterMappingOffIsIdentity() {
        let source = "Prima 😀 frase.\r\nSeconda frase."
        let filtered = filter.filterWithMapping(source, mode: .off)

        XCTAssertEqual(filtered.text, filter.filter(source, mode: .off))
        XCTAssertEqual(filtered.text, source)
        XCTAssertEqual(filtered.utf16Length, source.utf16.count)

        let wholeRange = SourceTextRange(location: 0, length: source.utf16.count)
        XCTAssertEqual(filtered.sourceRange(forRelativeRange: wholeRange), wholeRange)

        let emojiOffset = ("Prima 😀" as NSString).range(of: "😀").location
        XCTAssertEqual(filtered.sourceRange(atUTF16Offset: emojiOffset)?.location, emojiOffset)
    }

    func testFilteredTextSourceRangeAtSplitPoint() {
        let source = "Pagina 1\n\nPrima frase.\n\nSeconda frase."
        let filtered = filter.filterWithMapping(source, mode: .light)

        let secondOffset = (filtered.text as NSString).range(of: "Seconda").location
        let expectedSourceOffset = (source as NSString).range(of: "Seconda").location

        XCTAssertEqual(filtered.sourceRange(atUTF16Offset: secondOffset)?.location, expectedSourceOffset)
        XCTAssertEqual(filtered.sourceOffset(atUTF16Offset: secondOffset), expectedSourceOffset)
        XCTAssertNil(filtered.sourceRange(atUTF16Offset: filtered.utf16Length + 1))
    }

    // MARK: - Equivalenza mappa (ricerca binaria vs scansione lineare)

    func testMappingMatchesNaiveScanOnASCII() {
        let text = FilteredText.identity("Prima frase. Seconda frase! Terza, con dettagli.")
        assertMappingMatchesNaive(text)
        assertRangeMappingMatchesNaive(text)
    }

    func testMappingMatchesNaiveScanWithEmojiAndSurrogates() {
        let text = FilteredText.identity("😀 È già 😀 tutto pronto. Seconda 😀 frase àccéntata. Fine 😀.")
        XCTAssertEqual(text.utf16Length, text.text.utf16.count)

        assertMappingMatchesNaive(text)
        assertRangeMappingMatchesNaive(text)
    }

    func testMappingMatchesNaiveScanOnFilteredTextWithHoles() {
        let source = """
        Titolo corrente

        Pagina 1

        Prima frase con una parola spez-
        iale. 😀

        Titolo corrente

        Seconda frase, con più dettagli.

        Titolo corrente
        """
        let filtered = filter.filterWithMapping(source, mode: .light)
        XCTAssertLessThan(
            filtered.utf16Length,
            source.utf16.count,
            "Il filtro deve creare buchi nella mappa"
        )

        assertMappingMatchesNaive(filtered)
        assertRangeMappingMatchesNaive(filtered)
    }

    func testMappingMatchesNaiveScanOnScaledSyntheticSegments() {
        let text = FilteredText(
            text: String(repeating: "a", count: 20),
            sourceLength: 40,
            segments: [
                FilteredText.Segment(outputStart: 0, outputEnd: 5, sourceStart: 0, sourceEnd: 8),
                FilteredText.Segment(outputStart: 7, outputEnd: 12, sourceStart: 10, sourceEnd: 13),
                FilteredText.Segment(outputStart: 13, outputEnd: 20, sourceStart: 25, sourceEnd: 40)
            ]
        )

        assertMappingMatchesNaive(text)
        assertRangeMappingMatchesNaive(text)
    }

    func testUtf16LengthStaysConsistentAfterDerivedMaps() {
        let source = "Prima 😀 frase.\r\n\r\n\r\nSeconda frase con spez-\niale."
        let filtered = filter.filterWithMapping(source, mode: .light)
        XCTAssertEqual(filtered.utf16Length, filtered.text.utf16.count)

        let shortened = filtered.deleting(utf16Ranges: [1..<4, 2..<6])
        XCTAssertEqual(shortened.utf16Length, shortened.text.utf16.count)

        let sameLength = filtered.replacingCharactersPreservingMapping(
            String(repeating: "x", count: filtered.utf16Length)
        )
        XCTAssertEqual(sameLength.utf16Length, filtered.utf16Length)
        XCTAssertEqual(sameLength.segments, filtered.segments)

        let differentLength = filtered.replacingCharactersPreservingMapping("ab")
        XCTAssertEqual(differentLength.text, "ab")
        XCTAssertEqual(differentLength.utf16Length, 2)
    }

    // MARK: - Normalizzazione dopo il chunking

    func testNormalizationAfterChunkingKeepsRawTextAndSourceRange() {
        let source = "Il prezzo è 12,50 € con lo sconto del 20% su https://lettore.app oggi."
        let filtered = filter.filterWithMapping(source, mode: .light)
        let chunks = chunker.chunk(filteredText: filtered)

        XCTAssertEqual(chunks.count, 1)
        let rawChunk = chunks[0]
        XCTAssertTrue(rawChunk.text.contains("12,50 €"))

        let normalized = normalizer.normalize(rawChunk)
        XCTAssertTrue(normalized.text.contains("12 euro e 50 centesimi"))
        XCTAssertTrue(normalized.text.contains("20 per cento"))
        XCTAssertTrue(normalized.text.contains("link web"))
        XCTAssertFalse(normalized.text.contains("https://"))

        XCTAssertEqual(normalized.rawText, rawChunk.rawText)
        XCTAssertEqual(normalized.sourceRange, rawChunk.sourceRange)
        XCTAssertEqual(normalized.sourceDocumentID, rawChunk.sourceDocumentID)
        XCTAssertEqual(normalized.id, rawChunk.id)

        // Il range viene dal testo grezzo: la slice sorgente contiene la frase
        // originale, non la versione espansa.
        XCTAssertEqual(slice(normalized.sourceRange!, in: source), normalized.rawText)
    }

    // MARK: - Frasi lunghe

    func testLongSentenceSplitsIntoMappedSubRangesWithoutLosingText() {
        let source = "Questa è una frase molto lunga che contiene molte clausole, separate da virgole, e anche altri dettagli; serve a verificare che il taglio aggiorni i sotto-range senza perdere testo, e che ogni pezzo resti mappato sulla sorgente originale."
        let filtered = filter.filterWithMapping(source, mode: .light)

        XCTAssertEqual(filtered.text, source, "La frase di prova non contiene rumore")

        let chunks = chunker.chunk(filteredText: filtered, maxChunkLength: 80)
        XCTAssertGreaterThan(chunks.count, 1, "La frase lunga deve essere spezzata")
        XCTAssertEqual(chunks.map(\.index), Array(0..<chunks.count))

        assertChunksMapToSource(chunks, source: source)
        assertMonotonic(chunks)

        let rebuilt = chunks.map(\.rawText).joined(separator: " ")
        XCTAssertEqual(rebuilt, source, "I sotto-chunk devono ricomporre la frase senza perdere testo")
    }

    // MARK: - Prefisso e remainder

    func testPrefixAndRemainderCoverFilteredTextWithoutGaps() {
        let source = """
        Titolo corrente

        Prima frase introduttiva.

        Pagina 2

        Seconda frase con più parole.

        Titolo corrente

        Terza frase nel mezzo.

        Quarta frase conclusiva.

        Titolo corrente
        """

        let filtered = filter.filterWithMapping(source, mode: .light)
        let documentID = UUID()

        let whole = chunker.chunk(filteredText: filtered, sourceDocumentID: documentID)
        XCTAssertEqual(whole.count, 4)

        let splitIndex = SentenceCarryBuffer.splitPoint(
            in: filtered.text,
            targetLength: filtered.text.count / 2
        )
        let splitOffset = filtered.text[..<splitIndex].utf16.count
        XCTAssertGreaterThan(splitOffset, 0)
        XCTAssertLessThan(splitOffset, filtered.utf16Length)

        let prefix = chunker.chunk(
            filteredText: filtered,
            range: SourceTextRange(location: 0, length: splitOffset),
            sourceDocumentID: documentID
        )
        let remainder = chunker.chunk(
            filteredText: filtered,
            range: SourceTextRange(
                location: splitOffset,
                length: filtered.utf16Length - splitOffset
            ),
            sourceDocumentID: documentID
        )

        let combined = prefix + remainder
        XCTAssertEqual(combined.map(\.rawText), whole.map(\.rawText))
        XCTAssertEqual(combined.map(\.sourceRange), whole.map(\.sourceRange))
        XCTAssertEqual(combined.map(\.sourceDocumentID), whole.map(\.sourceDocumentID))

        assertChunksMapToSource(combined, source: source)
        assertMonotonic(combined)
    }

    // MARK: - UTF-16

    func testSourceRangesUseUTF16NotCharacterOffsets() {
        let source = "😀 È già tutto pronto. Seconda frase àccéntata. 😀 Fine."
        let filtered = filter.filterWithMapping(source, mode: .light)
        let chunks = chunker.chunk(filteredText: filtered)

        XCTAssertEqual(chunks.count, 3)
        assertChunksMapToSource(chunks, source: source)
        assertMonotonic(chunks)

        let secondRange = (source as NSString).range(of: "Seconda")
        let secondCharacterOffset = source.distance(
            from: source.startIndex,
            to: source.range(of: "Seconda")!.lowerBound
        )

        XCTAssertEqual(chunks[1].sourceRange?.location, secondRange.location)
        XCTAssertNotEqual(
            chunks[1].sourceRange?.location,
            secondCharacterOffset,
            "L'offset deve essere UTF-16: l'emoji occupa due unità"
        )
        XCTAssertEqual(slice(chunks[1].sourceRange!, in: source), chunks[1].rawText)
    }

    // MARK: - API e compatibilità

    func testManualChunksHaveNoSourceMapping() {
        let chunks = chunker.chunk(text: "Prima frase. Seconda frase!")

        XCTAssertEqual(chunks.count, 2)
        for chunk in chunks {
            XCTAssertNil(chunk.sourceRange)
            XCTAssertNil(chunk.sourceDocumentID)
            XCTAssertEqual(chunk.rawText, chunk.text)
        }
    }

    func testUnfilteredContiguousTextUsesProvidedBaseRange() {
        let documentID = UUID()
        let base = SourceTextRange(location: 100, length: 30)
        let chunks = chunker.chunk(
            text: "Prima frase. Seconda frase.",
            sourceRange: base,
            sourceDocumentID: documentID
        )

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].sourceRange, SourceTextRange(location: 100, length: 12))
        XCTAssertEqual(chunks[1].sourceRange, SourceTextRange(location: 113, length: 14))
        XCTAssertEqual(chunks.map(\.sourceDocumentID), [documentID, documentID])

        let tooShort = chunker.chunk(
            text: "Prima frase.",
            sourceRange: SourceTextRange(location: 10, length: 2)
        )
        XCTAssertNil(tooShort.first?.sourceRange, "Un base range troppo corto non deve produrre offset inventati")
    }

    func testSourceTextRangeCodableRoundTrip() throws {
        let range = SourceTextRange(location: 42, length: 7)
        let data = try JSONEncoder().encode(range)
        let decoded = try JSONDecoder().decode(SourceTextRange.self, from: data)
        XCTAssertEqual(decoded, range)
    }

    func testAppendChunksPreservesSourceMapping() {
        let suiteName = "LettoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(preferences: PreferencesStore(defaults: defaults))
        state.setQueue([ReadingChunk(index: 0, text: "Prima.")])

        let documentID = UUID()
        let mapped = ReadingChunk(
            index: 0,
            text: "Seconda.",
            sourceDocumentID: documentID,
            sourceRange: SourceTextRange(location: 20, length: 8)
        )
        let appended = state.appendChunks([mapped])

        XCTAssertEqual(appended.count, 1)
        XCTAssertEqual(appended[0].sourceDocumentID, documentID)
        XCTAssertEqual(appended[0].sourceRange, SourceTextRange(location: 20, length: 8))
        XCTAssertEqual(appended[0].index, 1)
        XCTAssertEqual(appended[0].id, mapped.id)
    }

    // MARK: - Helper

    private func slice(_ range: SourceTextRange, in source: String) -> String {
        (source as NSString).substring(with: range.nsRange)
    }

    private func assertChunksMapToSource(
        _ chunks: [ReadingChunk],
        source: String,
        dehyphenate: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let nsSource = source as NSString

        for chunk in chunks {
            guard let range = chunk.sourceRange else {
                XCTFail("Chunk senza sourceRange: \(chunk.rawText)", file: file, line: line)
                continue
            }

            XCTAssertGreaterThanOrEqual(range.location, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(range.length, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(range.end, nsSource.length, file: file, line: line)

            let originalSlice = nsSource
                .substring(with: range.nsRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let comparable: String
            if dehyphenate {
                comparable = originalSlice.replacingOccurrences(
                    of: #"([\p{L}])[-‐‑][ \t]*\n[ \t]*([\p{Ll}])"#,
                    with: "$1$2",
                    options: .regularExpression
                )
            } else {
                comparable = originalSlice
            }

            XCTAssertEqual(
                comparable,
                chunk.rawText,
                "La slice sorgente deve contenere la frase del chunk",
                file: file,
                line: line
            )
        }
    }

    private func assertMonotonic(
        _ chunks: [ReadingChunk],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var previousEnd = 0
        for chunk in chunks {
            guard let range = chunk.sourceRange else {
                XCTFail("Chunk senza sourceRange: \(chunk.rawText)", file: file, line: line)
                continue
            }
            XCTAssertGreaterThanOrEqual(
                range.location,
                previousEnd,
                "I range devono essere monotoni e non sovrapposti",
                file: file,
                line: line
            )
            previousEnd = range.end
        }
    }

    // MARK: - Riferimento naive (scansione lineare pre-ottimizzazione)

    private func assertMappingMatchesNaive(
        _ text: FilteredText,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for offset in -1...(text.utf16Length + 1) {
            XCTAssertEqual(
                text.mapStart(offset),
                naiveMapStart(text, offset),
                "mapStart(\(offset))",
                file: file,
                line: line
            )
            XCTAssertEqual(
                text.mapEnd(offset),
                naiveMapEnd(text, offset),
                "mapEnd(\(offset))",
                file: file,
                line: line
            )
            XCTAssertEqual(
                text.sourceOffset(atUTF16Offset: offset),
                naiveMapStart(text, offset),
                "sourceOffset(\(offset))",
                file: file,
                line: line
            )
            let expectedPoint = naiveMapStart(text, offset)
                .map { SourceTextRange(location: $0, length: 0) }
            XCTAssertEqual(
                text.sourceRange(atUTF16Offset: offset),
                expectedPoint,
                "sourceRange(atUTF16Offset: \(offset))",
                file: file,
                line: line
            )
        }
    }

    private func assertRangeMappingMatchesNaive(
        _ text: FilteredText,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let length = text.utf16Length
        for location in 0...length {
            for rangeLength in 0...(length - location) {
                let range = SourceTextRange(location: location, length: rangeLength)
                XCTAssertEqual(
                    text.sourceRange(forRelativeRange: range),
                    naiveSourceRange(text, range),
                    "sourceRange(forRelativeRange: \(location), \(rangeLength))",
                    file: file,
                    line: line
                )
            }
        }

        let invalidRanges = [
            SourceTextRange(location: -1, length: 1),
            SourceTextRange(location: 0, length: length + 1),
            SourceTextRange(location: length + 1, length: 0)
        ]
        for invalid in invalidRanges {
            XCTAssertNil(
                text.sourceRange(forRelativeRange: invalid),
                "Range non valido: \(invalid)",
                file: file,
                line: line
            )
        }
    }

    private func naiveSourceRange(_ text: FilteredText, _ range: SourceTextRange) -> SourceTextRange? {
        guard range.location >= 0,
              range.length >= 0,
              range.end <= text.utf16Length else {
            return nil
        }
        guard let start = naiveMapStart(text, range.location) else { return nil }
        guard range.length > 0 else {
            return SourceTextRange(location: start, length: 0)
        }
        let end = naiveMapEnd(text, range.end) ?? start
        return SourceTextRange(location: start, length: max(0, end - start))
    }

    private func naiveMapStart(_ text: FilteredText, _ offset: Int) -> Int? {
        guard offset >= 0, offset <= text.utf16Length else { return nil }
        if offset == text.utf16Length {
            return text.segments.last?.sourceEnd ?? 0
        }
        for segment in text.segments where offset < segment.outputEnd {
            if offset <= segment.outputStart {
                return segment.sourceStart
            }
            return naiveScale(offset - segment.outputStart, in: segment, roundUp: false)
        }
        return text.segments.last?.sourceEnd ?? 0
    }

    private func naiveMapEnd(_ text: FilteredText, _ offset: Int) -> Int? {
        guard offset >= 0, offset <= text.utf16Length else { return nil }
        if offset == 0 {
            return text.segments.first?.sourceStart ?? 0
        }

        var lastSourceEnd: Int?
        for segment in text.segments {
            if offset <= segment.outputStart {
                return lastSourceEnd ?? segment.sourceStart
            }
            if offset <= segment.outputEnd {
                if offset == segment.outputEnd {
                    return segment.sourceEnd
                }
                return naiveScale(offset - segment.outputStart, in: segment, roundUp: true)
            }
            lastSourceEnd = segment.sourceEnd
        }
        return lastSourceEnd ?? 0
    }

    private func naiveScale(
        _ localOffset: Int,
        in segment: FilteredText.Segment,
        roundUp: Bool
    ) -> Int {
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
