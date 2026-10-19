import SwiftUI
import AppKit
import LettoreCore
import LettoreEngine

public final class FloatingPillPanelWindow: NSPanel {
    public override var canBecomeKey: Bool {
        return true
    }
    public override var canBecomeMain: Bool {
        return false
    }
}

public final class DraggablePillHostingView<Content: View>: NSHostingView<Content> {
    public weak var appState: AppState?

    /// Zona del grip: in orizzontale occupa la testa sinistra della capsula,
    /// in verticale la testa superiore. Tutto il resto è dei controlli SwiftUI.
    private let horizontalGripZone: CGFloat = 30
    private let verticalGripZone: CGFloat = 26

    public override func mouseDown(with event: NSEvent) {
        guard let window = self.window else {
            super.mouseDown(with: event)
            return
        }

        let manager = FloatingPillPanelManager.shared
        let isExpanded = (appState?.isPillExpanded ?? false) || manager.isHoverExpanded
        let isVertical = (appState?.pillOrientation == .vertical)

        if isExpanded {
            // In espansione il drag parte solo dal grip; il resto va a SwiftUI.
            let loc = event.locationInWindow
            let inGrip = isVertical
                ? loc.y >= bounds.height - verticalGripZone
                : loc.x <= horizontalGripZone

            if !inGrip {
                super.mouseDown(with: event)
                return
            }
        }

        // In compatto l'intera capsula trascina.
        let startOrigin = window.frame.origin
        manager.beginPanelDrag(event: event)
        let endOrigin = window.frame.origin

        let distance = hypot(endOrigin.x - startOrigin.x, endOrigin.y - startOrigin.y)
        if distance < 3.0 {
            // Tap sul posto: nessun drag. In compatto equivale a play/pausa.
            manager.dragPanelCancelled()
            if !isExpanded {
                NotificationCenter.default.post(name: .floatingPillTogglePlayPause, object: nil)
            }
        } else {
            manager.dragPanelEnded()
        }
    }
}

/// Controller della finestra fluttuante borderless (NSPanel) della Pillola.
///
/// Regola di base: **un solo driver geometrico**. Il trascinamento usa
/// `NSWindow.performDrag` (che segue il mouse 1:1 nel suo tracking loop) e ogni
/// ridimensionamento passa da `updatePanelFrame`, che prima annulla qualsiasi
/// animazione di frame in corso. Non esistono due sistemi che scrivono il frame.
@MainActor
@Observable
public final class FloatingPillPanelManager {
    public static let shared = FloatingPillPanelManager()

    /// Dimensioni canoniche della finestra. Unica fonte di verità: il contenuto
    /// SwiftUI resta sempre più piccolo di questi valori, mai più grande.
    public enum PillMetrics {
        public static let horizontalCompact = NSSize(width: 104, height: 42)
        public static let horizontalExpanded = NSSize(width: 282, height: 42)
        public static let horizontalExpandedFallback = NSSize(width: 298, height: 42)
        public static let verticalCompact = NSSize(width: 48, height: 104)
        public static let verticalExpanded = NSSize(width: 48, height: 170)
        public static let verticalExpandedFallback = NSSize(width: 48, height: 192)

        /// Margine di sicurezza dai bordi dello schermo visibile.
        public static let screenInset: CGFloat = 8

        /// Distanza entro cui il rilascio aggancia la pillola al bordo laterale.
        /// Tenuta bassa di proposito: lo snap massimo coincide con questa soglia,
        /// quindi non può mai teletrasportare la pillola per centinaia di pixel.
        /// Non c'è isteresi: la valutazione avviene solo al rilascio, quindi una
        /// soglia unica è già deterministica e simmetrica in dock e undock.
        public static let dockThreshold: CGFloat = 60

        /// Durata del morphing, condivisa da finestra e contenuto SwiftUI.
        /// Una sola curva per entrambi: se divergono, il contenuto viene
        /// disegnato fuori dalla capsula durante la transizione.
        public static let morphDuration: TimeInterval = 0.28

        public static func panelSize(orientation: PillOrientation, isExpanded: Bool, isFallback: Bool) -> NSSize {
            switch orientation {
            case .horizontal:
                if !isExpanded { return horizontalCompact }
                return isFallback ? horizontalExpandedFallback : horizontalExpanded
            case .vertical:
                if !isExpanded { return verticalCompact }
                return isFallback ? verticalExpandedFallback : verticalExpanded
            }
        }

        /// Il contenuto SwiftUI è sempre più piccolo della finestra che lo ospita.
        public static func contentSize(orientation: PillOrientation, isExpanded: Bool, isFallback: Bool) -> NSSize {
            let panel = panelSize(orientation: orientation, isExpanded: isExpanded, isFallback: isFallback)
            let horizontalInset: CGFloat = orientation == .horizontal ? 8 : 6
            return NSSize(width: panel.width - horizontalInset, height: panel.height - 6)
        }
    }

    public private(set) var panel: NSPanel?
    public private(set) var isDragging: Bool = false

    /// L'espansione da hover vive qui, non in una euristica sulle dimensioni
    /// della finestra: durante il morphing `bounds` è in movimento e mentirebbe.
    public var isHoverExpanded: Bool = false

    public weak var appState: AppState?

    private var screenObserver: AnyObject?

    public var isVisible: Bool {
        return panel?.isVisible ?? false
    }

    private init() {}

    public func toggle(appState: AppState, audioEngine: AudioEngineService, coordinator: PlaybackCoordinator? = nil) {
        if let existing = panel, existing.isVisible {
            hide(appState: appState)
            return
        }
        show(appState: appState, audioEngine: audioEngine, coordinator: coordinator)
    }

    public func show(appState: AppState, audioEngine: AudioEngineService, coordinator: PlaybackCoordinator? = nil) {
        self.appState = appState
        appState.isFloatingPillVisible = true
        isHoverExpanded = false

        if let existing = panel {
            ensureScreenObserver(appState: appState)
            existing.makeKeyAndOrderFront(nil)
            evaluateDockingAndOrientation(panel: existing, appState: appState, animated: false)
            return
        }

        let pillView = FloatingPillView(
            appState: appState,
            audioEngine: audioEngine,
            coordinator: coordinator,
            isStandalone: true
        )

        let hostingView = DraggablePillHostingView(rootView: pillView)
        hostingView.appState = appState
        hostingView.autoresizingMask = [.width, .height]

        let initialSize = PillMetrics.horizontalCompact
        let newPanel = FloatingPillPanelWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = false
        newPanel.isMovableByWindowBackground = false
        newPanel.contentView = hostingView

        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let xPos = screenRect.midX - (initialSize.width / 2)
            let yPos = screenRect.maxY - initialSize.height - 12
            newPanel.setFrameOrigin(NSPoint(x: xPos, y: yPos))
        }

        self.panel = newPanel
        ensureScreenObserver(appState: appState)
        newPanel.makeKeyAndOrderFront(nil)

        evaluateDockingAndOrientation(panel: newPanel, appState: appState, animated: false)
    }

    public func hide(appState: AppState? = nil) {
        cancelFrameAnimation()
        panel?.orderOut(nil)
        isHoverExpanded = false
        appState?.isFloatingPillVisible = false
    }

    private func ensureScreenObserver(appState: AppState) {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak appState] _ in
            MainActor.assumeIsolated {
                guard let self = self, let appState = appState, let panel = self.panel else { return }
                guard !self.isDragging, panel.isVisible else { return }
                self.updatePanelFrame(
                    for: appState.pillOrientation,
                    isExpanded: appState.isPillExpanded || self.isHoverExpanded,
                    animated: false
                )
            }
        }
    }

    // MARK: - Ciclo di vita del drag

    /// Unico punto di ingresso del trascinamento nativo: annulla l'animazione
    /// di frame in volo e delega a `performDrag`.
    public func beginPanelDrag(event: NSEvent) {
        guard let panel = panel else { return }
        dragPanelStarted()
        panel.performDrag(with: event)
    }

    public func dragPanelStarted() {
        // Un'animazione di frame ancora in volo continuerebbe a scrivere l'origine
        // mentre performDrag calcola il delta: è la causa dello sfasamento dal cursore.
        cancelFrameAnimation()
        isDragging = true
    }

    public func dragPanelEnded() {
        isDragging = false
        updateHoverFlagFromCursor()
        guard let appState = appState, let panel = panel else { return }
        evaluateDockingAndOrientation(panel: panel, appState: appState, animated: true)
    }

    public func dragPanelCancelled() {
        isDragging = false
        updateHoverFlagFromCursor()
    }

    /// Durante il drag SwiftUI non riceve aggiornamenti affidabili di hover:
    /// al rilascio riallineiamo il flag alla posizione reale del cursore, così
    /// la pillola non resta espansa (o collassata) per uno stato fantasma.
    private func updateHoverFlagFromCursor() {
        guard let panel = panel, panel.isVisible else { return }
        isHoverExpanded = panel.frame.contains(NSEvent.mouseLocation)
    }

    // MARK: - Geometria

    public func size(for orientation: PillOrientation, isExpanded: Bool) -> NSSize {
        PillMetrics.panelSize(
            orientation: orientation,
            isExpanded: isExpanded,
            isFallback: appState?.isUsingSpeechFallback ?? false
        )
    }

    /// Riallinea il frame della finestra alla dimensione richiesta.
    ///
    /// Ancoraggio: il bordo che ospita il grip resta fermo.
    /// - Orizzontale: grip a sinistra, quindi resta fermo il bordo sinistro
    ///   (il clamp lo sposta solo quanto basta vicino al bordo destro).
    /// - Verticale: grip in alto, quindi resta fermo il bordo superiore.
    ///
    /// Lo stesso ancoraggio vale per dock e undock, così la transizione
    /// orizzontale ↔ verticale non produce salti verticali.
    public func updatePanelFrame(for orientation: PillOrientation, isExpanded: Bool, animated: Bool = true) {
        guard !isDragging else { return }
        guard let panel = panel, let screen = panel.screen ?? NSScreen.main else { return }

        let target = resolvedFrame(
            current: panel.frame,
            screenRect: screen.visibleFrame,
            orientation: orientation,
            isExpanded: isExpanded
        )
        applyFrame(target, to: panel, animated: animated)
    }

    /// Calcola il frame obiettivo a partire da un frame corrente.
    /// Funzione pura sulla geometria: nessun accesso al singleton, così può
    /// essere verificata anche su un pannello di test.
    public nonisolated static func resolvedFrame(
        current: CGRect,
        screenRect: CGRect,
        orientation: PillOrientation,
        isExpanded: Bool,
        isFallback: Bool
    ) -> CGRect {
        let targetSize = PillMetrics.panelSize(
            orientation: orientation,
            isExpanded: isExpanded,
            isFallback: isFallback
        )
        var newOrigin = current.origin

        switch orientation {
        case .horizontal:
            // Grip a sinistra: resta fermo il bordo sinistro. Il clamp sposta
            // solo quanto basta quando la capsula espansa supera il bordo destro.
            newOrigin.x = current.minX
            newOrigin.y = current.maxY - targetSize.height

        case .vertical:
            // Grip in alto: resta fermo il bordo superiore, in dock come in undock.
            newOrigin.y = current.maxY - targetSize.height

            let leftDist = current.minX - screenRect.minX
            let rightDist = screenRect.maxX - current.maxX

            if rightDist <= PillMetrics.dockThreshold {
                newOrigin.x = screenRect.maxX - targetSize.width - PillMetrics.screenInset
            } else if leftDist <= PillMetrics.dockThreshold {
                newOrigin.x = screenRect.minX + PillMetrics.screenInset
            } else {
                newOrigin.x = current.midX - targetSize.width / 2
            }
        }

        newOrigin = clampedOrigin(newOrigin, size: targetSize, in: screenRect)
        return CGRect(origin: newOrigin, size: targetSize)
    }

    /// Variante d'istanza: legge lo stato di fallback dell'app.
    func resolvedFrame(
        current: CGRect,
        screenRect: CGRect,
        orientation: PillOrientation,
        isExpanded: Bool
    ) -> CGRect {
        Self.resolvedFrame(
            current: current,
            screenRect: screenRect,
            orientation: orientation,
            isExpanded: isExpanded,
            isFallback: appState?.isUsingSpeechFallback ?? false
        )
    }

    // MARK: - Docking & orientamento

    public func evaluateDockingAndOrientation(panel: NSPanel, appState: AppState, animated: Bool) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let frame = panel.frame

        let leftDist = frame.minX - screenRect.minX
        let rightDist = screenRect.maxX - frame.maxX

        let newOrientation: PillOrientation
        let newDockSide: PillDockSide

        if leftDist <= PillMetrics.dockThreshold {
            newOrientation = .vertical
            newDockSide = .left
        } else if rightDist <= PillMetrics.dockThreshold {
            newOrientation = .vertical
            newDockSide = .right
        } else {
            newOrientation = .horizontal
            newDockSide = .center
        }

        appState.pillOrientation = newOrientation
        appState.pillDockSide = newDockSide

        // Riallinea sempre: copre anche lo snap al bordo quando l'orientamento
        // non cambia ma la pillola va riportata dentro lo schermo.
        let target = resolvedFrame(
            current: frame,
            screenRect: screenRect,
            orientation: newOrientation,
            isExpanded: appState.isPillExpanded || isHoverExpanded
        )
        applyFrame(target, to: panel, animated: animated)
    }

    // MARK: - Applicazione del frame

    private func clampedOrigin(_ origin: NSPoint, size: NSSize, in screenRect: NSRect) -> NSPoint {
        Self.clampedOrigin(origin, size: size, in: screenRect)
    }

    nonisolated static func clampedOrigin(_ origin: NSPoint, size: NSSize, in screenRect: NSRect) -> NSPoint {
        let inset = PillMetrics.screenInset
        let minX = screenRect.minX + inset
        let maxX = screenRect.maxX - size.width - inset
        let minY = screenRect.minY + inset
        let maxY = screenRect.maxY - size.height - inset

        return NSPoint(
            x: max(minX, min(maxX, origin.x)),
            y: max(minY, min(maxY, origin.y))
        )
    }

    private func applyFrame(_ newFrame: NSRect, to panel: NSPanel, animated: Bool) {
        guard panel.frame != newFrame else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = PillMetrics.morphDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(newFrame, display: true)
            }
        } else {
            panel.setFrame(newFrame, display: true)
        }
    }

    /// Interrompe l'animazione di frame e fissa la finestra dov'è adesso.
    ///
    /// È il punto che elimina la corsa tra animator e `performDrag`: senza,
    /// l'animazione di hover continua a scrivere l'origine mentre il drag
    /// calcola il delta dal mouse, e la pillola "scappa" dal cursore.
    /// Un'animazione a durata zero sullo stesso proxy sostituisce quella in
    /// volo, che è il modo affidabile di annullarla.
    private func cancelFrameAnimation() {
        guard let panel = panel else { return }
        let currentFrame = panel.frame

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(currentFrame, display: false)
        }
    }
}

extension Notification.Name {
    /// Tap sul corpo compatto della pillola: play/pausa.
    public static let floatingPillTogglePlayPause = Notification.Name("FloatingPillTogglePlayPause")
}
