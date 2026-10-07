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
    
    public override func mouseDown(with event: NSEvent) {
        guard let window = self.window else {
            super.mouseDown(with: event)
            return
        }
        
        let loc = event.locationInWindow
        let isExpanded = (appState?.isPillExpanded ?? false) || bounds.width > 120 || bounds.height > 120
        let isVertical = (appState?.pillOrientation == .vertical)
        
        if isExpanded {
            // In modalità espansa: passa i click sui controlli interattivi a SwiftUI
            if isVertical {
                // Sotto il grip superiore (y <= bounds.height - 24): controlli interattivi
                if loc.y <= bounds.height - 24 {
                    super.mouseDown(with: event)
                    return
                }
            } else {
                // A destra del grip (x > 50): controlli interattivi
                if loc.x > 50 {
                    super.mouseDown(with: event)
                    return
                }
            }
        }
        
        // In modalità compatta (o sull'area grip in espansa):
        // Tutto il corpo della pillola è reattivo al trascinamento hardware a 120 FPS
        let startOrigin = window.frame.origin
        FloatingPillPanelManager.shared.dragPanelStarted()
        window.performDrag(with: event)
        let endOrigin = window.frame.origin
        
        let dist = hypot(endOrigin.x - startOrigin.x, endOrigin.y - startOrigin.y)
        if dist < 3.0 && !isExpanded {
            // Click/tap sul posto senza trascinamento: attiva Play/Pausa
            FloatingPillPanelManager.shared.dragPanelCancelled()
            NotificationCenter.default.post(name: NSNotification.Name("FloatingPillTogglePlayPause"), object: nil)
        } else {
            // Trascinamento completato: valuta docking ed orientamento
            FloatingPillPanelManager.shared.dragPanelEnded()
        }
    }
}

/// Controller per la finestra fluttuante borderless (NSPanel) della Pillola.
/// Permette alla pillola di fluttuare libera sopra qualsiasi finestra di macOS (Safari, Word, Xcode)
/// con dimensioni minime al millimetro, zero spazio vuoto extra e trascinamento istantaneo e fluido.
@MainActor
public final class FloatingPillPanelManager {
    public static let shared = FloatingPillPanelManager()
    
    public private(set) var panel: NSPanel?
    public private(set) var isDragging: Bool = false
    public private(set) var isAnimatingFrame: Bool = false
    public weak var appState: AppState?
    private var moveObserver: AnyObject?
    private var initialMouseScreenLocation: NSPoint?
    private var initialWindowOrigin: NSPoint?
    
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
        
        if let existing = panel {
            ensureMoveObserver(panel: existing, appState: appState)
            existing.makeKeyAndOrderFront(nil)
            evaluateDockingAndOrientation(panel: existing, appState: appState, animated: false)
            updatePanelFrame(for: appState.pillOrientation, isExpanded: appState.isPillExpanded, animated: false)
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
        
        // Dimensioni millimetriche esatte della pillola compatta iniziale: zero spazio vuoto
        let initialSize = NSSize(width: 104, height: 42)
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
        
        // Posiziona la pillola in alto al centro dello schermo principale
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let xPos = screenRect.midX - (initialSize.width / 2)
            let yPos = screenRect.maxY - initialSize.height - 12
            newPanel.setFrameOrigin(NSPoint(x: xPos, y: yPos))
        }
        
        self.panel = newPanel
        ensureMoveObserver(panel: newPanel, appState: appState)
        newPanel.makeKeyAndOrderFront(nil)
        
        evaluateDockingAndOrientation(panel: newPanel, appState: appState, animated: false)
        updatePanelFrame(for: appState.pillOrientation, isExpanded: appState.isPillExpanded, animated: false)
    }
    
    public func hide(appState: AppState? = nil) {
        panel?.orderOut(nil)
        appState?.isFloatingPillVisible = false
    }
    
    private func ensureMoveObserver(panel: NSPanel, appState: AppState) {
        if let oldObs = moveObserver {
            NotificationCenter.default.removeObserver(oldObs)
            moveObserver = nil
        }
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self, weak appState, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self = self, let panel = panel, let appState = appState else { return }
                // IMPORTANTE: non invocare MAI evaluateDockingAndOrientation o setFrame
                // durante didMoveNotification per prevenire cicli ricorsivi durante le animazioni!
                self.updateInformationalDockSide(panel: panel, appState: appState)
            }
        }
    }
    
    private func updateInformationalDockSide(panel: NSPanel, appState: AppState) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let midX = panel.frame.midX
        let side: PillDockSide
        if midX < screenFrame.minX + (screenFrame.width * 0.33) {
            side = .left
        } else if midX > screenFrame.maxX - (screenFrame.width * 0.33) {
            side = .right
        } else {
            side = .center
        }
        if appState.pillDockSide != side && appState.pillOrientation != .vertical {
            appState.pillDockSide = side
        }
    }
    
    // MARK: - Gestione Drag Fluido & Diretto a Coordinate Schermo Globali
    
    public func dragPanelWithCurrentMouse() {
        guard let panel = panel else { return }
        let currentMouse = NSEvent.mouseLocation
        
        if initialMouseScreenLocation == nil || initialWindowOrigin == nil {
            initialMouseScreenLocation = currentMouse
            initialWindowOrigin = panel.frame.origin
            isDragging = true
            print("[FloatingPillPanel] Inizio drag da mouse: \(currentMouse), origine: \(panel.frame.origin)")
        }
        
        guard let startMouse = initialMouseScreenLocation,
              let startOrigin = initialWindowOrigin else { return }
              
        let deltaX = currentMouse.x - startMouse.x
        let deltaY = currentMouse.y - startMouse.y
        
        var newOrigin = NSPoint(x: startOrigin.x + deltaX, y: startOrigin.y + deltaY)
        
        // Mantieni all'interno dei limiti dello schermo visibile per non perdere mai la pillola
        if let screen = panel.screen ?? NSScreen.main {
            let screenRect = screen.visibleFrame
            let maxX = screenRect.maxX - panel.frame.width
            let maxY = screenRect.maxY - panel.frame.height
            newOrigin.x = max(screenRect.minX, min(maxX, newOrigin.x))
            newOrigin.y = max(screenRect.minY, min(maxY, newOrigin.y))
        }
        
        panel.setFrameOrigin(newOrigin)
        print("[FloatingPillPanel] Muove a nuova origine: \(newOrigin) (delta: \(deltaX), \(deltaY))")
    }
    
    public func dragPanel(deltaX: CGFloat, deltaY: CGFloat) {
        dragPanelWithCurrentMouse()
    }
    
    public func dragPanelStarted() {
        isDragging = true
        isAnimatingFrame = false
    }
    
    public func dragPanelEnded() {
        isDragging = false
        if let appState = self.appState, let panel = self.panel {
            evaluateDockingAndOrientation(panel: panel, appState: appState, animated: true)
        }
    }
    
    public func dragPanelCancelled() {
        isDragging = false
        initialMouseScreenLocation = nil
        initialWindowOrigin = nil
    }
    
    public func finishDrag(appState: AppState) {
        print("[FloatingPillPanel] Fine drag. Posizione finale: \(panel?.frame.origin ?? .zero)")
        isDragging = false
        isAnimatingFrame = false
        initialMouseScreenLocation = nil
        initialWindowOrigin = nil
        if let panel = panel {
            evaluateDockingAndOrientation(panel: panel, appState: appState, animated: true)
        }
    }
    
    // MARK: - Adattamento Dimensioni Dinamiche NSPanel
    
    public func updatePanelFrame(for orientation: PillOrientation, isExpanded: Bool, animated: Bool = true) {
        // Se l'utente sta trascinando attivamente la pillola, blocca modifiche al frame per evitare scatti
        if isDragging { return }
        guard let panel = panel, let screen = panel.screen ?? NSScreen.main else { return }
        let currentFrame = panel.frame
        let screenRect = screen.visibleFrame
        
        let targetSize: NSSize
        switch orientation {
        case .horizontal:
            let width: CGFloat = isExpanded ? (appState?.isUsingSpeechFallback == true ? 298 : 282) : 104
            targetSize = NSSize(width: width, height: 42)
        case .vertical:
            let height: CGFloat = isExpanded ? (appState?.isUsingSpeechFallback == true ? 192 : 170) : 104
            targetSize = NSSize(width: 48, height: height)
        }
        
        var newOrigin = currentFrame.origin
        switch orientation {
        case .horizontal:
            // Se veniamo da verticale ancorata a destra, espanditi verso l'interno sinistro dello schermo!
            if appState?.pillDockSide == .right || currentFrame.midX > screenRect.midX {
                newOrigin.x = currentFrame.maxX - targetSize.width
            } else if appState?.pillDockSide == .left {
                // Se veniamo da verticale ancorata a sinistra, mantieni l'ancoraggio a sinistra
                newOrigin.x = currentFrame.minX
            } else {
                let midX = currentFrame.midX
                newOrigin.x = midX - (targetSize.width / 2)
            }
            
            // Per la coordinata Y, mantieni il centro verticale dell'elemento
            if currentFrame.height > 60 {
                newOrigin.y = currentFrame.midY - (targetSize.height / 2)
            } else {
                let topY = currentFrame.maxY
                newOrigin.y = topY - targetSize.height
            }
            
        case .vertical:
            let topY = currentFrame.maxY
            newOrigin.y = topY - targetSize.height
            if appState?.pillDockSide == .right || currentFrame.midX > screenRect.midX {
                newOrigin.x = screenRect.maxX - targetSize.width - 8
            } else {
                newOrigin.x = screenRect.minX + 8
            }
        }
        
        // VINCOLO ASSOLUTO: Mantieni l'intero frame rigorosamente all'interno dello schermo visibile
        let minAllowedX = screenRect.minX + 8
        let maxAllowedX = screenRect.maxX - targetSize.width - 8
        let minAllowedY = screenRect.minY + 8
        let maxAllowedY = screenRect.maxY - targetSize.height - 8
        
        newOrigin.x = max(minAllowedX, min(maxAllowedX, newOrigin.x))
        newOrigin.y = max(minAllowedY, min(maxAllowedY, newOrigin.y))
        
        let newFrame = NSRect(origin: newOrigin, size: targetSize)
        if panel.frame != newFrame {
            if animated {
                self.isAnimatingFrame = true
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.28
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.animator().setFrame(newFrame, display: true)
                }, completionHandler: { [weak self] in
                    MainActor.assumeIsolated {
                        self?.isAnimatingFrame = false
                    }
                })
            } else {
                panel.setFrame(newFrame, display: true)
                self.isAnimatingFrame = false
            }
        }
    }
    
    // MARK: - Docking Naturale & Rilevamento Bordi Schermo
    
    public func evaluateDockingAndOrientation(panel: NSPanel, appState: AppState, animated: Bool) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame
        
        let leftDist = panelFrame.minX - screenFrame.minX
        let rightDist = screenFrame.maxX - panelFrame.maxX
        
        let isCurrentlyVertical = (appState.pillOrientation == .vertical)
        
        // Soglie di aggancio ergonomiche e naturali:
        // - Per agganciarsi ai bordi in verticale: basta rilasciare la pillola entro 90px dal bordo
        // - Per sganciarsi dal bordo e tornare orizzontale: basta allontanarla di oltre 130px verso l'interno
        let dockThreshold: CGFloat = isCurrentlyVertical ? 130.0 : 90.0
        
        let newOrientation: PillOrientation
        let newDockSide: PillDockSide
        
        if leftDist <= dockThreshold {
            newOrientation = .vertical
            newDockSide = .left
        } else if rightDist <= dockThreshold {
            newOrientation = .vertical
            newDockSide = .right
        } else {
            newOrientation = .horizontal
            newDockSide = .center
        }
        
        print("[FloatingPillPanel] evaluateDockingAndOrientation -> leftDist: \(leftDist), rightDist: \(rightDist), dockThreshold: \(dockThreshold), current: \(appState.pillOrientation), new: \(newOrientation), dockSide: \(newDockSide)")
        
        let orientationChanged = (appState.pillOrientation != newOrientation)
        let dockSideChanged = (appState.pillDockSide != newDockSide)
        
        if orientationChanged || dockSideChanged {
            withAnimation(animated ? .spring(response: 0.28, dampingFraction: 0.82) : nil) {
                appState.pillOrientation = newOrientation
                appState.pillDockSide = newDockSide
            }
            updatePanelFrame(for: newOrientation, isExpanded: appState.isPillExpanded, animated: animated)
        } else if isCurrentlyVertical {
            snapToVerticalEdge(panel: panel, dockSide: newDockSide, animated: animated)
        } else {
            clampFrameInsideScreen(panel: panel, animated: animated)
        }
    }
    
    private func snapToVerticalEdge(panel: NSPanel, dockSide: PillDockSide, animated: Bool) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let currentFrame = panel.frame
        let targetX: CGFloat
        if dockSide == .left {
            targetX = screenRect.minX + 8
        } else if dockSide == .right {
            targetX = screenRect.maxX - currentFrame.width - 8
        } else {
            return
        }
        
        let minY = screenRect.minY + 8
        let maxY = screenRect.maxY - currentFrame.height - 8
        let targetY = max(minY, min(maxY, currentFrame.origin.y))
        
        if abs(currentFrame.origin.x - targetX) > 1 || abs(currentFrame.origin.y - targetY) > 1 {
            let clampedFrame = NSRect(x: targetX, y: targetY, width: currentFrame.width, height: currentFrame.height)
            if animated {
                self.isAnimatingFrame = true
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.22
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().setFrame(clampedFrame, display: true)
                }, completionHandler: { [weak self] in
                    MainActor.assumeIsolated {
                        self?.isAnimatingFrame = false
                    }
                })
            } else {
                panel.setFrame(clampedFrame, display: true)
                self.isAnimatingFrame = false
            }
        }
    }
    
    private func clampFrameInsideScreen(panel: NSPanel, animated: Bool) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let currentFrame = panel.frame
        
        let minX = screenRect.minX + 8
        let maxX = screenRect.maxX - currentFrame.width - 8
        let minY = screenRect.minY + 8
        let maxY = screenRect.maxY - currentFrame.height - 8
        
        let targetX = max(minX, min(maxX, currentFrame.origin.x))
        let targetY = max(minY, min(maxY, currentFrame.origin.y))
        
        if abs(currentFrame.origin.x - targetX) > 1 || abs(currentFrame.origin.y - targetY) > 1 {
            let clampedFrame = NSRect(x: targetX, y: targetY, width: currentFrame.width, height: currentFrame.height)
            if animated {
                self.isAnimatingFrame = true
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.20
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().setFrame(clampedFrame, display: true)
                }, completionHandler: { [weak self] in
                    MainActor.assumeIsolated {
                        self?.isAnimatingFrame = false
                    }
                })
            } else {
                panel.setFrame(clampedFrame, display: true)
                self.isAnimatingFrame = false
            }
        }
    }
    
    public func updateDockSide(panel: NSPanel, appState: AppState) {
        evaluateDockingAndOrientation(panel: panel, appState: appState, animated: false)
    }
    
    public func updateOrientation(panel: NSPanel, appState: AppState) {
        evaluateDockingAndOrientation(panel: panel, appState: appState, animated: true)
    }
}
