import Foundation
@preconcurrency import ApplicationServices
import CoreGraphics
import AppKit
import LettoreCore

/// Modalità di scrittura della selezione nella sessione sorgente.
enum SourceHighlightMode {
    /// `AXSelectedTextRange` con `AXValue` `CFRange` (TextEdit, VS Code).
    case textRange
    /// `AXSelectedTextMarkerRange` con marker creati da indice (Safari).
    case textMarker
}

/// Sessione di highlight aperta alla cattura.
///
/// Gli `AXUIElement` restano confinati all'attore. Il range è in unità UTF-16
/// assolute del documento sorgente della sessione.
struct SourceHighlightSession {
    let documentID: UUID
    let sourcePID: pid_t?
    let element: AXUIElement
    let markerContainer: AXUIElement?
    let mode: SourceHighlightMode
    let capturedRange: SourceTextRange?
    var lastRequestedRange: SourceTextRange?
    var lastWrittenRange: SourceTextRange?
}

/// Metadati restituiti alla cattura per collegare i chunk alla sessione.
struct SourceHighlightRegistration {
    let documentID: UUID
    let sourceRange: SourceTextRange?
    let sourcePID: pid_t?
}

// MARK: - Registrazione della sessione

extension AXCaptureService {

    /// Registra la sessione per una cattura continua risolta da un documento.
    func registerResolvedHighlightSession(
        focused: AXUIElement,
        markerContainer: AXUIElement?,
        sourcePID: pid_t?,
        capturedRange: SourceTextRange?
    ) -> SourceHighlightRegistration {
        installHighlightSession(
            focused: focused,
            markerContainer: markerContainer,
            sourcePID: sourcePID ?? processIdentifier(of: focused),
            capturedRange: capturedRange
        )
    }

    /// Registra la sessione per la cattura non continua. Il range copre il
    /// testo selezionato restituito, senza trimming.
    func registerSelectionHighlight(
        focused: AXUIElement,
        sourcePID: pid_t?
    ) -> SourceHighlightRegistration {
        let selection = rawSelectionRange(of: focused)
        return installHighlightSession(
            focused: focused,
            markerContainer: selection.container,
            sourcePID: sourcePID ?? processIdentifier(of: focused),
            capturedRange: selection.range
        )
    }

    /// Registra la sessione per il fallback "sola selezione" della lettura
    /// continua: il testo restituito è ritagliato, quindi il range avanza.
    func registerTrimmedSelectionHighlight(
        focused: AXUIElement,
        sourcePID: pid_t?,
        selectedText: String
    ) -> SourceHighlightRegistration {
        let selection = rawSelectionRange(of: focused)
        let range = selection.range.map {
            SourceTextTrimming.trimmedRange(selection: $0, selectedText: selectedText)
        }
        return installHighlightSession(
            focused: focused,
            markerContainer: selection.container,
            sourcePID: sourcePID ?? processIdentifier(of: focused),
            capturedRange: range
        )
    }

    private func installHighlightSession(
        focused: AXUIElement,
        markerContainer: AXUIElement?,
        sourcePID: pid_t?,
        capturedRange: SourceTextRange?
    ) -> SourceHighlightRegistration {
        clearHighlightSession()

        let documentID = UUID()

        // Senza un range non esiste una selezione da scrivere: non trattenere
        // l'elemento AX né installare un observer che non potrebbe applicare
        // nulla. Il chiamante userà il fallback Studio.
        guard let capturedRange else {
            return SourceHighlightRegistration(
                documentID: documentID,
                sourceRange: nil,
                sourcePID: sourcePID
            )
        }

        let mode: SourceHighlightMode = markerContainer == nil ? .textRange : .textMarker
        highlightSession = SourceHighlightSession(
            documentID: documentID,
            sourcePID: sourcePID,
            element: focused,
            markerContainer: markerContainer,
            mode: mode,
            capturedRange: capturedRange
        )

        print("[AXCapture][Highlight] sessione=\(documentID.uuidString.prefix(8)) mode=\(mode == .textMarker ? "marker" : "range") range=\(capturedRange.location)+\(capturedRange.length) pid=\(sourcePID.map(String.init) ?? "nil")")

        return SourceHighlightRegistration(
            documentID: documentID,
            sourceRange: capturedRange,
            sourcePID: sourcePID
        )
    }

    /// Selezione corrente in coordinate assolute, con il contenitore marker
    /// quando la sorgente usa `AXSelectedTextMarkerRange`.
    private func rawSelectionRange(
        of focused: AXUIElement
    ) -> (range: SourceTextRange?, container: AXUIElement?) {
        // Preferisci il range solo se è davvero scrivibile: Safari espone
        // spesso un `AXSelectedTextRange` non settabile e la selezione va
        // scritta tramite i text marker.
        if isAttributeSettable(focused, kAXSelectedTextRangeAttribute as CFString),
           let range = copySelectedRange(of: focused),
           range.location >= 0,
           range.length >= 0 {
            return (
                SourceTextRange(location: range.location, length: range.length),
                nil
            )
        }

        guard let container = nearestTextMarkerContainer(from: focused, fallback: nil) else {
            return (nil, nil)
        }
        guard let markerRange = selectedTextMarkerRange(from: focused, in: container),
              let start = copyStartMarker(of: markerRange),
              let index = textMarkerIndex(of: start, in: container),
              index >= 0 else {
            return (nil, container)
        }

        let length = max(0, textMarkerRangeLength(of: markerRange, in: container) ?? 0)
        return (
            SourceTextRange(location: index, length: length),
            container
        )
    }

    func clearHighlightSession() {
        selectionObserverHandle?.invalidate()
        selectionObserverHandle = nil
        selectionNotificationGeneration &+= 1
        selectionObservationGeneration &+= 1
        highlightSession = nil
    }
}

// MARK: - Scrittura della selezione

extension AXCaptureService: SourceSelectionHighlighting {

    public func highlightSourceRange(
        _ range: SourceTextRange,
        documentID: UUID
    ) async -> SourceHighlightOutcome {
        guard range.location >= 0, range.length >= 0 else { return .failed }

        guard var session = highlightSession, session.documentID == documentID else {
            return .unsupported
        }
        session.lastRequestedRange = range
        highlightSession = session

        guard await isApplicationFrontmost(session.sourcePID) else {
            return .suspended
        }

        // La sessione può essere stata sostituita durante l'attesa del
        // MainActor: non scrivere su un documento diverso.
        guard var current = highlightSession, current.documentID == documentID else {
            return .unsupported
        }

        let outcome: SourceHighlightOutcome
        switch current.mode {
        case .textRange:
            outcome = writeTextRange(range, to: current.element)
        case .textMarker:
            outcome = writeTextMarkerRange(range, to: current.markerContainer)
        }

        if outcome == .applied {
            current.lastWrittenRange = range
            highlightSession = current
        }

        return outcome
    }

    public func endSourceHighlight(documentID: UUID) async {
        guard highlightSession?.documentID == documentID else { return }
        clearHighlightSession()
    }

    private func writeTextRange(
        _ range: SourceTextRange,
        to element: AXUIElement
    ) -> SourceHighlightOutcome {
        guard isAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString) else {
            print("[AXCapture][Highlight] AXSelectedTextRange non scrivibile")
            return .unsupported
        }

        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else {
            print("[AXCapture][Highlight] AXValueCreate(.cfRange) fallito")
            return .failed
        }

        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            value
        )
        guard result == .success else {
            print("[AXCapture][Highlight] scrittura range fallita: \(result.rawValue)")
            return .failed
        }

        // Readback quando disponibile: distingue una scrittura applicata da
        // una silenziosamente ignorata.
        guard let actual = copySelectedRange(of: element) else { return .applied }
        return actual.location == range.location && actual.length == range.length
            ? .applied
            : .failed
    }

    private func writeTextMarkerRange(
        _ range: SourceTextRange,
        to container: AXUIElement?
    ) -> SourceHighlightOutcome {
        guard let container else { return .unsupported }
        guard isAttributeSettable(container, AXMarkerAttribute.selectedRange as CFString) else {
            print("[AXCapture][Highlight] AXSelectedTextMarkerRange non scrivibile")
            return .unsupported
        }

        guard let start = textMarker(atIndex: range.location, in: container),
              let end = textMarker(atIndex: range.end, in: container),
              let markerRange = textMarkerRange(from: start, to: end) else {
            print("[AXCapture][Highlight] marker non creabili per \(range.location)..<\(range.end)")
            return .failed
        }

        let result = AXUIElementSetAttributeValue(
            container,
            AXMarkerAttribute.selectedRange as CFString,
            markerRange
        )
        guard result == .success else {
            print("[AXCapture][Highlight] scrittura marker fallita: \(result.rawValue)")
            return .failed
        }

        guard let written = textMarkerRangeAttribute(container, AXMarkerAttribute.selectedRange),
              let writtenStart = copyStartMarker(of: written),
              let actualStart = textMarkerIndex(of: writtenStart, in: container) else {
            return .applied
        }
        let actualLength = textMarkerRangeLength(of: written, in: container)
        if actualStart != range.location {
            return .failed
        }
        if let actualLength, actualLength != range.length {
            return .failed
        }
        return .applied
    }

    private func isAttributeSettable(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, attribute, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    private func isApplicationFrontmost(_ pid: pid_t?) async -> Bool {
        guard let pid else { return false }
        let frontmost = await MainActor.run {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
        return frontmost == pid
    }
}

// MARK: - Osservazione di AXSelectedTextChanged

extension AXCaptureService: SourceSelectionChangeObserving {

    public func observeSelectionChanges(
        documentID: UUID,
        onChange: @escaping @Sendable () -> Void
    ) async -> Bool {
        guard let session = highlightSession, session.documentID == documentID else {
            return false
        }

        selectionObserverHandle?.invalidate()
        selectionObserverHandle = nil
        // Le notifiche già in debounce appartengono all'osservazione vecchia.
        selectionNotificationGeneration &+= 1
        selectionObservationGeneration &+= 1
        let observationGeneration = selectionObservationGeneration

        guard let pid = session.sourcePID ?? processIdentifier(of: session.element) else {
            return false
        }

        let handler: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            Task {
                await self.handleSelectionChanged(
                    documentID: documentID,
                    observationGeneration: observationGeneration,
                    onChange: onChange
                )
            }
        }
        let box = AXSelectionNotificationBox(handler: handler)
        let token = AXSelectionHandlerRegistry.shared.register(box)
        guard let refcon = AXSelectionHandlerRegistry.pointer(forToken: token) else {
            AXSelectionHandlerRegistry.shared.unregister(token)
            return false
        }

        var observer: AXObserver?
        guard AXObserverCreate(pid, axSelectionChangedCallback, &observer) == .success,
              let observer else {
            AXSelectionHandlerRegistry.shared.unregister(token)
            return false
        }

        // L'observer va sull'elemento, non su app+elemento: la stessa modifica
        // verrebbe notificata due volte. Per Safari l'elemento osservato è la
        // web area che possiede i marker.
        let element = session.markerContainer ?? session.element
        guard AXObserverAddNotification(
            observer,
            element,
            kAXSelectedTextChangedNotification as CFString,
            refcon
        ) == .success else {
            AXSelectionHandlerRegistry.shared.unregister(token)
            return false
        }

        let handle = AXSelectionObserverHandle(
            observer: observer,
            element: element,
            token: token
        )

        // CFRunLoop non è thread-safe: la source va aggiunta al run loop
        // principale dal thread principale.
        await MainActor.run {
            handle.installOnMainRunLoop()
        }

        // Durante l'attesa l'attore è rientrante: uno stop o una nuova
        // osservazione possono aver già sostituito questa installazione.
        guard !Task.isCancelled,
              highlightSession?.documentID == documentID,
              selectionObservationGeneration == observationGeneration,
              selectionObserverHandle == nil else {
            handle.invalidate()
            return false
        }

        selectionObserverHandle = handle
        return true
    }

    public func stopObservingSelectionChanges(documentID: UUID) async {
        guard highlightSession?.documentID == documentID else { return }
        selectionObserverHandle?.invalidate()
        selectionObserverHandle = nil
        // Annulla un eventuale debounce già in corso e un'installazione
        // dell'observer ancora in volo.
        selectionNotificationGeneration &+= 1
        selectionObservationGeneration &+= 1
    }

    private func handleSelectionChanged(
        documentID: UUID,
        observationGeneration: Int,
        onChange: @escaping @Sendable () -> Void
    ) async {
        // Una notifica già accodata può arrivare dopo lo stop: il token
        // dell'osservazione la scarta anche prima che la source sia rimossa.
        guard selectionObservationGeneration == observationGeneration,
              highlightSession?.documentID == documentID else {
            return
        }

        // Le notifiche possono arrivare duplicate: solo l'ultima della
        // finestra di debounce viene valutata.
        selectionNotificationGeneration &+= 1
        let generation = selectionNotificationGeneration
        try? await Task.sleep(nanoseconds: 60_000_000)

        guard !Task.isCancelled,
              generation == selectionNotificationGeneration,
              selectionObservationGeneration == observationGeneration,
              let session = highlightSession,
              session.documentID == documentID else {
            return
        }

        guard let current = currentSelectionRange(for: session) else { return }

        // Notifica generata dalla nostra scrittura: il readback coincide con
        // l'ultimo range scritto e non è input utente.
        if let expected = session.lastWrittenRange, current == expected {
            return
        }

        onChange()
    }

    private func currentSelectionRange(
        for session: SourceHighlightSession
    ) -> SourceTextRange? {
        switch session.mode {
        case .textRange:
            guard let range = copySelectedRange(of: session.element) else { return nil }
            return SourceTextRange(location: range.location, length: range.length)

        case .textMarker:
            guard let container = session.markerContainer,
                  let written = textMarkerRangeAttribute(
                    container,
                    AXMarkerAttribute.selectedRange
                  ),
                  let start = copyStartMarker(of: written),
                  let index = textMarkerIndex(of: start, in: container) else {
                return nil
            }
            let length = max(0, textMarkerRangeLength(of: written, in: container) ?? 0)
            return SourceTextRange(location: index, length: length)
        }
    }
}

// MARK: - Ponte C dell'AXObserver

final class AXSelectionNotificationBox: @unchecked Sendable {
    private let handler: @Sendable () -> Void

    init(handler: @escaping @Sendable () -> Void) {
        self.handler = handler
    }

    func fire() {
        handler()
    }
}

/// Registro degli handler dei callback AX.
///
/// Il `refcon` è un token numerico, non un puntatore a un oggetto: un callback
/// già accodato sul run loop può essere consegnato dopo la rimozione della
/// source. Cercando l'handler nel registro, quel callback trova un dizionario
/// valido (al più senza voce) invece di memoria liberata.
final class AXSelectionHandlerRegistry: @unchecked Sendable {
    static let shared = AXSelectionHandlerRegistry()

    private let lock = NSLock()
    private var nextToken = 1
    private var handlers: [Int: AXSelectionNotificationBox] = [:]

    func register(_ box: AXSelectionNotificationBox) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let token = nextToken
        nextToken += 1
        handlers[token] = box
        return token
    }

    func unregister(_ token: Int) {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeValue(forKey: token)
    }

    func handler(forToken token: Int) -> AXSelectionNotificationBox? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[token]
    }

    static func pointer(forToken token: Int) -> UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer(bitPattern: token)
    }

    static func token(from pointer: UnsafeMutableRawPointer) -> Int {
        Int(bitPattern: pointer)
    }
}

final class AXSelectionObserverHandle: @unchecked Sendable {
    private let observer: AXObserver
    private let element: AXUIElement
    private let token: Int
    private var isInvalidated = false

    init(
        observer: AXObserver,
        element: AXUIElement,
        token: Int
    ) {
        self.observer = observer
        self.element = element
        self.token = token
    }

    /// Deve girare sul main run loop, dove vive la source.
    func installOnMainRunLoop() {
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
    }

    /// Rimuove notifica e source sul main run loop. Il box resta nel registro
    /// finché la rimozione non è completata: un callback già in coda non può
    /// leggere memoria liberata.
    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true

        let observer = self.observer
        let element = self.element
        let token = self.token
        DispatchQueue.main.async {
            AXObserverRemoveNotification(
                observer,
                element,
                kAXSelectedTextChangedNotification as CFString
            )
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
            AXSelectionHandlerRegistry.shared.unregister(token)
        }
    }
}

private func axSelectionChangedCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let token = AXSelectionHandlerRegistry.token(from: refcon)
    guard let box = AXSelectionHandlerRegistry.shared.handler(forToken: token) else {
        return
    }
    box.fire()
}
