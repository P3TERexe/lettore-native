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
    public override func mouseDown(with event: NSEvent) {
        guard let window = self.window else {
            super.mouseDown(with: event)
            return
        }
        
        let loc = event.locationInWindow
        let isExpanded = bounds.width > 120
        
        // Se la pillola è espansa e il click cade sui controlli a destra, passa l'evento ai bottoni SwiftUI
        if isExpanded && loc.x > 75 {
            super.mouseDown(with: event)
            return
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
        appState.isFloatingPillVisible = true
        
        if let existing = panel {
            ensureMoveObserver(panel: existing, appState: appState)
            existing.makeKeyAndOrderFront(nil)
            updateDockSide(panel: existing, appState: appState)
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
        
        updateDockSide(panel: newPanel, appState: appState)
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
                self.updateDockSide(panel: panel, appState: appState)
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
    }
    
    public func finishDrag(appState: AppState) {
        print("[FloatingPillPanel] Fine drag. Posizione finale: \(panel?.frame.origin ?? .zero)")
        isDragging = false
        initialMouseScreenLocation = nil
        initialWindowOrigin = nil
        if let panel = panel {
            updateDockSide(panel: panel, appState: appState)
        }
    }
    
    // MARK: - Adattamento Dimensioni Dinamiche NSPanel
    
    public func updatePanelFrame(for orientation: PillOrientation, isExpanded: Bool, animated: Bool = true) {
        // Se l'utente sta trascinando la pillola, blocca modifiche al frame per evitare scatti improvvisi
        if isDragging { return }
        guard let panel = panel, let screen = panel.screen ?? NSScreen.main else { return }
        let currentFrame = panel.frame
        
        let targetSize: NSSize
        switch orientation {
        case .horizontal:
            targetSize = isExpanded ? NSSize(width: 295, height: 42) : NSSize(width: 104, height: 42)
        case .vertical:
            targetSize = isExpanded ? NSSize(width: 50, height: 215) : NSSize(width: 50, height: 50)
        }
        
        var newOrigin = currentFrame.origin
        switch orientation {
        case .horizontal:
            let midX = currentFrame.midX
            newOrigin.x = midX - (targetSize.width / 2)
            let topY = currentFrame.maxY
            newOrigin.y = topY - targetSize.height
        case .vertical:
            let topY = currentFrame.maxY
            newOrigin.y = topY - targetSize.height
            if currentFrame.midX > screen.visibleFrame.midX {
                let rightX = currentFrame.maxX
                newOrigin.x = rightX - targetSize.width
            }
        }
        
        // Mantieni all'interno dei limiti dello schermo visibile
        let screenRect = screen.visibleFrame
        newOrigin.x = max(screenRect.minX, min(screenRect.maxX - targetSize.width, newOrigin.x))
        newOrigin.y = max(screenRect.minY, min(screenRect.maxY - targetSize.height, newOrigin.y))
        
        let newFrame = NSRect(origin: newOrigin, size: targetSize)
        if panel.frame != newFrame {
            panel.setFrame(newFrame, display: true, animate: animated)
        }
    }
    
    // MARK: - Docking & Posizione (Senza cambi forzati di orientamento)
    
    public func updateDockSide(panel: NSPanel, appState: AppState) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame
        let midX = panelFrame.midX
        let screenWidth = screenFrame.width
        
        let leftThreshold = screenFrame.minX + screenWidth * 0.33
        let rightThreshold = screenFrame.maxX - screenWidth * 0.33
        
        let newDockSide: PillDockSide
        if midX < leftThreshold {
            newDockSide = .left
        } else if midX > rightThreshold {
            newDockSide = .right
        } else {
            newDockSide = .center
        }
        
        if appState.pillDockSide != newDockSide {
            appState.pillDockSide = newDockSide
        }
    }
    
    public func updateOrientation(panel: NSPanel, appState: AppState) {
        updateDockSide(panel: panel, appState: appState)
    }
}
