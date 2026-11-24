import XCTest
import AppKit
import LettoreCore
@testable import LettoreSystem

/// Lo snapshot degli appunti deve essere fatto di dati puri: gli
/// `NSPasteboardItem` originali sono legati al pasteboard di origine e
/// riscriverli faceva fallire `writeObjects` con un'eccezione (crash SIGABRT).
/// Il fallback clipboard deve inoltre sopravvivere a copie lente e catture
/// annullate, serializzare le catture sovrapposte e non sovrascrivere una
/// copia dell'utente, senza distruggere gli appunti originali.
@MainActor
final class ClipboardSnapshotTests: XCTestCase {

    private let jpegType = NSPasteboard.PasteboardType("public.jpeg")
    private let utf16ExternalType = NSPasteboard.PasteboardType("public.utf16-external-plain-text")
    private static let jpegData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("it.lettore.clipboardsnapshot.\(UUID().uuidString)"))
    }

    // MARK: - Snapshot

    func testSnapshotRestoreKeepsTypesAndDoesNotThrow() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()

        let original = NSPasteboardItem()
        original.setData(Self.jpegData, forType: jpegType)
        original.setString("testo di prova", forType: .string)
        XCTAssertTrue(pasteboard.writeObjects([original]))

        let snapshot = makePasteboardSnapshot(of: pasteboard)
        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.sourceItemCount, 1)
        XCTAssertEqual(Set(snapshot.items[0].keys), [jpegType, .string])

        // Il ripristino arriva dopo un clearContents: è il caso che faceva
        // esplodere `writeObjects` con gli item originali.
        pasteboard.clearContents()
        pasteboard.setString("contenuto successivo", forType: .string)

        restorePasteboardSnapshot(snapshot, to: pasteboard)

        let restored = pasteboard.pasteboardItems ?? []
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(Set(restored.first?.types ?? []), [jpegType, .string])
        XCTAssertEqual(restored.first?.data(forType: jpegType), Self.jpegData)
        XCTAssertEqual(restored.first?.string(forType: .string), "testo di prova")
    }

    /// Un item RTF fa dichiarare ad AppKit anche i tipi testuali derivati
    /// (`public.utf16-external-plain-text`, `public.utf8-plain-text`), che in
    /// alcuni casi non sono leggibili alla prima lettura. Il contenuto
    /// principale è comunque l'RTF: lo snapshot non è parziale e il ripristino
    /// deve rimetterlo negli appunti al posto della selezione copiata.
    func testRTFItemSnapshotIgnoresUnmaterializedDerivedTextTypes() {
        let source = makePasteboard()
        source.clearContents()

        // Testo non convertibile in RTF: AppKit dichiara i tipi derivati ma
        // `data(forType:)` può restituire `nil`, come fanno diverse app reali.
        let rtfText = "testo RTF non convertibile"
        let original = NSPasteboardItem()
        original.setString(rtfText, forType: .rtf)
        XCTAssertTrue(source.writeObjects([original]))

        let written = source.pasteboardItems?.first
        XCTAssertNotNil(written?.data(forType: .rtf))
        XCTAssertTrue(
            Set(written?.types ?? []).contains(utf16ExternalType),
            "AppKit deve dichiarare il tipo derivato per esercitare il caso"
        )

        let snapshot = makePasteboardSnapshot(of: source)
        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.sourceItemCount, 1)
        XCTAssertEqual(snapshot.items[0][.rtf], written?.data(forType: .rtf))
        XCTAssertTrue(
            Set(snapshot.items[0].keys).isSubset(of: PasteboardSnapshot.textualContentTypes),
            "Oltre all'RTF lo snapshot può contenere solo tipi testuali derivati"
        )
        XCTAssertFalse(
            snapshot.hasPartialMaterialization,
            "Gli alias testuali non materializzati non devono bloccare il ripristino"
        )

        let target = makePasteboard()
        target.clearContents()
        target.setString("appunti utente", forType: .string)

        restorePasteboardSnapshot(snapshot, to: target)

        let restored = target.pasteboardItems ?? []
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.data(forType: .rtf), written?.data(forType: .rtf))
        XCTAssertNotEqual(
            target.string(forType: .string),
            "appunti utente",
            "Gli appunti utente vanno sostituiti dallo snapshot"
        )
    }

    /// Controllo deterministico della stessa regola, indipendente dal
    /// comportamento di AppKit: i tipi attesi includono gli alias testuali che
    /// il pasteboard non ha materializzato.
    func testInjectedMissingTextAliasesDoNotMakeSnapshotPartial() {
        let rtfData = "{\\rtf1\\ansi Ciao}".data(using: .ascii)!
        let snapshot = PasteboardSnapshot(
            items: [[.rtf: rtfData]],
            sourceItemCount: 1,
            expectedTypes: [[.rtf, .string, utf16ExternalType]],
            isTruncatedForByteBudget: false
        )
        XCTAssertEqual(snapshot.materializedTypeCount, 1)
        XCTAssertEqual(snapshot.expectedTypeCount, 3)
        XCTAssertFalse(snapshot.hasPartialMaterialization)

        let target = makePasteboard()
        target.clearContents()
        target.setString("appunti utente", forType: .string)

        restorePasteboardSnapshot(snapshot, to: target)

        XCTAssertEqual(target.pasteboardItems?.count, 1)
        XCTAssertEqual(target.pasteboardItems?.first?.data(forType: .rtf), rtfData)
        XCTAssertNotEqual(target.string(forType: .string), "appunti utente")
    }

    /// Un item che dichiara RTF e stringa ma materializza solo la stringa ha
    /// perso il formato: la stringa non è una forma primaria forte e non può
    /// ricostruire l'RTF mancante. Lo snapshot è parziale e il ripristino va
    /// saltato, altrimenti la selezione copiata resterebbe al posto degli
    /// appunti originali con il formato degradato.
    func testInjectedRTFDeclaredButOnlyStringMaterializedIsPartial() {
        let stringData = "solo testo".data(using: .utf8)!
        let snapshot = PasteboardSnapshot(
            items: [[.string: stringData]],
            sourceItemCount: 1,
            expectedTypes: [[.rtf, .string]],
            isTruncatedForByteBudget: false
        )
        XCTAssertTrue(
            snapshot.hasPartialMaterialization,
            "L'RTF dichiarato e non materializzato rende lo snapshot parziale anche con la stringa"
        )

        let target = makePasteboard()
        target.clearContents()
        target.setString("appunti utente", forType: .string)

        restorePasteboardSnapshot(snapshot, to: target)

        XCTAssertEqual(target.string(forType: .string), "appunti utente")
    }

    /// Stessa regola sul percorso reale: l'item promette RTF e stringa, ma il
    /// provider materializza solo la stringa. AppKit dichiara anche gli alias
    /// derivati; l'RTF mancante rende comunque parziale lo snapshot.
    func testItemDeclaringRTFButProvidingOnlyStringIsPartial() {
        let source = makePasteboard()
        source.clearContents()

        let partial = NSPasteboardItem()
        partial.setDataProvider(
            StringOnlyPasteboardDataProvider(text: "testo parziale"),
            forTypes: [.rtf, .string]
        )
        XCTAssertTrue(source.writeObjects([partial]))
        XCTAssertEqual(source.pasteboardItems?.count, 1)

        let snapshot = makePasteboardSnapshot(of: source)
        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(Set(snapshot.items[0].keys), [.string])
        XCTAssertTrue(
            snapshot.hasPartialMaterialization,
            "RTF promesso e non materializzato: lo snapshot è parziale"
        )

        let target = makePasteboard()
        target.clearContents()
        target.setString("appunti utente", forType: .string)

        restorePasteboardSnapshot(snapshot, to: target)

        XCTAssertEqual(target.string(forType: .string), "appunti utente")
    }

    func testSnapshotIsReusableForConsecutiveRestores() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()

        let original = NSPasteboardItem()
        original.setData(Self.jpegData, forType: jpegType)
        XCTAssertTrue(pasteboard.writeObjects([original]))

        let snapshot = makePasteboardSnapshot(of: pasteboard)

        // Lo stesso snapshot deve poter essere ripristinato più volte: il
        // secondo restore riaprirebbe il crash se contenesse item legati.
        for attempt in 0..<2 {
            pasteboard.clearContents()
            pasteboard.setString("copia \(attempt)", forType: .string)

            restorePasteboardSnapshot(snapshot, to: pasteboard)

            XCTAssertEqual(pasteboard.pasteboardItems?.count, 1, "restore \(attempt)")
            XCTAssertEqual(
                pasteboard.pasteboardItems?.first?.data(forType: jpegType),
                Self.jpegData,
                "restore \(attempt)"
            )
        }
    }

    func testEmptySnapshotClearsContents() {
        let source = makePasteboard()
        source.clearContents()

        let snapshot = makePasteboardSnapshot(of: source)
        XCTAssertTrue(snapshot.items.isEmpty)
        XCTAssertEqual(snapshot.sourceItemCount, 0)

        let target = makePasteboard()
        target.clearContents()
        target.setString("da cancellare", forType: .string)
        XCTAssertFalse(target.pasteboardItems?.isEmpty ?? true)

        restorePasteboardSnapshot(snapshot, to: target)

        XCTAssertTrue(target.pasteboardItems?.isEmpty ?? true)
        XCTAssertNil(target.string(forType: .string))
    }

    func testSnapshotSurvivesPasteboardChanges() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()

        let original = NSPasteboardItem()
        original.setData(Self.jpegData, forType: jpegType)
        XCTAssertTrue(pasteboard.writeObjects([original]))

        let snapshot = makePasteboardSnapshot(of: pasteboard)

        // Sostituisce più volte il contenuto: lo snapshot non deve dipendere
        // dal pasteboard di origine.
        pasteboard.clearContents()
        pasteboard.setString("primo", forType: .string)
        pasteboard.clearContents()
        pasteboard.setString("secondo", forType: .string)

        restorePasteboardSnapshot(snapshot, to: pasteboard)

        let restored = pasteboard.pasteboardItems ?? []
        XCTAssertEqual(restored.first?.data(forType: jpegType), Self.jpegData)
        XCTAssertNil(restored.first?.string(forType: .string))
    }

    func testUnmaterializedSnapshotDoesNotClearUserContents() {
        let source = makePasteboard()
        source.clearContents()
        let promised = NSPasteboardItem()
        promised.setDataProvider(NilPasteboardDataProvider(), forTypes: [.string])
        XCTAssertTrue(source.writeObjects([promised]))
        XCTAssertEqual(source.pasteboardItems?.count, 1)

        // Il provider promised non fornisce dati: lo snapshot resta vuoto ma
        // la sorgente non era vuota.
        let snapshot = makePasteboardSnapshot(of: source)
        XCTAssertTrue(snapshot.items.isEmpty)
        XCTAssertEqual(snapshot.sourceItemCount, 1)
        XCTAssertTrue(snapshot.hasPartialMaterialization)

        let target = makePasteboard()
        target.clearContents()
        target.setString("appunti utente", forType: .string)

        restorePasteboardSnapshot(snapshot, to: target)

        XCTAssertEqual(target.string(forType: .string), "appunti utente")
    }

    func testPartialSnapshotSkipsRestore() {
        let source = makePasteboard()
        source.clearContents()

        let real = NSPasteboardItem()
        real.setString("testo materializzato", forType: .string)
        let promised = NSPasteboardItem()
        promised.setDataProvider(NilPasteboardDataProvider(), forTypes: [.string])
        XCTAssertTrue(source.writeObjects([real, promised]))
        XCTAssertEqual(source.pasteboardItems?.count, 2)

        // Un item su due non è materializzabile: riscrivere solo il primo
        // perderebbe l'altro, quindi il ripristino va saltato del tutto.
        let snapshot = makePasteboardSnapshot(of: source)
        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.sourceItemCount, 2)
        XCTAssertTrue(snapshot.hasPartialMaterialization)

        let target = makePasteboard()
        target.clearContents()
        target.setString("appunti utente", forType: .string)

        restorePasteboardSnapshot(snapshot, to: target)

        XCTAssertEqual(target.pasteboardItems?.count, 1)
        XCTAssertEqual(target.string(forType: .string), "appunti utente")
    }

    func testItemMissingAPromisedTypeSkipsRestore() {
        let source = makePasteboard()
        source.clearContents()

        // L'item promette testo e fileURL ma il provider fornisce solo il
        // testo: il conteggio degli item coincide, i tipi no.
        let partial = NSPasteboardItem()
        partial.setDataProvider(
            StringOnlyPasteboardDataProvider(text: "testo parziale"),
            forTypes: [.string, .fileURL]
        )
        XCTAssertTrue(source.writeObjects([partial]))
        XCTAssertEqual(source.pasteboardItems?.count, 1)

        let snapshot = makePasteboardSnapshot(of: source)
        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.sourceItemCount, 1)
        XCTAssertEqual(Set(snapshot.items[0].keys), [.string])
        XCTAssertEqual(snapshot.expectedTypes.first, [.string, .fileURL])
        XCTAssertTrue(snapshot.hasPartialMaterialization)

        let target = makePasteboard()
        target.clearContents()
        target.setString("appunti utente", forType: .string)

        restorePasteboardSnapshot(snapshot, to: target)

        // Il tipo mancante non è recuperabile: riscrivere il solo testo
        // perderebbe fileURL, quindi si lascia intatto il contenuto corrente.
        XCTAssertEqual(target.string(forType: .string), "appunti utente")
        XCTAssertNil(target.pasteboardItems?.first?.data(forType: .fileURL))
    }

    func testSnapshotOverByteBudgetIsPartialAndSkipsRestore() {
        let source = makePasteboard()
        source.clearContents()

        let big = NSPasteboardItem()
        big.setData(Data(repeating: 0xAB, count: 64), forType: jpegType)
        XCTAssertTrue(source.writeObjects([big]))

        // Soglia minuscola con dati piccoli: niente allocazioni da 64 MiB.
        let snapshot = makePasteboardSnapshot(of: source, byteBudget: 16)
        XCTAssertTrue(snapshot.isTruncatedForByteBudget)
        XCTAssertTrue(snapshot.items.isEmpty)
        XCTAssertEqual(snapshot.sourceItemCount, 1)
        XCTAssertTrue(snapshot.hasPartialMaterialization)

        let target = makePasteboard()
        target.clearContents()
        target.setString("appunti utente", forType: .string)

        restorePasteboardSnapshot(snapshot, to: target)

        XCTAssertEqual(target.string(forType: .string), "appunti utente")
    }

    // MARK: - Selezione AX e slot clipboard

    /// Una selezione vuota è una risposta valida dell'app: non deve
    /// autorizzare Cmd+C, attivazione e furto del focus. Solo l'attributo non
    /// disponibile giustifica il fallback clipboard.
    func testEmptySelectionDoesNotRequireClipboardFallback() {
        let empty = SelectionReadout.classify(
            focusedElementAvailable: true,
            attributeSucceeded: true,
            selectedText: ""
        )
        let whitespaceOnly = SelectionReadout.classify(
            focusedElementAvailable: true,
            attributeSucceeded: true,
            selectedText: " \n\t "
        )
        let unavailable = SelectionReadout.classify(
            focusedElementAvailable: true,
            attributeSucceeded: false,
            selectedText: nil
        )
        let noFocusedElement = SelectionReadout.classify(
            focusedElementAvailable: false,
            attributeSucceeded: true,
            selectedText: "testo"
        )
        let text = SelectionReadout.classify(
            focusedElementAvailable: true,
            attributeSucceeded: true,
            selectedText: "selezione"
        )

        XCTAssertEqual(empty, .empty)
        XCTAssertEqual(whitespaceOnly, .empty)
        XCTAssertFalse(empty.requiresClipboardFallback)
        XCTAssertFalse(whitespaceOnly.requiresClipboardFallback)
        XCTAssertEqual(unavailable, .unavailable)
        XCTAssertTrue(unavailable.requiresClipboardFallback)
        XCTAssertEqual(noFocusedElement, .unavailable)
        XCTAssertTrue(noFocusedElement.requiresClipboardFallback)
        XCTAssertEqual(text, .text("selezione"))
        XCTAssertFalse(text.requiresClipboardFallback)
    }

    /// L'attesa di una cattura sovrapposta deve superare la soglia di stale,
    /// altrimenti la seconda richiesta rinuncia mentre la prima è ancora
    /// considerata valida: nessuna cattura, nessuna invalidazione.
    func testClipboardCaptureWaitTimeoutExceedsStaleInterval() {
        XCTAssertGreaterThan(
            AXCaptureService.clipboardCaptureWaitTimeout,
            AXCaptureService.clipboardCaptureStaleInterval,
            "Chi attende uno slot non deve rinunciare prima che l'occupante sia stale"
        )
    }

    // MARK: - Fallback clipboard

    func testFallbackCopiesTextAndRestoresPreviousClipboard() async {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("appunti originali", forType: .string)

        let clipboard = ClipboardPasteboard(pasteboard)
        let copyAction = FakeClipboardCopyAction(pasteboard: clipboard, copiedText: "testo selezionato")
        let service = AXCaptureService()

        let captured = await service.captureViaClipboardFallback(
            pasteboard: clipboard,
            copyAction: copyAction
        )

        XCTAssertEqual(captured?.text, "testo selezionato")
        XCTAssertEqual(pasteboard.string(forType: .string), "appunti originali")
    }

    func testSlowCopyIsObservedInsideGraceWindow() async {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("appunti originali", forType: .string)

        let clipboard = ClipboardPasteboard(pasteboard)
        // La copia arriva oltre i 150 ms del vecchio polling.
        let copyAction = FakeClipboardCopyAction(
            pasteboard: clipboard,
            copiedText: "copia lenta",
            delayNanoseconds: 200_000_000
        )
        let service = AXCaptureService()

        let captured = await service.captureViaClipboardFallback(
            pasteboard: clipboard,
            copyAction: copyAction
        )

        XCTAssertEqual(captured?.text, "copia lenta")
        XCTAssertEqual(pasteboard.string(forType: .string), "appunti originali")
    }

    func testReducedPollingWindowDetectsLateCopy() async {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("appunti originali", forType: .string)

        let clipboard = ClipboardPasteboard(pasteboard)
        // Scrittura differita di ~40 ms: arriva dopo i primi tick ma dentro
        // una finestra ridotta a 20 tick (200 ms), senza attendere il secondo
        // reale della produzione.
        let copyAction = FakeClipboardCopyAction(
            pasteboard: clipboard,
            copiedText: "copia differita",
            asyncWriteDelayNanoseconds: 40_000_000
        )
        let service = AXCaptureService()

        let captured = await service.captureViaClipboardFallback(
            pasteboard: clipboard,
            copyAction: copyAction,
            totalTicks: 20,
            activationTick: 1_000
        )

        await copyAction.waitForPendingWrite()
        XCTAssertEqual(captured?.text, "copia differita")
        XCTAssertEqual(pasteboard.string(forType: .string), "appunti originali")
    }

    func testTwoPhaseCopyWithDelayedTextIsCapturedAndRestored() async {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("appunti originali", forType: .string)

        let clipboard = ClipboardPasteboard(pasteboard)
        // Copia in due fasi: `clearContents` subito, testo dopo ~90 ms. Il
        // primo cambio appunti non ha stringa e non deve far uscire.
        let copyAction = FakeClipboardCopyAction(
            pasteboard: clipboard,
            copiedText: "selezione in due fasi",
            twoPhaseCopyDelayNanoseconds: 90_000_000
        )
        let service = AXCaptureService()

        let captured = await service.captureViaClipboardFallback(
            pasteboard: clipboard,
            copyAction: copyAction,
            totalTicks: 40,
            activationTick: 1_000
        )
        await copyAction.waitForPendingWrite()

        XCTAssertEqual(captured?.text, "selezione in due fasi")
        XCTAssertEqual(pasteboard.string(forType: .string), "appunti originali")
    }

    func testChangeWithoutTextRestoresSnapshotAfterGrace() async {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("appunti originali", forType: .string)

        let clipboard = ClipboardPasteboard(pasteboard)
        // Copia non testuale: il cambio appunti non produce alcuna stringa.
        // Oltre la grazia la cattura fallisce, ma la selezione copiata non
        // deve restare negli appunti.
        let copyAction = FakeClipboardCopyAction(
            pasteboard: clipboard,
            nonTextData: Data([0xFF, 0xD8, 0xFF, 0xE0])
        )
        let service = AXCaptureService()

        let captured = await service.captureViaClipboardFallback(
            pasteboard: clipboard,
            copyAction: copyAction,
            totalTicks: 40,
            activationTick: 1_000,
            nonTextGraceInterval: 0.1
        )

        XCTAssertNil(captured)
        XCTAssertEqual(
            pasteboard.string(forType: .string),
            "appunti originali",
            "Lo snapshot va ripristinato anche senza testo letto"
        )
        XCTAssertNil(pasteboard.data(forType: FakeClipboardCopyAction.nonTextType))
    }

    func testStaleCaptureExitsWithoutActivationOrRestore() async {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("appunti originali", forType: .string)

        let clipboard = ClipboardPasteboard(pasteboard)
        // La prima cattura non produce testo e, se il token non la fermasse,
        // arriverebbe all'attivazione dell'app di origine.
        let staleAction = FakeClipboardCopyAction(
            pasteboard: clipboard,
            copiesOnActivationOnly: true
        )
        let service = AXCaptureService()

        let stale = Task {
            await service.captureViaClipboardFallback(
                targeting: 4242,
                pasteboard: clipboard,
                copyAction: staleAction,
                totalTicks: 300,
                activationTick: 50,
                staleInterval: 0.05
            )
        }
        try? await Task.sleep(nanoseconds: 150_000_000)

        // La seconda cattura trova la prima oltre la soglia ridotta e la
        // invalida: la prima deve uscire senza Cmd+C e senza ripristini.
        let freshAction = FakeClipboardCopyAction(pasteboard: clipboard, copiedText: "nuova")
        let fresh = await service.captureViaClipboardFallback(
            pasteboard: clipboard,
            copyAction: freshAction,
            totalTicks: 20,
            activationTick: 1_000,
            staleInterval: 0.05
        )

        let staleCaptured = await stale.value
        let staleActivations = await staleAction.recordedActivationPIDs()
        XCTAssertNil(staleCaptured, "La cattura invalidata non restituisce testo")
        XCTAssertTrue(staleActivations.isEmpty, "Nessun Cmd+C dalla cattura invalidata")
        XCTAssertEqual(fresh?.text, "nuova")
        XCTAssertEqual(pasteboard.string(forType: .string), "appunti originali")
    }

    func testCopyLandedAfterCancellationIsRestoredAndReturned() async {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("appunti originali", forType: .string)

        let clipboard = ClipboardPasteboard(pasteboard)
        let copyAction = FakeClipboardCopyAction(
            pasteboard: clipboard,
            copiedText: "copia tardiva",
            asyncWriteDelayNanoseconds: 60_000_000
        )
        let service = AXCaptureService()

        // Annulla prima che la copia atterri: il ramo di cancellazione deve
        // comunque osservare per un breve tratto, restituire la copia tardiva
        // e ripristinare gli appunti di origine.
        let task = Task {
            await service.captureViaClipboardFallback(
                pasteboard: clipboard,
                copyAction: copyAction,
                totalTicks: 200
            )
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()
        let captured = await task.value
        await copyAction.waitForPendingWrite()

        XCTAssertEqual(captured?.text, "copia tardiva")
        XCTAssertEqual(pasteboard.string(forType: .string), "appunti originali")
    }

    func testCopyIsNotRequestedWhenTaskIsAlreadyCancelled() async {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("appunti originali", forType: .string)

        let clipboard = ClipboardPasteboard(pasteboard)
        let copyAction = FakeClipboardCopyAction(pasteboard: clipboard, copiedText: "nostra")
        let service = AXCaptureService()

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await service.captureViaClipboardFallback(
                pasteboard: clipboard,
                copyAction: copyAction
            )
        }
        let captured = await task.value

        XCTAssertNil(captured)
        let copyRequests = await copyAction.recordedCopyRequests()
        XCTAssertTrue(copyRequests.isEmpty, "Nessun Cmd+C da una cattura già annullata")
        XCTAssertEqual(pasteboard.string(forType: .string), "appunti originali")
    }

    func testUserCopyInsideWindowIsPreserved() async {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("appunti originali", forType: .string)

        let clipboard = ClipboardPasteboard(pasteboard)
        // La nostra copia scrive "nostra"; poco dopo, dentro la finestra di
        // osservazione, l'utente copia "utente".
        let copyAction = FakeClipboardCopyAction(
            pasteboard: clipboard,
            copiedText: "nostra",
            userWrite: ("utente", 25_000_000)
        )
        let service = AXCaptureService()

        let captured = await service.captureViaClipboardFallback(
            pasteboard: clipboard,
            copyAction: copyAction
        )
        await copyAction.waitForPendingWrite()

        XCTAssertEqual(captured?.text, "nostra", "La cattura resta la nostra selezione")
        XCTAssertEqual(
            pasteboard.string(forType: .string),
            "utente",
            "La copia dell'utente non va sovrascritta dal ripristino"
        )
    }

    func testMissingCopyReturnsNilAndKeepsClipboard() async {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("appunti originali", forType: .string)

        let clipboard = ClipboardPasteboard(pasteboard)
        let copyAction = FakeClipboardCopyAction(pasteboard: clipboard, copiedText: nil)
        let service = AXCaptureService()

        let captured = await service.captureViaClipboardFallback(
            pasteboard: clipboard,
            copyAction: copyAction
        )

        XCTAssertNil(captured)
        XCTAssertEqual(pasteboard.string(forType: .string), "appunti originali")
    }

    func testActivationFallbackCopiesWhenTargetedCopyFails() async {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("appunti originali", forType: .string)

        let targetPID: pid_t = 4242
        let clipboard = ClipboardPasteboard(pasteboard)
        let copyAction = FakeClipboardCopyAction(
            pasteboard: clipboard,
            copiedText: "testo recuperato",
            copiesOnActivationOnly: true
        )
        let service = AXCaptureService()

        let captured = await service.captureViaClipboardFallback(
            targeting: targetPID,
            pasteboard: clipboard,
            copyAction: copyAction
        )

        XCTAssertEqual(captured?.text, "testo recuperato")
        let activationPIDs = await copyAction.recordedActivationPIDs()
        XCTAssertEqual(activationPIDs, [targetPID])
        XCTAssertEqual(pasteboard.string(forType: .string), "appunti originali")
    }

    func testCopyOnUnmaterializedSourceDoesNotCopyOrWipePasteboard() async {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        let promised = NSPasteboardItem()
        promised.setDataProvider(NilPasteboardDataProvider(), forTypes: [.string])
        XCTAssertTrue(pasteboard.writeObjects([promised]))
        let changeCountBefore = pasteboard.changeCount

        let clipboard = ClipboardPasteboard(pasteboard)
        let copyAction = FakeClipboardCopyAction(pasteboard: clipboard, copiedText: "testo selezionato")
        let service = AXCaptureService()

        let captured = await service.captureViaClipboardFallback(
            targeting: 4242,
            pasteboard: clipboard,
            copyAction: copyAction
        )

        // Lo snapshot non è ripristinabile: niente Cmd+C, niente attivazione.
        // Meglio rinunciare che lasciare la selezione copiata al posto degli
        // appunti (o azzerarli con uno snapshot vuoto).
        XCTAssertNil(captured)
        let copyRequests = await copyAction.recordedCopyRequests()
        let activations = await copyAction.recordedActivationPIDs()
        XCTAssertTrue(copyRequests.isEmpty, "Nessun Cmd+C con uno snapshot parziale")
        XCTAssertTrue(activations.isEmpty, "Nessuna attivazione con uno snapshot parziale")
        XCTAssertEqual(pasteboard.changeCount, changeCountBefore, "Gli appunti non vanno toccati")
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
    }

    /// Uno snapshot parziale non è ripristinabile: il Cmd+C lascerebbe la
    /// selezione copiata negli appunti al posto del contenuto dell'utente.
    /// La cattura deve rinunciare prima di inviare eventi o attivare app.
    func testPartialSnapshotSkipsCopyAndLeavesClipboardUntouched() async {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()

        let real = NSPasteboardItem()
        real.setString("appunti originali", forType: .string)
        let promised = NSPasteboardItem()
        promised.setDataProvider(NilPasteboardDataProvider(), forTypes: [.string])
        XCTAssertTrue(pasteboard.writeObjects([real, promised]))
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 2)
        let changeCountBefore = pasteboard.changeCount

        let clipboard = ClipboardPasteboard(pasteboard)
        let copyAction = FakeClipboardCopyAction(pasteboard: clipboard, copiedText: "selezione")
        let service = AXCaptureService()

        let captured = await service.captureViaClipboardFallback(
            targeting: 4242,
            pasteboard: clipboard,
            copyAction: copyAction
        )

        XCTAssertNil(captured)
        let copyRequests = await copyAction.recordedCopyRequests()
        let activations = await copyAction.recordedActivationPIDs()
        XCTAssertTrue(copyRequests.isEmpty, "Cmd+C mai chiamato con snapshot parziale")
        XCTAssertTrue(activations.isEmpty, "Attivazione mai tentata con snapshot parziale")
        XCTAssertEqual(pasteboard.changeCount, changeCountBefore, "Gli appunti restano intatti")
        XCTAssertEqual(pasteboard.string(forType: .string), "appunti originali")
    }

    func testOverlappingCaptureWaitsAndCompletes() async {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("appunti originali", forType: .string)

        let clipboard = ClipboardPasteboard(pasteboard)
        let copyAction = FakeClipboardCopyAction(
            pasteboard: clipboard,
            copiedText: "testo lento",
            delayNanoseconds: 300_000_000
        )
        let service = AXCaptureService()

        let first = Task {
            await service.captureViaClipboardFallback(
                pasteboard: clipboard,
                copyAction: copyAction
            )
        }
        try? await Task.sleep(nanoseconds: 100_000_000)

        // La seconda cattura attende la prima e poi procede: la richiesta non
        // va persa con un falso "nessuna selezione".
        let second = await service.captureViaClipboardFallback(
            pasteboard: clipboard,
            copyAction: copyAction
        )
        XCTAssertEqual(second?.text, "testo lento", "La cattura sovrapposta attende e completa")

        let firstCaptured = await first.value
        XCTAssertEqual(firstCaptured?.text, "testo lento")
        XCTAssertEqual(pasteboard.string(forType: .string), "appunti originali")
    }

    // MARK: - SystemClipboardCopyAction (percorso reale, dipendenze finte)

    func testSystemActionDoesNotPostWhenActivationFails() async {
        let spy = ClipboardActionSpy(previousPID: 4242, frontmostPID: 777, activationSucceeds: false)
        let action = makeSystemCopyAction(spy)
        let targetPID: pid_t = 777

        await action.copyActivatingTarget(targetPID)

        let recorded = await spy.recorded()
        XCTAssertEqual(recorded.activations, [targetPID])
        XCTAssertTrue(recorded.posts.isEmpty, "Nessun Cmd+C globale se l'attivazione fallisce")
        XCTAssertTrue(recorded.restores.isEmpty, "Il focus non è mai cambiato")
    }

    func testSystemActionDoesNotPostWhenTargetIsNotFrontmost() async {
        let spy = ClipboardActionSpy(previousPID: 4242, frontmostPID: 999, activationSucceeds: true)
        let action = makeSystemCopyAction(spy)
        let targetPID: pid_t = 777

        await action.copyActivatingTarget(targetPID)

        let recorded = await spy.recorded()
        XCTAssertEqual(recorded.activations, [targetPID])
        XCTAssertTrue(recorded.posts.isEmpty, "Cmd+C non inviato all'app sbagliata")
        XCTAssertEqual(recorded.restores, [4242], "Il focus va ripristinato")
    }

    /// Durante il settle il focus può tornare su un'altra app (attivazione
    /// annullata dal sistema o interazione dell'utente): il Cmd+C globale
    /// finirebbe sull'app sbagliata. Sequenza delle interrogazioni: app
    /// precedente, target in primo piano, altra app dopo il settle.
    func testSystemActionDoesNotPostWhenTargetLeavesFrontmostDuringSettle() async {
        let spy = ClipboardActionSpy(
            previousPID: 4242,
            frontmostPID: 777,
            activationSucceeds: true,
            frontmostSequence: [4242, 777, 999]
        )
        let action = SystemClipboardCopyAction(
            frontmostPID: { await spy.frontmost() },
            activate: { await spy.activate($0) },
            restoreFocus: { await spy.restoreFocus($0) },
            postCommandC: { await spy.post($0) },
            frontmostTimeoutNanoseconds: 0,
            activationSettleNanoseconds: 100_000_000,
            copySettleNanoseconds: 0
        )

        await action.copyActivatingTarget(777)

        let recorded = await spy.recorded()
        XCTAssertEqual(recorded.activations, [777])
        XCTAssertTrue(recorded.posts.isEmpty, "Cmd+C non inviato a un'app non più in primo piano")
        XCTAssertEqual(recorded.restores, [4242], "Il focus va ripristinato")
    }

    func testSystemActionPostsOnceAndRestoresFocusOnSuccess() async {
        let spy = ClipboardActionSpy(previousPID: 4242, frontmostPID: 777, activationSucceeds: true)
        let action = makeSystemCopyAction(spy)
        let targetPID: pid_t = 777

        await action.copyActivatingTarget(targetPID)

        let recorded = await spy.recorded()
        XCTAssertEqual(recorded.activations, [targetPID])
        XCTAssertEqual(recorded.posts.count, 1)
        XCTAssertNil(recorded.posts.first ?? nil, "Il Cmd+C di ripiego è globale")
        XCTAssertEqual(recorded.restores, [4242])
    }

    func testSystemActionDoesNotPostWhenCancelledDuringActivation() async {
        let spy = ClipboardActionSpy(previousPID: 4242, frontmostPID: 777, activationSucceeds: true)
        let action = SystemClipboardCopyAction(
            frontmostPID: { await spy.frontmost() },
            activate: { await spy.activate($0) },
            restoreFocus: { await spy.restoreFocus($0) },
            postCommandC: { await spy.post($0) },
            frontmostTimeoutNanoseconds: 0,
            activationSettleNanoseconds: 200_000_000,
            copySettleNanoseconds: 0
        )

        let task = Task { await action.copyActivatingTarget(777) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        await task.value

        let recorded = await spy.recorded()
        XCTAssertEqual(recorded.activations, [777])
        XCTAssertTrue(recorded.posts.isEmpty, "Nessun Cmd+C dopo la cancellazione")
        XCTAssertEqual(recorded.restores, [4242], "Il focus resta ripristinato")
    }

    func testSystemActionDoesNotPostWhenCancelledBeforeCopy() async {
        let spy = ClipboardActionSpy(previousPID: 4242, frontmostPID: 777, activationSucceeds: true)
        let action = makeSystemCopyAction(spy)

        // Il task si annulla da solo prima di raggiungere il post: il Cmd+C
        // non deve partire per una cattura già abbandonata.
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await action.copy(from: nil)
        }
        await task.value

        let recorded = await spy.recorded()
        XCTAssertTrue(recorded.posts.isEmpty, "Nessun Cmd+C da una cattura già annullata")
    }

    private func makeSystemCopyAction(_ spy: ClipboardActionSpy) -> SystemClipboardCopyAction {
        SystemClipboardCopyAction(
            frontmostPID: { await spy.frontmost() },
            activate: { await spy.activate($0) },
            restoreFocus: { await spy.restoreFocus($0) },
            postCommandC: { await spy.post($0) },
            frontmostTimeoutNanoseconds: 0,
            activationSettleNanoseconds: 0,
            copySettleNanoseconds: 0
        )
    }
}

// MARK: - Fake

/// Finta copia: scrive su un pasteboard dedicato senza eventi di sistema.
private actor FakeClipboardCopyAction: ClipboardCopyAction {
    static let nonTextType = NSPasteboard.PasteboardType("public.jpeg")
    private let pasteboard: ClipboardPasteboard
    private let copiedText: String?
    private let delayNanoseconds: UInt64
    private let copiesOnActivationOnly: Bool
    /// Quando valorizzato, `copy` pianifica la scrittura e torna subito: la
    /// copia atterra dopo un ritardo, come un'app lenta.
    private let asyncWriteDelayNanoseconds: UInt64?
    /// Copia in due fasi: `clearContents` immediato e testo dopo il ritardo.
    private let twoPhaseCopyDelayNanoseconds: UInt64?
    /// Contenuto copiato non testuale (immagine): nessuna stringa leggibile.
    private let nonTextData: Data?
    /// Copia dell'utente simulata: testo scritto e ritardo rispetto alla
    /// nostra copia.
    private let userWrite: (text: String, delayNanoseconds: UInt64)?
    private var activationPIDs: [pid_t] = []
    private var copyRequests: [pid_t?] = []
    private var pendingWrites: [Task<Void, Never>] = []

    init(
        pasteboard: ClipboardPasteboard,
        copiedText: String? = nil,
        delayNanoseconds: UInt64 = 0,
        copiesOnActivationOnly: Bool = false,
        asyncWriteDelayNanoseconds: UInt64? = nil,
        twoPhaseCopyDelayNanoseconds: UInt64? = nil,
        nonTextData: Data? = nil,
        userWrite: (text: String, delayNanoseconds: UInt64)? = nil
    ) {
        self.pasteboard = pasteboard
        self.copiedText = copiedText
        self.delayNanoseconds = delayNanoseconds
        self.copiesOnActivationOnly = copiesOnActivationOnly
        self.asyncWriteDelayNanoseconds = asyncWriteDelayNanoseconds
        self.twoPhaseCopyDelayNanoseconds = twoPhaseCopyDelayNanoseconds
        self.nonTextData = nonTextData
        self.userWrite = userWrite
    }

    func copy(from targetPID: pid_t?) async {
        copyRequests.append(targetPID)
        guard !copiesOnActivationOnly else { return }
        if let twoPhaseCopyDelayNanoseconds {
            let board = pasteboard.raw
            board.clearContents()
            startAsyncWrite(copiedText, after: twoPhaseCopyDelayNanoseconds)
        } else if let nonTextData {
            let board = pasteboard.raw
            board.clearContents()
            board.setData(nonTextData, forType: Self.nonTextType)
        } else if let asyncWriteDelayNanoseconds {
            startAsyncWrite(copiedText, after: asyncWriteDelayNanoseconds)
        } else {
            await writeCopiedText()
        }
        startUserWrite()
    }

    func copyActivatingTarget(_ targetPID: pid_t) async {
        activationPIDs.append(targetPID)
        await writeCopiedText()
        startUserWrite()
    }

    func recordedActivationPIDs() -> [pid_t] {
        activationPIDs
    }

    func recordedCopyRequests() -> [pid_t?] {
        copyRequests
    }

    func waitForPendingWrite() async {
        for write in pendingWrites {
            _ = await write.value
        }
    }

    private func startAsyncWrite(_ text: String?, after delay: UInt64) {
        guard let text else { return }
        let clipboard = pasteboard
        pendingWrites.append(Task {
            try? await Task.sleep(nanoseconds: delay)
            let board = clipboard.raw
            board.clearContents()
            board.setString(text, forType: .string)
        })
    }

    private func startUserWrite() {
        guard let userWrite else { return }
        let clipboard = pasteboard
        let text = userWrite.text
        let delay = userWrite.delayNanoseconds
        pendingWrites.append(Task {
            try? await Task.sleep(nanoseconds: delay)
            let board = clipboard.raw
            board.clearContents()
            board.setString(text, forType: .string)
        })
    }

    private func writeCopiedText() async {
        guard let copiedText else { return }
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        let board = pasteboard.raw
        board.clearContents()
        board.setString(copiedText, forType: .string)
    }
}

/// Provider promised che non materializza nulla: simula appunti con dati lazy
/// che non possono essere copiati nello snapshot.
private final class NilPasteboardDataProvider: NSObject, NSPasteboardItemDataProvider {
    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {}
}

/// Provider promised che fornisce solo il tipo `.string` pur promettendo anche
/// `.fileURL`: simula un item materializzato solo in parte.
private final class StringOnlyPasteboardDataProvider: NSObject, NSPasteboardItemDataProvider {
    private let text: String
    private let type: NSPasteboard.PasteboardType

    init(text: String, type: NSPasteboard.PasteboardType = .string) {
        self.text = text
        self.type = type
    }

    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType requestedType: NSPasteboard.PasteboardType
    ) {
        guard requestedType == type else { return }
        item.setString(text, forType: type)
    }
}

/// Spia per il percorso reale di `SystemClipboardCopyAction`: registra le
/// chiamate senza attivare app né postare eventi di sistema.
private actor ClipboardActionSpy {
    struct Recorded {
        var activations: [pid_t] = []
        var posts: [pid_t?] = []
        var restores: [pid_t] = []
    }

    private let previousPID: pid_t?
    private let frontmostPID: pid_t
    private let activationSucceeds: Bool
    /// Sequenza esplicita delle risposte di `frontmost()`, una per
    /// interrogazione (l'ultima si ripete). Vuota: comportamento storico.
    private let frontmostSequence: [pid_t?]
    private var frontmostQueries = 0
    private var log = Recorded()

    init(
        previousPID: pid_t?,
        frontmostPID: pid_t,
        activationSucceeds: Bool,
        frontmostSequence: [pid_t?] = []
    ) {
        self.previousPID = previousPID
        self.frontmostPID = frontmostPID
        self.activationSucceeds = activationSucceeds
        self.frontmostSequence = frontmostSequence
    }

    /// Prima interrogazione: l'app in primo piano prima dell'attivazione.
    /// Dopo: il valore configurato per il polling (o la sequenza esplicita).
    func frontmost() -> pid_t? {
        if !frontmostSequence.isEmpty {
            let index = min(frontmostQueries, frontmostSequence.count - 1)
            frontmostQueries += 1
            return frontmostSequence[index]
        }
        frontmostQueries += 1
        return frontmostQueries == 1 ? previousPID : frontmostPID
    }

    func activate(_ pid: pid_t) -> Bool {
        log.activations.append(pid)
        return activationSucceeds
    }

    func post(_ pid: pid_t?) {
        log.posts.append(pid)
    }

    func restoreFocus(_ pid: pid_t) {
        log.restores.append(pid)
    }

    func recorded() -> Recorded {
        log
    }
}

