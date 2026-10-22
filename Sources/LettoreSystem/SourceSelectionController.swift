import Foundation
import AppKit
import LettoreCore

/// Eventi di input che possono interrompere una sessione di lettura.
public enum SourceInputEvent: Equatable, Sendable {
    case keyDown
    case leftMouseDown
    case leftMouseDragged
    case rightMouseDown
    case otherMouseDown
    case scrollWheel
}

/// Sorgente di eventi di input globali.
///
/// Il protocollo permette ai test di iniettare eventi senza installare un
/// monitor reale. Lo scroll è consegnato al controller, che lo ignora: la
/// policy resta testabile.
@MainActor
public protocol SourceInputMonitoring: AnyObject {
    func start(handler: @escaping @Sendable @MainActor (SourceInputEvent) -> Void)
    func stop()
}

/// Monitor globale `NSEvent` usato in produzione.
///
/// Non ruba il focus e non modifica gli eventi: osserva soltanto. La rotella e
/// il trackpad restano consentiti durante la lettura.
@MainActor
public final class NSEventSourceInputMonitor: SourceInputMonitoring {
    nonisolated(unsafe) private var monitor: Any?

    public init() {}

    public func start(handler: @escaping @Sendable @MainActor (SourceInputEvent) -> Void) {
        stop()

        let mask: NSEvent.EventTypeMask = [
            .keyDown,
            .leftMouseDown,
            .leftMouseDragged,
            .rightMouseDown,
            .otherMouseDown,
            .scrollWheel
        ]

        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            guard let mapped = SourceInputEvent(eventType: event.type) else { return }
            Task { @MainActor in
                handler(mapped)
            }
        }
    }

    public func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

extension SourceInputEvent {
    init?(eventType: NSEvent.EventType) {
        switch eventType {
        case .keyDown: self = .keyDown
        case .leftMouseDown: self = .leftMouseDown
        case .leftMouseDragged: self = .leftMouseDragged
        case .rightMouseDown: self = .rightMouseDown
        case .otherMouseDown: self = .otherMouseDown
        case .scrollWheel: self = .scrollWheel
        default: return nil
        }
    }
}

/// Controller della sessione di selezione nativa.
///
/// Responsabilità:
/// - una sola sessione per volta;
/// - decisione frontmost/sospensione senza scrivere in background;
/// - riapplicazione dell'ultimo range quando la sorgente torna frontmost;
/// - stop su input dell'utente nell'app sorgente, una sola volta per sessione.
///
/// Non gestisce playback, toggle o persistenza: il ticket 04 collega il
/// callback `onUserInteraction` alla lettura.
@MainActor
public final class SourceSelectionController {

    private struct Session {
        let documentID: UUID
        let sourcePID: pid_t
        var lastRange: SourceTextRange?
        var isSuspended: Bool
        var didReportUserInteraction: Bool
        var isInteractionEnded: Bool
    }

    private let highlighter: any SourceSelectionHighlighting
    private let frontmostPID: @MainActor () -> pid_t?
    private let isEnabled: @MainActor () -> Bool
    private let onUserInteraction: @MainActor () -> Void
    private let inputMonitor: any SourceInputMonitoring
    private let activationCenter: NotificationCenter

    private var session: Session?
    private var workspaceObserver: NSObjectProtocol?

    public init(
        highlighter: any SourceSelectionHighlighting,
        frontmostPID: @escaping @MainActor () -> pid_t? = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        },
        isEnabled: @escaping @MainActor () -> Bool = { true },
        onUserInteraction: @escaping @MainActor () -> Void = {},
        inputMonitor: any SourceInputMonitoring = NSEventSourceInputMonitor(),
        activationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.highlighter = highlighter
        self.frontmostPID = frontmostPID
        self.isEnabled = isEnabled
        self.onUserInteraction = onUserInteraction
        self.inputMonitor = inputMonitor
        self.activationCenter = activationCenter
    }

    // MARK: - Ciclo di vita

    public func begin(documentID: UUID, sourcePID: pid_t) async {
        if let previous = session {
            // Evita che un update rimasto in volo durante il rilascio continui
            // a usare la sessione precedente.
            session = nil
            await release(previous)
        }

        session = Session(
            documentID: documentID,
            sourcePID: sourcePID,
            lastRange: nil,
            isSuspended: false,
            didReportUserInteraction: false,
            isInteractionEnded: false
        )

        installWorkspaceObserver()
        inputMonitor.start { [weak self] event in
            self?.handleInputEvent(event)
        }

        if let observing = highlighter as? any SourceSelectionChangeObserving {
            _ = await observing.observeSelectionChanges(documentID: documentID) { [weak self] in
                Task { @MainActor in
                    self?.handleObservedSelectionChange(documentID: documentID)
                }
            }
        }
    }

    /// Aggiorna la frase corrente. Restituisce `nil` quando la richiesta è un
    /// no-op (toggle spento, documento non corrente, sessione già interrotta).
    @discardableResult
    public func update(
        range: SourceTextRange,
        documentID: UUID
    ) async -> SourceHighlightOutcome? {
        guard isEnabled() else { return nil }
        guard var current = session,
              current.documentID == documentID,
              !current.isInteractionEnded else {
            return nil
        }

        current.lastRange = range

        guard frontmostPID() == current.sourcePID else {
            current.isSuspended = true
            session = current
            return .suspended
        }

        current.isSuspended = false
        session = current

        let outcome = await highlighter.highlightSourceRange(
            range,
            documentID: documentID
        )

        // La sessione può essere cambiata durante l'await: non applicare
        // l'esito della vecchia richiesta alla sessione nuova.
        guard self.session?.documentID == documentID else { return outcome }
        if outcome == .suspended {
            self.session?.isSuspended = true
        }
        return outcome
    }

    /// Sospende gli aggiornamenti senza toccare l'audio.
    public func suspend() {
        guard session != nil else { return }
        session?.isSuspended = true
    }

    /// Riprende gli aggiornamenti se la sorgente è di nuovo frontmost.
    public func resume() async {
        guard var current = session,
              isEnabled(),
              !current.isInteractionEnded else {
            return
        }

        guard frontmostPID() == current.sourcePID else {
            current.isSuspended = true
            session = current
            return
        }

        current.isSuspended = false
        session = current

        guard let range = current.lastRange else { return }
        let outcome = await highlighter.highlightSourceRange(
            range,
            documentID: current.documentID
        )
        if outcome == .suspended, self.session?.documentID == current.documentID {
            self.session?.isSuspended = true
        }
    }

    /// Chiude la sessione e rilascia observer e monitor. Non deseleziona il
    /// testo nell'app di origine.
    public func end() async {
        guard let current = session else {
            stopInfrastructure()
            return
        }
        session = nil
        await release(current)
    }

    // MARK: - Frontmost

    /// Gestisce il cambio di applicazione frontmost. È `internal` perché i
    /// test lo invocano direttamente senza costruire una vera attivazione.
    func handleApplicationActivation(pid: pid_t) async {
        guard var current = session,
              !current.isInteractionEnded else {
            return
        }

        guard pid == current.sourcePID else {
            current.isSuspended = true
            session = current
            return
        }

        guard isEnabled(), frontmostPID() == current.sourcePID else {
            current.isSuspended = true
            session = current
            return
        }

        current.isSuspended = false
        session = current

        guard let range = current.lastRange else { return }
        let outcome = await highlighter.highlightSourceRange(
            range,
            documentID: current.documentID
        )
        if outcome == .suspended, self.session?.documentID == current.documentID {
            self.session?.isSuspended = true
        }
    }

    // MARK: - Input

    private func handleInputEvent(_ event: SourceInputEvent) {
        guard event != .scrollWheel else { return }
        guard isEnabled() else { return }
        guard let current = session,
              !current.didReportUserInteraction,
              frontmostPID() == current.sourcePID else {
            return
        }
        reportUserInteraction()
    }

    private func handleObservedSelectionChange(documentID: UUID) {
        guard isEnabled() else { return }
        guard let current = session,
              current.documentID == documentID,
              !current.didReportUserInteraction,
              frontmostPID() == current.sourcePID else {
            return
        }
        reportUserInteraction()
    }

    /// Il callback deve arrivare una sola volta per sessione: sia il monitor
    /// globale sia l'observer AX possono segnalare lo stesso input.
    private func reportUserInteraction() {
        guard var current = session, !current.didReportUserInteraction else {
            return
        }
        current.didReportUserInteraction = true
        current.isInteractionEnded = true
        session = current
        onUserInteraction()
    }

    // MARK: - Infrastruttura

    private func installWorkspaceObserver() {
        guard workspaceObserver == nil else { return }

        workspaceObserver = activationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication else {
                return
            }
            let pid = application.processIdentifier
            Task { @MainActor in
                await self?.handleApplicationActivation(pid: pid)
            }
        }
    }

    private func stopInfrastructure() {
        inputMonitor.stop()

        if let workspaceObserver {
            activationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
    }

    private func release(_ session: Session) async {
        stopInfrastructure()

        if let observing = highlighter as? any SourceSelectionChangeObserving {
            await observing.stopObservingSelectionChanges(documentID: session.documentID)
        }
        await highlighter.endSourceHighlight(documentID: session.documentID)
    }
}
