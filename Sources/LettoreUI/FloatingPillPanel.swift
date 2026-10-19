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
        guard self.window != nil else {
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
        manager.beginPanelDrag(atMouseLocation: NSEvent.mouseLocation) { distance in
            if distance < FloatingPillPanelManager.PillMetrics.tapThreshold {
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
}

/// Controller della finestra fluttuante borderless (NSPanel) della Pillola.
///
/// Regola di base: **un solo driver geometrico**. Il trascinamento è manuale
/// (mouseDragged → origine = cursore − offset di presa) e ogni
/// ridimensionamento passa da `resolvedFrame`, che prima annulla qualsiasi
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

        /// Distanza entro cui la pillola si aggancia al bordo laterale mentre
        /// viene trascinata. L'aggancio è "morbido": una volta docked, la
        /// pillola resta al bordo finché il cursore non si allontana oltre
        /// `dockExitThreshold`, così il magnete non sfarfalla sul confine.
        public static let dockThreshold: CGFloat = 60

        /// Soglia di uscita dal dock (isteresi). Più alta della soglia di
        /// ingresso per evitare oscillazioni orizzontale ↔ verticale.
        public static let dockExitThreshold: CGFloat = 130

        /// Spostamento massimo del cursore (in punti) entro cui un click resta
        /// un tap: oltre è un trascinamento. Il tremolio della mano su un click
        /// reale arriva a 4-5px, quindi la soglia deve essere più larga.
        public static let tapThreshold: CGFloat = 8

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
    private var dragReleaseHandler: (@MainActor (CGFloat) -> Void)?
    private var dragEventMonitor: Any?
    private var dragGrabOffset: NSPoint = .zero
    private var dragStartMouseLocation: NSPoint = .zero
    private var dragWasExpanded: Bool = false
    private var liveDockSide: PillDockSide = .center

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
            existing.orderFrontRegardless()
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
        // Il frame della finestra è deciso solo da `resolvedFrame`. Senza
        // questo, NSHostingView adatta la finestra alla dimensione intrinseca
        // del contenuto (274×36 invece di 282×42) in un passaggio asincrono:
        // il frame "scappa" sotto al manager e il morphing ai bordi deriva.
        hostingView.sizingOptions = []

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
        // Non rubare mai il key status all'app esterna: la lettura AX della
        // selezione (e il fallback Cmd+C) devono restare puntati sull'app da
        // cui l'utente ha selezionato il testo.
        newPanel.becomesKeyOnlyIfNeeded = true
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
        // orderFrontRegardless (non makeKeyAndOrderFront): la pillola appare
        // anche con app non attiva senza mai diventare key window.
        newPanel.orderFrontRegardless()

        evaluateDockingAndOrientation(panel: newPanel, appState: appState, animated: false)
    }

    public func hide(appState: AppState? = nil) {
        removeDragEventMonitor()
        dragReleaseHandler = nil
        isDragging = false
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

    /// Punto di ingresso unico del trascinamento manuale.
    ///
    /// Niente `performDrag`: il WindowServer terrebbe l'ancora del cursore per
    /// sé e qualunque ridimensionamento live (il morphing ai bordi) verrebbe
    /// combattuto dal suo tracking loop. Qui il movimento è nostro, quindi
    /// possiamo morphare la pillola **mentre** la si trascina.
    public func beginPanelDrag(atMouseLocation mouseLocation: NSPoint, onRelease: @escaping @MainActor (CGFloat) -> Void) {
        guard let panel = panel else { return }
        removeDragEventMonitor()
        dragPanelStarted()
        dragGrabOffset = NSPoint(
            x: mouseLocation.x - panel.frame.minX,
            y: mouseLocation.y - panel.frame.minY
        )
        dragStartMouseLocation = mouseLocation
        dragWasExpanded = (appState?.isPillExpanded ?? false) || isHoverExpanded
        liveDockSide = appState?.pillDockSide ?? .center
        dragReleaseHandler = onRelease

        // Il morphing live ricostruisce l'albero SwiftUI: la vista che ha
        // ricevuto il mouseDown può sparire a metà drag e non ricevere più il
        // mouseUp. Il monitor locale non dipende dalla gerarchia delle viste.
        dragEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard let self else { return event }
            let type = event.type
            guard type == .leftMouseDragged || type == .leftMouseUp else { return event }
            MainActor.assumeIsolated {
                if type == .leftMouseDragged {
                    self.continuePanelDrag(to: NSEvent.mouseLocation)
                } else {
                    self.finishPanelDrag()
                }
            }
            return nil
        }
    }

    private func removeDragEventMonitor() {
        if let monitor = dragEventMonitor {
            NSEvent.removeMonitor(monitor)
            dragEventMonitor = nil
        }
    }

    /// Aggiorna posizione e orientamento a ogni evento di trascinamento.
    /// Qui vive il morphing live: il docking è deciso dalla posizione del
    /// cursore e lo stato raggiunto viene conservato al rilascio, senza
    /// rivalutazioni sul frame che potrebbero riagganciarlo.
    public func continuePanelDrag(to mouseLocation: NSPoint) {
        guard isDragging, let panel = panel, let screen = panel.screen ?? NSScreen.main else { return }
        let screenRect = screen.visibleFrame

        // Il frame proposto segue il cursore col medesimo offset di presa; la
        // dimensione resta quella attuale e viene risolta da `resolvedFrame`.
        let proposed = CGRect(
            origin: NSPoint(x: mouseLocation.x - dragGrabOffset.x,
                            y: mouseLocation.y - dragGrabOffset.y),
            size: panel.frame.size
        )

        // Il dock live si decide sulla posizione del **cursore**, non sul bordo
        // della finestra: con la capsula espansa (282 px) il bordo destro
        // tocca lo schermo quando il puntatore è ancora ~265 px indietro, e
        // ancorare subito la verticale al bordo farebbe "teletrasportare" la
        // pillola lontano dal mouse. Col cursore il morphing avviene quando
        // l'utente porta davvero il puntatore all'estremo.
        let dock = Self.resolvedLiveDock(
            previous: liveDockSide,
            cursorX: mouseLocation.x,
            screenRect: screenRect
        )
        liveDockSide = dock

        let orientation: PillOrientation = dock == .center ? .horizontal : .vertical
        appState?.pillOrientation = orientation
        appState?.pillDockSide = dock

        let target = Self.resolvedFrame(
            current: proposed,
            screenRect: screenRect,
            orientation: orientation,
            isExpanded: dragWasExpanded,
            isFallback: appState?.isUsingSpeechFallback ?? false,
            dockSide: dock
        )
        let previousHeight = panel.frame.height
        applyFrame(target, to: panel, animated: false)

        // Il morphing cambia l'altezza della finestra e l'ancoraggio del bordo
        // superiore sposta l'origine senza che il cursore si muova. Se tenessimo
        // l'offset di presa iniziale, il prossimo evento ripartirebbe da quella
        // origine "vecchia" e la pillola scivolerebbe in verticale a ogni
        // cambio di orientamento (es. 170 → 42 → 170 px). L'asse x resta
        // invece quello del grip: al momento dell'undock la capsula orizzontale
        // deve ricomparire sotto il cursore, non allineata al bordo dove era
        // stata agganciata.
        dragGrabOffset.y += target.height - previousHeight
    }

    /// Chiude il drag e consegna al chiamante lo spostamento **del cursore**.
    /// La distanza del cursore, non della finestra: lo snap al bordo muove la
    /// finestra anche sotto un cursore quasi fermo, e un click non deve
    /// diventare drag solo perché la pillola si è agganciata.
    public func finishPanelDrag() {
        guard isDragging else { return }
        removeDragEventMonitor()
        let handler = dragReleaseHandler
        dragReleaseHandler = nil
        let distance = hypot(
            NSEvent.mouseLocation.x - dragStartMouseLocation.x,
            NSEvent.mouseLocation.y - dragStartMouseLocation.y
        )
        handler?(distance)
    }

    public func dragPanelStarted() {
        // Un'animazione di frame ancora in volo continuerebbe a scrivere l'origine
        // mentre il drag calcola il delta: è la causa dello sfasamento dal cursore.
        cancelFrameAnimation()
        isDragging = true
    }

    public func dragPanelEnded() {
        isDragging = false
        updateHoverFlagFromCursor()
        guard let appState = appState, let panel = panel,
              let screen = panel.screen ?? NSScreen.main else { return }

        // Non rivalutare il docking qui: durante il drag è stato deciso sulla
        // posizione del cursore, mentre qui il frame (specie se espanso e
        // clamped al bordo) darebbe distanze diverse e riaggancerebbe la
        // pillola appena trascinata via. Si applica lo stato live, animando
        // solo l'eventuale cambio di espansione dovuto all'hover.
        let target = Self.resolvedFrame(
            current: panel.frame,
            screenRect: screen.visibleFrame,
            orientation: appState.pillOrientation,
            isExpanded: appState.isPillExpanded || isHoverExpanded,
            isFallback: appState.isUsingSpeechFallback,
            dockSide: appState.pillDockSide
        )
        applyFrame(target, to: panel, animated: true)
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
    ///
    /// `dockSide` è esplicito: l'isteresi vive in `resolvedDock`, non qui.
    public nonisolated static func resolvedFrame(
        current: CGRect,
        screenRect: CGRect,
        orientation: PillOrientation,
        isExpanded: Bool,
        isFallback: Bool,
        dockSide: PillDockSide = .center
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

            switch dockSide {
            case .right:
                newOrigin.x = screenRect.maxX - targetSize.width - PillMetrics.screenInset
            case .left:
                newOrigin.x = screenRect.minX + PillMetrics.screenInset
            case .center:
                newOrigin.x = current.midX - targetSize.width / 2
            }
        }

        newOrigin = clampedOrigin(newOrigin, size: targetSize, in: screenRect)
        return CGRect(origin: newOrigin, size: targetSize)
    }

    /// Isteresi del docking: si entra con la soglia bassa, si esce solo
    /// superando quella alta. Deterministica e simmetrica in dock e undock.
    public nonisolated static func resolvedDock(
        previous: PillDockSide,
        leftDist: CGFloat,
        rightDist: CGFloat
    ) -> PillDockSide {
        let enter = PillMetrics.dockThreshold
        let exit = PillMetrics.dockExitThreshold

        switch previous {
        case .left:
            if leftDist <= exit { return .left }
            return rightDist <= enter ? .right : .center
        case .right:
            if rightDist <= exit { return .right }
            return leftDist <= enter ? .left : .center
        case .center:
            if leftDist <= enter { return .left }
            if rightDist <= enter { return .right }
            return .center
        }
    }

    /// Docking durante il drag: le distanze sono quelle del cursore, l'unico
    /// punto che riflette l'intenzione dell'utente. Il frame della finestra è
    /// ingannevole perché la capsula espansa viene clampata al bordo molto
    /// prima che il puntatore ci arrivi.
    public nonisolated static func resolvedLiveDock(
        previous: PillDockSide,
        cursorX: CGFloat,
        screenRect: CGRect
    ) -> PillDockSide {
        resolvedDock(
            previous: previous,
            leftDist: cursorX - screenRect.minX,
            rightDist: screenRect.maxX - cursorX
        )
    }

    /// Variante d'istanza: legge stato di fallback e dock corrente dall'app.
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
            isFallback: appState?.isUsingSpeechFallback ?? false,
            dockSide: appState?.pillDockSide ?? .center
        )
    }

    // MARK: - Docking & orientamento

    public func evaluateDockingAndOrientation(panel: NSPanel, appState: AppState, animated: Bool) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let frame = panel.frame

        let leftDist = frame.minX - screenRect.minX
        let rightDist = screenRect.maxX - frame.maxX
        // Stessa isteresi del drag live: nessun salto di orientamento al rilascio.
        let dock = Self.resolvedDock(
            previous: appState.pillDockSide,
            leftDist: leftDist,
            rightDist: rightDist
        )

        appState.pillOrientation = dock == .center ? .horizontal : .vertical
        appState.pillDockSide = dock

        // Riallinea sempre: copre anche lo snap al bordo quando l'orientamento
        // non cambia ma la pillola va riportata dentro lo schermo.
        let target = Self.resolvedFrame(
            current: frame,
            screenRect: screenRect,
            orientation: appState.pillOrientation,
            isExpanded: appState.isPillExpanded || isHoverExpanded,
            isFallback: appState.isUsingSpeechFallback,
            dockSide: dock
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
