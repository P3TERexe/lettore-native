import Foundation
@preconcurrency import ApplicationServices
import CoreGraphics
import AppKit
import LettoreCore

/// Sessione AX aperta dalla lettura continua.
///
/// Gli elementi `AXUIElement` restano confinati all'attore: verso l'esterno
/// viaggiano solo stringhe e valori `Sendable`.
struct ContinuousAXSession {
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

private struct ResolvedDocument {
    let text: String
    let anchorUTF16: Int
    let canPage: Bool
    let usedViewportSnapshot: Bool
    let viewportText: String
    let notice: String?
}

extension AXCaptureService: ContinuousTextSource {

    // MARK: - Avvio

    public func startContinuousCapture() async -> ContinuousCaptureStart {
        await endContinuousCapture()

        if !AXIsProcessTrusted() {
            requestAccessibilityPrompt()
        }

        guard let appElement = focusedApplication() else {
            return ContinuousCaptureStart(
                text: "",
                selectedText: "",
                notice: "Nessuna applicazione in primo piano: impossibile avviare la lettura continua."
            )
        }

        let appName = applicationName(for: appElement)
        let sourcePID = processIdentifier(of: appElement)

        guard let focused = focusedElement() else {
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
            let safetyCap = 200_000
            if text.count > safetyCap {
                text = String(text.prefix(safetyCap))
                notice = "Il documento supera 200.000 caratteri: la lettura si ferma al limite di sicurezza."
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
        // legge la selezione corrente.
        if let clipboard = await captureViaClipboardFallback(appName: appName) {
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
        guard var session = continuousSession else { return .end }
        guard session.canPage, !session.reachedEnd, let container = session.scrollContainer else {
            return .end
        }

        guard AXIsProcessTrusted() else {
            session.reachedEnd = true
            continuousSession = session
            return ContinuousTextPage(
                text: "",
                isFinal: true,
                notice: "Permesso Accessibilità revocato: la lettura continua si ferma qui."
            )
        }

        if isScrollAtEnd(container) {
            session.reachedEnd = true
            continuousSession = session
            return .end
        }

        let before = collectViewportText(from: container) ?? session.lastViewportText
        let attempt = scrollDownOneViewport(container)
        print("[AXCapture][Continuo] pagina before=\(before.count) attempt=\(String(describing: attempt)) atEnd=\(isScrollAtEnd(container))")

        if case .unavailable = attempt {
            session.reachedEnd = true
            continuousSession = session
            return ContinuousTextPage(
                text: "",
                isFinal: true,
                notice: "Questa app non espone un contenitore scorrevole: la lettura continua si ferma qui."
            )
        }

        var after = await waitForViewportChange(container: container, before: before)

        // Se lo scroll AX non ha prodotto un aggiornamento, l'unico fallback
        // sicuro è PageDown, e solo quando l'app di origine è già in primo
        // piano: non rubiamo mai il focus.
        if after == nil {
            let isFrontmost = await isSourceFrontmost(session)
            if isFrontmost {
                print("[AXCapture][Continuo] fallback PageDown (app di origine in primo piano)")
                postPageDown()
                after = await waitForViewportChange(container: container, before: before)
            }
        }

        guard let after, !after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            session.reachedEnd = true
            continuousSession = session

            if isScrollAtEnd(container) {
                return .end
            }

            let isFrontmost = await isSourceFrontmost(session)
            let notice = isFrontmost
                ? "Il documento non ha risposto allo scorrimento: la lettura continua si ferma qui."
                : "L'app di origine non è più in primo piano: non posso caricare altre pagine. Torna sull'app e riprova."
            return ContinuousTextPage(text: "", isFinal: true, notice: notice)
        }

        let delta = textAfterOverlap(old: before, new: after)
        session.lastViewportText = after
        session.lastScrollValue = scrollBarValue(of: container)
        print("[AXCapture][Continuo] dopo scroll after=\(after.count) delta=\(delta.count) atEnd=\(isScrollAtEnd(container))")

        guard !delta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            session.reachedEnd = true
            continuousSession = session
            if isScrollAtEnd(container) {
                return .end
            }
            return ContinuousTextPage(
                text: "",
                isFinal: true,
                notice: "La pagina successiva non contiene nuovo testo: la lettura continua si ferma qui."
            )
        }

        let remaining = max(0, 200_000 - session.capturedText.count)
        guard remaining > 0 else {
            session.reachedEnd = true
            continuousSession = session
            return ContinuousTextPage(
                text: "",
                isFinal: true,
                notice: "Limite di 200.000 caratteri raggiunto: la lettura continua si ferma qui."
            )
        }

        let pageText = String(delta.prefix(remaining))
        let hitSafetyCap = pageText.count < delta.count
        session.capturedText += pageText
        session.reachedEnd = hitSafetyCap || isScrollAtEnd(container)
        continuousSession = session

        return ContinuousTextPage(
            text: pageText,
            isFinal: session.reachedEnd,
            notice: hitSafetyCap ? "Limite di 200.000 caratteri raggiunto: la lettura continua si ferma qui." : nil
        )
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
                        canPage: !isScrollAtEnd(container),
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

        // 2. Il valore è su un antenato (es. contenitore web) mentre il range
        // resta sull'elemento focalizzato.
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
                    canPage: !isScrollAtEnd(container),
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
            try? await Task.sleep(nanoseconds: 50_000_000)
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

    private func isScrollAtEnd(_ container: AXUIElement) -> Bool {
        guard let bar = elementAttribute(container, kAXVerticalScrollBarAttribute as CFString),
              let state = scrollBarState(of: bar) else {
            return false
        }

        // Una scroll bar con range nullo significa che non c'è altro testo
        // sotto la viewport corrente: non serve paginare.
        guard state.max > state.min else { return true }

        let epsilon = max(0.000_1, (state.max - state.min) * 0.001)
        return state.value >= state.max - epsilon
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

    /// Rimuove dalla nuova viewport la parte già vista, usando il più lungo
    /// suffisso della vecchia viewport che coincide con un prefisso della nuova.
    private func textAfterOverlap(old: String, new: String, maxOverlap: Int = 4_000) -> String {
        guard !new.isEmpty else { return "" }
        guard !old.isEmpty else { return new }

        let oldLength = (old as NSString).length
        let newLength = (new as NSString).length
        let limit = min(maxOverlap, min(oldLength, newLength))
        guard limit > 0 else { return new }

        let oldTail = (old as NSString).substring(from: oldLength - limit) as NSString
        let newHead = (new as NSString).substring(to: limit) as NSString
        var overlap = min(oldTail.length, newHead.length)

        while overlap > 0 {
            let oldSuffix = oldTail.substring(from: oldTail.length - overlap)
            let newPrefix = newHead.substring(to: overlap)
            if oldSuffix == newPrefix {
                return (new as NSString).substring(from: overlap)
            }
            overlap -= 1
        }

        return new
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
