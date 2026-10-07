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
        
        if isVertical {
            if isExpanded {
                // In verticale espanso:
                // Se il click è sotto il grip superiore (y <= bounds.height - 28), passa l'evento ai bottoni SwiftUI
                if loc.y <= bounds.height - 28 {
                    super.mouseDown(with: event)
                    return
                }
            } else {
                // In verticale compatto:
                // Waveform e play mini-button sono tra y = 14 e y = bounds.height - 22
                if loc.y >= 14 && loc.y <= bounds.height - 22 {
                    super.mouseDown(with: event)
                    return
                }
            }
        } else {
            if isExpanded {
                // In orizzontale espanso: controlli interattivi a destra (x > 70)
                if loc.x > 70 {
                    super.mouseDown(with: event)
                    return
                }
            } else {
                // In orizzontale compatto: waveform al centro (x tra 24 e 80)
                if loc.x >= 24 && loc.x <= 80 {
                    super.mouseDown(with: event)
                    return
                }
            }
        }
        
        // Avvia il trascinamento nativo macOS con accelerazione hardware
        print("[DraggablePillHostingView] Avvio drag nativo da: \(loc)")
        FloatingPillPanelManager.shared.dragPanelStarted()
        window.performDrag(with: event)
        FloatingPillPanelManager.shared.dragPanelEnded()
        print("[DraggablePillHostingView] Drag completato a: \(window.frame.origin)")
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
                if !self.isDragging {
                    self.evaluateDockingAndOrientation(panel: panel, appState: appState, animated: false)
                }
            }
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
    }
    
    public func dragPanelEnded() {
        isDragging = false
        if let appState = self.appState, let panel = self.panel {
            evaluateDockingAndOrientation(panel: panel, appState: appState, animated: true)
        }
    }
    
    public func finishDrag(appState: AppState) {
        print("[FloatingPillPanel] Fine drag. Posizione finale: \(panel?.frame.origin ?? .zero)")
        isDragging = false
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
            let midX = currentFrame.midX
            newOrigin.x = midX - (targetSize.width / 2)
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
        
        // Mantieni all'interno dei limiti dello schermo visibile
        newOrigin.x = max(screenRect.minX + 4, min(screenRect.maxX - targetSize.width - 4, newOrigin.x))
        newOrigin.y = max(screenRect.minY + 8, min(screenRect.maxY - targetSize.height - 8, newOrigin.y))
        
        let newFrame = NSRect(origin: newOrigin, size: targetSize)
        if panel.frame != newFrame {
            panel.setFrame(newFrame, display: true, animate: animated)
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
        // Isteresi bilanciata ed ergonomica:
        // - Se orizzontale, basta spostarla a ridosso dell'estremo bordo (<= 35px) per agganciarla in verticale
        // - Se già verticale, basta allontanarla di oltre 50px verso l'interno per sganciarsi e tornare orizzontale
        let dockThreshold: CGFloat = isCurrentlyVertical ? 50.0 : 35.0
        
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
        
        let orientationChanged = (appState.pillOrientation != newOrientation)
        let dockSideChanged = (appState.pillDockSide != newDockSide)
        
        if orientationChanged || dockSideChanged {
            withAnimation(animated ? .spring(response: 0.38, dampingFraction: 0.78) : nil) {
                appState.pillOrientation = newOrientation
                appState.pillDockSide = newDockSide
            }
            updatePanelFrame(for: newOrientation, isExpanded: appState.isPillExpanded, animated: animated)
        } else if isCurrentlyVertical {
            snapToVerticalEdge(panel: panel, dockSide: newDockSide, animated: animated)
        }
    }
    
    private func snapToVerticalEdge(panel: NSPanel, dockSide: PillDockSide, animated: Bool) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        var currentFrame = panel.frame
        let targetX: CGFloat
        if dockSide == .left {
            targetX = screenRect.minX + 8
        } else if dockSide == .right {
            targetX = screenRect.maxX - currentFrame.width - 8
        } else {
            return
        }
        if abs(currentFrame.origin.x - targetX) > 1 {
            currentFrame.origin.x = targetX
            panel.setFrame(currentFrame, display: true, animate: animated)
        }
    }
    
    public func updateDockSide(panel: NSPanel, appState: AppState) {
        evaluateDockingAndOrientation(panel: panel, appState: appState, animated: false)
    }
    
    public func updateOrientation(panel: NSPanel, appState: AppState) {
        evaluateDockingAndOrientation(panel: panel, appState: appState, animated: true)
    }
}
