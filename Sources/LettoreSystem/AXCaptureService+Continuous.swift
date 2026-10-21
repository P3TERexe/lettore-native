import Foundation
@preconcurrency import ApplicationServices
import CoreGraphics
import AppKit
import LettoreCore

/// Sessione AX aperta dalla lettura continua.
///
/// Gli elementi `AXUIElement` restano confinati all'attore: verso l'esterno
/// viaggiano solo stringhe e valori `Sendable`.
///
/// L'`id` identifica la sessione lungo gli `await`: se nel frattempo lo stop
/// ha chiamato `endContinuousCapture()` (o è partita una nuova sessione), le
/// fetch in sospeso non devono risuscitare lo stato vecchio.
struct ContinuousAXSession {
    let id: UUID
    let focusedElement: AXUIElement
    let scrollContainer: AXUIElement?
    let sourcePID: pid_t?
    let appName: String?
    let selectedText: String
    var capturedText: String
    var lastViewportText: String
    var lastScrollValue: Double?
    var canPage: Bool
    var reachedEnd: Bool
}

/// Attributi AX dei text marker (web area di Safari e affini).
///
/// I valori coincidono con `kAXStartTextMarkerAttribute` e con gli attributi
/// parametrici `AXIndexForTextMarker`/`AXLengthForTextMarkerRange` descritti
/// in `AXWebConstants.h`; sono definiti come stringhe locali per non
/// dipendere dalla versione dell'SDK usata in build. Il supporto effettivo
/// viene verificato a runtime: se l'attributo non è implementato la query
/// fallisce e si ripiega sul testo materializzato.
private enum AXMarkerAttribute {
    static let start = "AXStartTextMarker"
    static let end = "AXEndTextMarker"
    static let selectedRange = "AXSelectedTextMarkerRange"
    static let stringForRange = "AXStringForTextMarkerRange"
    static let indexForMarker = "AXIndexForTextMarker"
    static let lengthForRange = "AXLengthForTextMarkerRange"
    static let markerForIndex = "AXTextMarkerForIndex"
}

private struct ResolvedDocument {
    let text: String
    let anchorUTF16: Int
    let canPage: Bool
    let usedViewportSnapshot: Bool
    let viewportText: String
    let notice: String?
}

extension AXCaptureService: ContinuousTextSource {

    private static let safetyCharacterCap = 200_000
    private static let safetyCapNotice = "Il documento supera 200.000 caratteri: la lettura si ferma al limite di sicurezza."
    private static let pageLimitNotice = "Limite di 200.000 caratteri raggiunto: la lettura continua si ferma qui."

    // MARK: - Avvio

    public func startContinuousCapture() async -> ContinuousCaptureStart {
        await startContinuousCapture(targeting: nil)
    }

    public func startContinuousCapture(from applicationPID: pid_t) async -> ContinuousCaptureStart {
        await startContinuousCapture(targeting: applicationPID)
    }

    private func startContinuousCapture(targeting applicationPID: pid_t?) async -> ContinuousCaptureStart {
        await endContinuousCapture()

        if !AXIsProcessTrusted() {
            requestAccessibilityPrompt()
        }

        let appElement: AXUIElement
        if let applicationPID {
            appElement = AXUIElementCreateApplication(applicationPID)
        } else if let focusedApp = focusedApplication() {
            appElement = focusedApp
        } else {
            // Alcune app (editor PDF, Electron) non espongono nemmeno
            // l'applicazione focalizzata a livello di sistema. Se stiamo
            // leggendo l'app in primo piano, l'unica strada è Cmd+C: non
            // ruba il focus e permette almeno di leggere la selezione.
            let frontmostName = NSWorkspace.shared.frontmostApplication?.localizedName
            if let clipboard = await captureViaClipboardFallback(appName: frontmostName) {
                return ContinuousCaptureStart(
                    text: clipboard.text,
                    selectedText: clipboard.text,
                    sourceAppName: frontmostName,
                    canPage: false,
                    notice: "Continuazione non disponibile in questa app: letta solo la selezione."
                )
            }
            return ContinuousCaptureStart(
                text: "",
                selectedText: "",
                notice: "Nessuna applicazione in primo piano: impossibile avviare la lettura continua."
            )
        }

        let appName = applicationName(for: appElement)
        let sourcePID = processIdentifier(of: appElement)

        let focused: AXUIElement?
        if applicationPID != nil {
            focused = focusedElement(in: appElement)
        } else {
            focused = focusedElement()
        }

        guard let focused else {
            // Alcune app (per esempio editor PDF o app Electron) non espongono
            // il focused element via AX. Se stiamo leggendo l'app in primo piano
            // possiamo usare Cmd+C senza rubare il focus; con un PID esplicito
            // il fallback è vietato perché Cmd+C finirebbe nell'app sbagliata.
            if applicationPID == nil,
               let clipboard = await captureViaClipboardFallback(appName: appName) {
                return ContinuousCaptureStart(
                    text: clipboard.text,
                    selectedText: clipboard.text,
                    sourceAppName: appName,
                    canPage: false,
                    notice: "Continuazione non disponibile in questa app: letta solo la selezione."
                )
            }
            return ContinuousCaptureStart(
                text: "",
                selectedText: "",
                sourceAppName: appName,
                notice: "Nessun elemento focalizzato: seleziona del testo o posiziona il cursore e riprova."
            )
        }

        let selectedText = stringAttribute(focused, kAXSelectedTextAttribute as CFString) ?? ""
        let selectedRange = copySelectedRange(of: focused)
        let scrollContainer = nearestScrollContainer(from: focused)
        let numberOfCharacters = intAttribute(focused, kAXNumberOfCharactersAttribute as CFString)
        let focusedValue = stringAttribute(focused, kAXValueAttribute as CFString)

        print("[AXCapture][Continuo] app=\(appName ?? "?") role=\(role(of: focused) ?? "?") selezione=\(selectedText.count) valore=\(focusedValue?.count ?? 0) numberOfCharacters=\(numberOfCharacters.map(String.init) ?? "nil") scroll=\(scrollContainer != nil)")

        if let resolved = resolveDocument(
            focused: focused,
            selectedText: selectedText,
            selectedRange: selectedRange,
            scrollContainer: scrollContainer,
            numberOfCharacters: numberOfCharacters
        ) {
            let source = resolved.text as NSString
            let anchor = max(0, min(resolved.anchorUTF16, source.length))
            var text = source.substring(from: anchor)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            var notice = resolved.notice
            let safetyCap = Self.safetyCharacterCap
            if text.count > safetyCap {
                text = String(text.prefix(safetyCap))
                notice = Self.safetyCapNotice
            }

            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return selectionOnlyFallback(
                    selectedText: selectedText,
                    appName: appName,
                    notice: "Il punto di partenza non contiene testo leggibile. Seleziona del testo o sposta il cursore."
                )
            }

            let canPage = resolved.canPage
                && scrollContainer != nil
                && text.count < safetyCap

            print("[AXCapture][Continuo] risolto testo=\(resolved.text.count) anchor=\(anchor) canPage=\(resolved.canPage) snapshot=\(resolved.usedViewportSnapshot) output=\(text.count)")

            continuousSession = ContinuousAXSession(
                id: UUID(),
                focusedElement: focused,
                scrollContainer: scrollContainer,
                sourcePID: sourcePID,
                appName: appName,
                selectedText: selectedText,
                capturedText: text,
                lastViewportText: resolved.viewportText,
                lastScrollValue: scrollContainer.flatMap { scrollBarValue(of: $0) },
                canPage: canPage,
                reachedEnd: !canPage
            )

            return ContinuousCaptureStart(
                text: text,
                selectedText: selectedText,
                sourceAppName: appName,
                canPage: canPage,
                notice: notice
            )
        }

        // Ultima spiaggia: la vecchia cattura via clipboard copre le app che
        // non espongono né valore né range. Non può continuare, ma almeno
        // legge la selezione corrente. Con un PID esplicito il fallback è
        // vietato: Cmd+C finirebbe nell'app in primo piano (lo Studio), non
        // nell'app di origine.
        if applicationPID == nil,
           let clipboard = await captureViaClipboardFallback(appName: appName) {
            return ContinuousCaptureStart(
                text: clipboard.text,
                selectedText: clipboard.text,
                sourceAppName: appName,
                canPage: false,
                notice: "Continuazione non disponibile in questa app: letta solo la selezione."
            )
        }

        return selectionOnlyFallback(
            selectedText: selectedText,
            appName: appName,
            notice: "Continuazione non disponibile in questa app: seleziona del testo e riprova."
        )
    }

    // MARK: - Pagine successive

    public func nextContinuousPage() async -> ContinuousTextPage {
        guard !Task.isCancelled else { return .end }
        guard let local = continuousSession else { return .end }
        guard local.canPage, !local.reachedEnd, let container = local.scrollContainer else {
            return .end
        }

        guard AXIsProcessTrusted() else {
            return finishPage(
                ContinuousTextPage(
                    text: "",
                    isFinal: true,
                    notice: "Permesso Accessibilità revocato: la lettura continua si ferma qui."
                ),
                session: local
            )
        }

        // Una scroll bar con range non leggibile non significa "fine
        // documento": in Safari `value/min/max` restano a zero su documenti
        // lunghi. Solo un range valido con `value >= max` dichiara la fine;
        // negli altri casi si tenta comunque lo scroll AX (o PageDown).
        if scrollEndState(of: container) == .atEnd {
            return finishPage(.end, session: local)
        }

        let before = collectViewportText(from: container) ?? local.lastViewportText
        let attempt = scrollDownOneViewport(container)
        print("[AXCapture][Continuo] pagina before=\(before.count) attempt=\(String(describing: attempt)) atEnd=\(scrollEndState(of: container))")

        if case .unavailable = attempt {
            return finishPage(
                ContinuousTextPage(
                    text: "",
                    isFinal: true,
                    notice: "Questa app non espone un contenitore scorrevole: la lettura continua si ferma qui."
                ),
                session: local
            )
        }

        var after = await waitForViewportChange(container: container, before: before)
        guard isContinuousSessionCurrent(local) else { return .end }

        // Se lo scroll AX non ha prodotto un aggiornamento, l'unico fallback
        // sicuro è PageDown, e solo quando l'app di origine è già in primo
        // piano: non rubiamo mai il focus.
        if after == nil {
            let isFrontmost = await isSourceFrontmost(local)
            guard isContinuousSessionCurrent(local) else { return .end }

            if isFrontmost {
                print("[AXCapture][Continuo] fallback PageDown (app di origine in primo piano)")
                postPageDown()
                after = await waitForViewportChange(container: container, before: before)
                guard isContinuousSessionCurrent(local) else { return .end }
            }
        }

        guard let after, !after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if scrollEndState(of: container) == .atEnd {
                return finishPage(.end, session: local)
            }

            let isFrontmost = await isSourceFrontmost(local)
            guard isContinuousSessionCurrent(local) else { return .end }

            let notice = isFrontmost
                ? "Il documento non ha risposto allo scorrimento: la lettura continua si ferma qui."
                : "L'app di origine non è più in primo piano: non posso caricare altre pagine. Torna sull'app e riprova."
            return finishPage(
                ContinuousTextPage(text: "", isFinal: true, notice: notice),
                session: local
            )
        }

        let delta = DocumentPageOverlap.textAfterOverlap(before, after)
        print("[AXCapture][Continuo] dopo scroll after=\(after.count) delta=\(delta.count) atEnd=\(scrollEndState(of: container))")

        guard !delta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if scrollEndState(of: container) == .atEnd {
                return finishPage(.end, session: local)
            }
            return finishPage(
                ContinuousTextPage(
                    text: "",
                    isFinal: true,
                    notice: "La pagina successiva non contiene nuovo testo: la lettura continua si ferma qui."
                ),
                session: local
            )
        }

        let remaining = max(0, Self.safetyCharacterCap - local.capturedText.count)
        guard remaining > 0 else {
            return finishPage(
                ContinuousTextPage(text: "", isFinal: true, notice: Self.pageLimitNotice),
                session: local
            )
        }

        let pageText = String(delta.prefix(remaining))
        let hitSafetyCap = pageText.count < delta.count

        var updated = local
        updated.capturedText += pageText
        updated.lastViewportText = after
        updated.lastScrollValue = scrollBarValue(of: container)
        updated.reachedEnd = hitSafetyCap || scrollEndState(of: container) == .atEnd

        guard commitContinuousSession(updated) else { return .end }

        return ContinuousTextPage(
            text: pageText,
            isFinal: updated.reachedEnd,
            notice: hitSafetyCap ? Self.pageLimitNotice : nil
        )
    }

    /// Segna la sessione come conclusa senza scrivere se nel frattempo è stata
    /// chiusa o sostituita: una fetch sospesa non deve mai far risorgere la
    /// sessione AX vecchia.
    private func finishPage(
        _ page: ContinuousTextPage,
        session: ContinuousAXSession
    ) -> ContinuousTextPage {
        var updated = session
        updated.reachedEnd = true
        guard commitContinuousSession(updated) else { return .end }
        return page
    }

    /// Scrive la sessione aggiornata solo se è ancora quella attiva e il task
    /// non è stato cancellato.
    private func commitContinuousSession(_ updated: ContinuousAXSession) -> Bool {
        guard !Task.isCancelled, continuousSession?.id == updated.id else { return false }
        continuousSession = updated
        return true
    }

    private func isContinuousSessionCurrent(_ session: ContinuousAXSession) -> Bool {
        continuousSession?.id == session.id && !Task.isCancelled
    }

    public func endContinuousCapture() async {
        continuousSession = nil
    }

    // MARK: - Risoluzione del documento

    private func resolveDocument(
        focused: AXUIElement,
        selectedText: String,
        selectedRange: CFRange?,
        scrollContainer: AXUIElement?,
        numberOfCharacters: Int?
    ) -> ResolvedDocument? {
        let focusedValue = stringAttribute(focused, kAXValueAttribute as CFString)
        let focusedLength = focusedValue.map { ($0 as NSString).length }

        // 1. L'elemento focalizzato espone sia il valore sia il range: è il
        // caso dei campi di testo e degli editor che mantengono il documento
        // completo nell'AXValue.
        if let value = focusedValue, let range = selectedRange, let length = focusedLength {
            let end = range.location + range.length
            if range.location >= 0, end <= length {
                let isFragment = numberOfCharacters.map { $0 > length } ?? false

                if isFragment,
                   let container = scrollContainer,
                   let snapshot = collectViewportText(from: container),
                   let anchor = anchorOffset(
                       in: snapshot,
                       selectedText: selectedText,
                       focusedValue: value,
                       range: range
                   ) {
                    return ResolvedDocument(
                        text: snapshot,
                        anchorUTF16: anchor,
                        canPage: scrollEndState(of: container) != .atEnd,
                        usedViewportSnapshot: true,
                        viewportText: snapshot,
                        notice: nil
                    )
                }

                return ResolvedDocument(
                    text: value,
                    anchorUTF16: max(0, Int(range.location)),
                    canPage: false,
                    usedViewportSnapshot: false,
                    viewportText: value,
                    notice: isFragment
                        ? "Non riesco a mappare il cursore nel documento: leggo solo l'elemento selezionato."
                        : nil
                )
            }
        }

        // 2. Web area / testo con marcatori (Safari): `AXValue` è assente, ma
        // il contenitore espone AXStartTextMarker/AXEndTextMarker e gli
        // attributi parametrici danno il testo completo. Va provato prima del
        // walk sugli antenati: un `AXValue` parziale su un antenato non deve
        // vincere sul documento completo esposto dai marker.
        if let resolved = resolveTextMarkerDocument(
            from: focused,
            scrollContainer: scrollContainer,
            selectedText: selectedText
        ) {
            return resolved
        }

        // 2.5. Il valore è su un antenato (es. contenitore web) mentre il
        // range resta sull'elemento focalizzato.
        if let resolved = resolveInAncestors(
            from: focused,
            selectedText: selectedText,
            selectedRange: selectedRange
        ) {
            return resolved
        }

        // 3. Documento virtualizzato: ricostruisce la viewport con una DFS e
        // ancora la selezione/cursore al testo visibile.
        if let container = scrollContainer,
           let snapshot = collectViewportText(from: container) {
            if let anchor = anchorOffset(
                in: snapshot,
                selectedText: selectedText,
                focusedValue: focusedValue,
                range: selectedRange
            ) {
                return ResolvedDocument(
                    text: snapshot,
                    anchorUTF16: anchor,
                    canPage: scrollEndState(of: container) != .atEnd,
                    usedViewportSnapshot: true,
                    viewportText: snapshot,
                    notice: nil
                )
            }

            // Ancoraggio non mappabile: non leggiamo l'intera viewport da una
            // posizione arbitraria. Meglio il solo elemento focalizzato, con
            // un avviso esplicito.
            if let value = focusedValue, !value.isEmpty {
                let offset = max(0, Int(selectedRange?.location ?? 0))
                return ResolvedDocument(
                    text: value,
                    anchorUTF16: min(offset, (value as NSString).length),
                    canPage: false,
                    usedViewportSnapshot: false,
                    viewportText: value,
                    notice: "Non riesco a mappare il cursore nel documento: leggo solo l'elemento selezionato."
                )
            }
        }

        // 4. Valore senza range utilizzabile: prova almeno ad ancorare la
        // selezione nel valore; altrimenti si parte dall'inizio.
        if let value = focusedValue, !value.isEmpty {
            let length = (value as NSString).length
            let trimmedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)

            let anchor: Int
            let notice: String?
            if !trimmedSelection.isEmpty,
               let found = anchorOffset(in: value, for: trimmedSelection) {
                anchor = found
                notice = nil
            } else if let range = selectedRange,
                      range.location >= 0,
                      Int(range.location) <= length {
                anchor = Int(range.location)
                notice = trimmedSelection.isEmpty
                    ? "Cursore non disponibile: lettura dall'inizio dell'elemento."
                    : nil
            } else {
                anchor = 0
                notice = trimmedSelection.isEmpty
                    ? "Cursore non disponibile: lettura dall'inizio dell'elemento."
                    : "Non riesco a mappare la selezione: lettura dall'inizio dell'elemento."
            }

            return ResolvedDocument(
                text: value,
                anchorUTF16: min(anchor, length),
                canPage: false,
                usedViewportSnapshot: false,
                viewportText: value,
                notice: notice
            )
        }

        return nil
    }

    /// Risolve i contenitori basati su `AXTextMarker` (Safari e alcune web
    /// view) senza dipendere da `AXValue`.
    ///
    /// Quando la selezione (o il cursore) è disponibile si chiede subito il
    /// range `selectionStart → endMarker`: il documento intero non viene
    /// materializzato solo per scartarne la testa. `AXLengthForTextMarkerRange`
    /// e `AXIndexForTextMarker` (UTF-16), quando l'app li supporta, validano il
    /// limite di sicurezza prima di costruire la stringa; se la query fallisce
    /// si ripiega esplicitamente sulla stringa del range completo.
    private func resolveTextMarkerDocument(
        from focused: AXUIElement,
        scrollContainer: AXUIElement?,
        selectedText: String
    ) -> ResolvedDocument? {
        guard let container = nearestTextMarkerContainer(from: focused, fallback: scrollContainer),
              let documentStart = textMarkerAttribute(container, AXMarkerAttribute.start),
              let documentEnd = textMarkerAttribute(container, AXMarkerAttribute.end) else {
            return nil
        }

        let documentRange = textMarkerRange(from: documentStart, to: documentEnd)
        let documentLength = documentRange.flatMap { textMarkerRangeLength(of: $0, in: container) }

        // La selezione può stare su un nodo intermedio, non solo
        // sull'elemento focalizzato: risali fino al contenitore dei marker.
        let selectionRange = selectedTextMarkerRange(from: focused, in: container)
        if let selectionStart = selectionRange.flatMap(copyStartMarker),
           let resolved = resolveMarkedRange(
               container: container,
               from: selectionStart,
               to: documentEnd,
               documentLength: documentLength
           ) {
            return resolved
        }

        // Senza marker di selezione utilizzabili si ripiega sul documento
        // completo, provando prima ad ancorare la selezione testuale.
        return resolveTextMarkerFallback(
            container: container,
            documentStart: documentStart,
            documentEnd: documentEnd,
            selectedText: selectedText
        )
    }

    /// Chiede direttamente il testo da `selectionStart` alla fine del documento
    /// e, quando le API di indicizzazione dei marker sono disponibili, costruisce
    /// un range già troncato al limite di sicurezza prima di materializzarlo.
    private func resolveMarkedRange(
        container: AXUIElement,
        from selectionStart: AXTextMarker,
        to documentEnd: AXTextMarker,
        documentLength: Int?
    ) -> ResolvedDocument? {
        let selectionIndex = textMarkerIndex(of: selectionStart, in: container).flatMap { index -> Int? in
            guard index >= 0 else { return nil }
            if let documentLength, index > documentLength { return nil }
            return index
        }

        if let selectionIndex,
           let documentLength,
           documentLength - selectionIndex > Self.safetyCharacterCap,
           let cappedEnd = textMarker(atIndex: selectionIndex + Self.safetyCharacterCap, in: container),
           let cappedRange = textMarkerRange(from: selectionStart, to: cappedEnd),
           let cappedText = parameterizedString(container, AXMarkerAttribute.stringForRange, cappedRange) {
            return ResolvedDocument(
                text: cappedText,
                anchorUTF16: 0,
                canPage: false,
                usedViewportSnapshot: false,
                viewportText: cappedText,
                notice: Self.safetyCapNotice
            )
        }

        guard let anchoredRange = textMarkerRange(from: selectionStart, to: documentEnd),
              let text = parameterizedString(container, AXMarkerAttribute.stringForRange, anchoredRange) else {
            return nil
        }

        // Sanity check: l'ancora più il testo ancorato non possono superare la
        // lunghezza del documento. Se i marker sono incoerenti si preferisce
        // il fallback testuale al testo arbitrario.
        if let selectionIndex,
           let documentLength,
           selectionIndex + (text as NSString).length > documentLength {
            print("[AXCapture][Continuo] marker incoerenti: range più lungo del documento")
            return nil
        }

        return ResolvedDocument(
            text: text,
            anchorUTF16: 0,
            canPage: false,
            usedViewportSnapshot: false,
            viewportText: text,
            notice: nil
        )
    }

    /// Fallback quando `AXSelectedTextMarkerRange` manca o non è utilizzabile:
    /// materializza il documento completo e ancora la selezione testuale già
    /// disponibile prima di ripiegare sull'inizio.
    private func resolveTextMarkerFallback(
        container: AXUIElement,
        documentStart: AXTextMarker,
        documentEnd: AXTextMarker,
        selectedText: String
    ) -> ResolvedDocument? {
        guard let fullRange = textMarkerRange(from: documentStart, to: documentEnd),
              let fullText = parameterizedString(container, AXMarkerAttribute.stringForRange, fullRange),
              !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let trimmedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let length = (fullText as NSString).length
        let anchor: Int
        let notice: String?

        if !trimmedSelection.isEmpty, let found = anchorOffset(in: fullText, for: trimmedSelection) {
            anchor = found
            notice = nil
        } else if trimmedSelection.isEmpty {
            anchor = 0
            notice = "Cursore non disponibile: lettura dall'inizio del documento."
        } else {
            anchor = 0
            notice = "Non riesco a mappare la selezione nel documento: lettura dall'inizio."
        }

        return ResolvedDocument(
            text: fullText,
            anchorUTF16: max(0, min(anchor, length)),
            canPage: false,
            usedViewportSnapshot: false,
            viewportText: fullText,
            notice: notice
        )
    }

    private func nearestTextMarkerContainer(
        from element: AXUIElement,
        fallback: AXUIElement?
    ) -> AXUIElement? {
        var current: AXUIElement? = element
        var depth = 0

        while let node = current, depth < 12 {
            if hasTextMarkers(node) { return node }
            current = elementAttribute(node, kAXParentAttribute as CFString)
            depth += 1
        }

        // Il walk può fermarsi prima della web area: ripiega sul contenitore
        // scorrevole e, se serve, sui suoi antenati.
        current = fallback
        depth = 0
        while let node = current, depth < 25 {
            if hasTextMarkers(node) { return node }
            current = elementAttribute(node, kAXParentAttribute as CFString)
            depth += 1
        }

        return nil
    }

    private func hasTextMarkers(_ element: AXUIElement) -> Bool {
        textMarkerAttribute(element, AXMarkerAttribute.start) != nil
            && textMarkerAttribute(element, AXMarkerAttribute.end) != nil
    }

    /// Cerca `AXSelectedTextMarkerRange` risalendo tutti gli antenati fino al
    /// contenitore dei marker: in Safari l'attributo è sulla web area, ma
    /// altre web view lo espongono su nodi intermedi.
    private func selectedTextMarkerRange(
        from element: AXUIElement,
        in container: AXUIElement
    ) -> AXTextMarkerRange? {
        var current: AXUIElement? = element
        var depth = 0

        while let node = current, depth < 25 {
            if let range = textMarkerRangeAttribute(node, AXMarkerAttribute.selectedRange) {
                return range
            }
            if CFEqual(node, container) { break }
            if hasTextMarkers(node) { break }
            if role(of: node) == "AXWindow" { break }
            current = elementAttribute(node, kAXParentAttribute as CFString)
            depth += 1
        }

        return textMarkerRangeAttribute(container, AXMarkerAttribute.selectedRange)
    }

    /// `AXTextMarkerRangeCreate` è importata come non-opzionale: il range
    /// viene rivalidato per tipo prima di essere passato alle query. Se la
    /// validazione fallisce i chiamanti ripiegano sul testo materializzato.
    private func textMarkerRange(from start: AXTextMarker, to end: AXTextMarker) -> AXTextMarkerRange? {
        let range = AXTextMarkerRangeCreate(nil, start, end)
        guard CFGetTypeID(range) == AXTextMarkerRangeGetTypeID() else { return nil }
        return range
    }

    /// Anche `AXTextMarkerRangeCopyStartMarker` è non-opzionale: il marker
    /// restituito viene validato per tipo.
    private func copyStartMarker(of range: AXTextMarkerRange) -> AXTextMarker? {
        let marker = AXTextMarkerRangeCopyStartMarker(range)
        guard CFGetTypeID(marker) == AXTextMarkerGetTypeID() else { return nil }
        return marker
    }

    private func textMarkerIndex(of marker: AXTextMarker, in container: AXUIElement) -> Int? {
        parameterizedNumber(container, AXMarkerAttribute.indexForMarker, parameter: marker)
    }

    private func textMarkerRangeLength(of range: AXTextMarkerRange, in container: AXUIElement) -> Int? {
        parameterizedNumber(container, AXMarkerAttribute.lengthForRange, parameter: range)
    }

    private func textMarker(atIndex index: Int, in container: AXUIElement) -> AXTextMarker? {
        var value: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            container,
            AXMarkerAttribute.markerForIndex as CFString,
            NSNumber(value: index),
            &value
        ) == .success,
        let candidate = value,
        CFGetTypeID(candidate) == AXTextMarkerGetTypeID() else {
            return nil
        }
        return (candidate as! AXTextMarker)
    }

    private func parameterizedNumber(
        _ element: AXUIElement,
        _ name: String,
        parameter: AnyObject
    ) -> Int? {
        var value: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, parameter, &value) == .success else {
            return nil
        }
        if let number = value as? NSNumber { return number.intValue }
        if let number = value as? Int { return number }
        return nil
    }

    private func textMarkerAttribute(_ element: AXUIElement, _ name: String) -> AXTextMarker? {
        guard let value = copyAttribute(element, name as CFString),
              CFGetTypeID(value) == AXTextMarkerGetTypeID() else {
            return nil
        }
        return (value as! AXTextMarker)
    }

    private func textMarkerRangeAttribute(
        _ element: AXUIElement,
        _ name: String
    ) -> AXTextMarkerRange? {
        guard let value = copyAttribute(element, name as CFString),
              CFGetTypeID(value) == AXTextMarkerRangeGetTypeID() else {
            return nil
        }
        return (value as! AXTextMarkerRange)
    }

    private func parameterizedString(
        _ element: AXUIElement,
        _ name: String,
        _ parameter: AnyObject
    ) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            name as CFString,
            parameter,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }

    private func resolveInAncestors(
        from focused: AXUIElement,
        selectedText: String,
        selectedRange: CFRange?
    ) -> ResolvedDocument? {
        var current = elementAttribute(focused, kAXParentAttribute as CFString)
        var depth = 0

        while let node = current, depth < 12 {
            defer {
                current = elementAttribute(node, kAXParentAttribute as CFString)
                depth += 1
            }

            if role(of: node) == "AXWindow" { break }

            guard let value = stringAttribute(node, kAXValueAttribute as CFString),
                  !value.isEmpty else { continue }

            let nsValue = value as NSString

            if let range = selectedRange,
               range.location >= 0,
               range.length > 0,
               range.location + range.length <= nsValue.length {
                let selected = nsValue.substring(
                    with: NSRange(location: range.location, length: range.length)
                )
                let lhs = selected.trimmingCharacters(in: .whitespacesAndNewlines)
                let rhs = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if rhs.isEmpty || lhs == rhs {
                    return ResolvedDocument(
                        text: value,
                        anchorUTF16: range.location,
                        canPage: false,
                        usedViewportSnapshot: false,
                        viewportText: value,
                        notice: nil
                    )
                }
            }

            if !selectedText.isEmpty,
               let anchor = anchorOffset(in: value, for: selectedText) {
                return ResolvedDocument(
                    text: value,
                    anchorUTF16: anchor,
                    canPage: false,
                    usedViewportSnapshot: false,
                    viewportText: value,
                    notice: nil
                )
            }
        }

        return nil
    }

    private func anchorOffset(
        in snapshot: String,
        selectedText: String,
        focusedValue: String?,
        range: CFRange?
    ) -> Int? {
        if !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return anchorOffset(in: snapshot, for: selectedText)
        }

        guard let focusedValue, !focusedValue.isEmpty, let range else {
            return nil
        }

        guard let base = anchorOffset(in: snapshot, for: focusedValue) else {
            return nil
        }

        let length = (focusedValue as NSString).length
        let caret = max(0, Int(range.location))
        guard caret <= length else { return base }
        return base + caret
    }

    private func anchorOffset(in text: String, for needle: String) -> Int? {
        let trimmed = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let nsText = text as NSString
        var range = nsText.range(of: trimmed)
        if range.location == NSNotFound {
            range = nsText.range(of: trimmed, options: [.caseInsensitive])
        }

        return range.location == NSNotFound ? nil : range.location
    }

    private func selectionOnlyFallback(
        selectedText: String,
        appName: String?,
        notice: String
    ) -> ContinuousCaptureStart {
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ContinuousCaptureStart(
                text: "",
                selectedText: selectedText,
                sourceAppName: appName,
                canPage: false,
                notice: notice
            )
        }

        return ContinuousCaptureStart(
            text: trimmed,
            selectedText: selectedText,
            sourceAppName: appName,
            canPage: false,
            notice: "Continuazione non disponibile in questa app: letta solo la selezione."
        )
    }

    // MARK: - Scrolling

    private enum ScrollAttempt {
        case performedAX
        case needsFallback
        case unavailable
    }

    private func scrollDownOneViewport(_ container: AXUIElement) -> ScrollAttempt {
        let bar = elementAttribute(container, kAXVerticalScrollBarAttribute as CFString)

        for target in [container, bar].compactMap({ $0 }) {
            var namesValue: CFArray?
            guard AXUIElementCopyActionNames(target, &namesValue) == .success,
                  let names = namesValue as? [String] else { continue }

            print("[AXCapture][Continuo] azioni AX su \(role(of: target) ?? "?"): \(names)")

            for name in ["AXScrollDownByPage", "AXScrollDown", "AXPageDown"] where names.contains(name) {
                if AXUIElementPerformAction(target, name as CFString) == .success {
                    return .performedAX
                }
            }
        }

        guard let bar else { return .unavailable }
        guard let state = scrollBarState(of: bar), state.max > state.min else {
            return .needsFallback
        }

        // Se la scroll bar espone l'incremento di riga, prova a impostare un
        // avanzamento di circa una pagina senza generare eventi di tastiera.
        if let increment = doubleAttribute(bar, "AXValueIncrement" as CFString), increment > 0 {
            let step = min(state.max - state.min, increment * 20)
            let target = min(state.max, state.value + step)

            if target > state.value + 0.000_001 {
                let result = AXUIElementSetAttributeValue(
                    bar,
                    kAXValueAttribute as CFString,
                    NSNumber(value: target)
                )
                if result == .success {
                    return .performedAX
                }
            }
        }

        return .needsFallback
    }

    @discardableResult
    private func postPageDown() -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 121, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 121, keyDown: false) else {
            return false
        }

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private func waitForViewportChange(
        container: AXUIElement,
        before: String,
        attempts: Int = 14
    ) async -> String? {
        for _ in 0..<attempts {
            if Task.isCancelled { return nil }
            try? await Task.sleep(nanoseconds: 50_000_000)
            if Task.isCancelled { return nil }
            if let after = collectViewportText(from: container),
               after != before,
               !after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return after
            }
        }
        return nil
    }

    private func isSourceFrontmost(_ session: ContinuousAXSession) async -> Bool {
        guard let sourcePID = session.sourcePID else { return false }
        let frontmost = await MainActor.run {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
        return frontmost == sourcePID
    }

    /// Esito della lettura della scroll bar verticale.
    ///
    /// `unknown` copre sia l'assenza della scroll bar sia un range non
    /// leggibile (in Safari `value/min/max` restano a zero su documenti
    /// lunghi): non è una prova di fine documento e obbliga a tentare lo
    /// scroll.
    private enum ScrollEndState {
        case atEnd
        case notAtEnd
        case unknown
    }

    private func scrollEndState(of container: AXUIElement) -> ScrollEndState {
        guard let bar = elementAttribute(container, kAXVerticalScrollBarAttribute as CFString),
              let state = scrollBarState(of: bar) else {
            return .unknown
        }

        // Range nullo o non disponibile: la barra non dice se c'è altro testo
        // sotto la viewport, quindi si tenta comunque lo scroll.
        guard state.max > state.min else { return .unknown }

        let epsilon = max(0.000_1, (state.max - state.min) * 0.001)
        return state.value >= state.max - epsilon ? .atEnd : .notAtEnd
    }

    private func scrollBarValue(of container: AXUIElement) -> Double? {
        guard let bar = elementAttribute(container, kAXVerticalScrollBarAttribute as CFString) else {
            return nil
        }
        return doubleAttribute(bar, kAXValueAttribute as CFString)
    }

    private func scrollBarState(of bar: AXUIElement) -> (value: Double, min: Double, max: Double)? {
        guard let value = doubleAttribute(bar, kAXValueAttribute as CFString),
              let minValue = doubleAttribute(bar, kAXMinValueAttribute as CFString),
              let maxValue = doubleAttribute(bar, kAXMaxValueAttribute as CFString) else {
            return nil
        }
        return (value, minValue, maxValue)
    }

    // MARK: - Raccolta del testo visibile

    private func collectViewportText(from root: AXUIElement) -> String? {
        var blocks: [String] = []
        var seenKeys = Set<String>()
        var visited = Set<CFHashCode>()
        var totalCharacters = 0

        func normalizedKey(_ text: String) -> String {
            text
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }

        func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 40, totalCharacters < 200_000 else { return }

            let hash = CFHash(element)
            guard visited.insert(hash).inserted else { return }

            let elementRole = role(of: element) ?? ""
            if Self.skippedRoles.contains(elementRole) { return }

            if Self.textRoles.contains(elementRole),
               let value = stringAttribute(element, kAXValueAttribute as CFString) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty,
                   !Self.isURL(trimmed),
                   !Self.isOnlyListMarker(trimmed) {
                    let key = normalizedKey(trimmed)
                    if !key.isEmpty, seenKeys.insert(key).inserted {
                        blocks.append(trimmed)
                        totalCharacters += trimmed.count
                    }
                    // Il valore di un contenitore di testo include già i
                    // discendenti: non ricorrere per evitare duplicati.
                    return
                }
            }

            for child in children(of: element) {
                walk(child, depth: depth + 1)
            }
        }

        walk(root, depth: 0)

        let joined = blocks.joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    private static let textRoles: Set<String> = [
        "AXStaticText",
        "AXHeading",
        "AXTextArea",
        "AXTextField",
        "AXWebArea",
        "AXCell",
        "AXRow",
        "AXListItem",
        "AXParagraph"
    ]

    private static let skippedRoles: Set<String> = [
        "AXButton",
        "AXCheckBox",
        "AXRadioButton",
        "AXPopUpButton",
        "AXMenuItem",
        "AXMenuBar",
        "AXMenu",
        "AXToolbar",
        "AXScrollBar",
        "AXSlider",
        "AXImage",
        "AXTabGroup",
        "AXTab",
        "AXComboBox",
        "AXDisclosureTriangle",
        "AXProgressIndicator",
        "AXColorWell",
        "AXSplitter",
        "AXGrowArea",
        "AXRuler",
        "AXRulerMarker"
    ]

    private static func isURL(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasPrefix("http://")
            || lower.hasPrefix("https://")
            || lower.hasPrefix("file://")
    }

    private static func isOnlyListMarker(_ text: String) -> Bool {
        guard text.count <= 2 else { return false }
        return text.allSatisfy { "•◦▪‣-–—·".contains($0) }
    }

    // MARK: - Attributi AX

    private func focusedApplication() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        return elementAttribute(systemWide, kAXFocusedApplicationAttribute as CFString)
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        return elementAttribute(systemWide, kAXFocusedUIElementAttribute as CFString)
    }

    /// Elemento focalizzato nell'app target. Quando l'app non espone il
    /// focused element si prova con la finestra focalizzata e poi con quella
    /// principale, così la cattura resta confinata all'app indicata.
    private func focusedElement(in application: AXUIElement) -> AXUIElement? {
        let attributes = [
            kAXFocusedUIElementAttribute,
            kAXFocusedWindowAttribute,
            kAXMainWindowAttribute
        ]

        for attribute in attributes {
            if let element = elementAttribute(application, attribute as CFString) {
                return element
            }
        }

        return nil
    }

    private func applicationName(for appElement: AXUIElement) -> String? {
        if let title = stringAttribute(appElement, kAXTitleAttribute as CFString), !title.isEmpty {
            return title
        }
        guard let pid = processIdentifier(of: appElement) else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    private func processIdentifier(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }

    private func nearestScrollContainer(from element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        var firstScrollArea: AXUIElement?
        var depth = 0

        while let node = current, depth < 25 {
            let elementRole = role(of: node) ?? ""
            let hasVerticalBar = elementAttribute(
                node,
                kAXVerticalScrollBarAttribute as CFString
            ) != nil

            if elementRole == "AXScrollArea" || hasVerticalBar {
                if firstScrollArea == nil {
                    firstScrollArea = node
                }
                if hasVerticalBar {
                    return node
                }
            }

            current = elementAttribute(node, kAXParentAttribute as CFString)
            depth += 1
        }

        return firstScrollArea
    }

    private func role(of element: AXUIElement) -> String? {
        stringAttribute(element, kAXRoleAttribute as CFString)
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        guard let value = copyAttribute(element, kAXChildrenAttribute as CFString) else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        copyAttribute(element, attribute) as? String
    }

    private func intAttribute(_ element: AXUIElement, _ attribute: CFString) -> Int? {
        guard let value = copyAttribute(element, attribute) else { return nil }
        if let number = value as? NSNumber { return number.intValue }
        if let int = value as? Int { return int }
        return nil
    }

    private func doubleAttribute(_ element: AXUIElement, _ attribute: CFString) -> Double? {
        guard let value = copyAttribute(element, attribute) else { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        if let double = value as? Double { return double }
        return nil
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        guard let value = copyAttribute(element, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func copySelectedRange(of element: AXUIElement) -> CFRange? {
        guard let value = copyAttribute(element, kAXSelectedTextRangeAttribute as CFString),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    private func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        return value
    }
}

extension AXCaptureService: TargetedContinuousTextSource {}
