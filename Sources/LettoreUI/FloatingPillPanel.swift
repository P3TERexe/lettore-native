import SwiftUI
import AppKit
import LettoreCore
import LettoreEngine

/// Controller per la finestra fluttuante borderless (NSPanel) della Pillola.
/// Permette alla pillola di fluttuare libera sopra qualsiasi finestra di macOS (Safari, Word, Xcode)
/// senza alcun bordo di finestra, titolo o sfondo grigio, garantendo il passaggio dei click alle app sottostanti.
@MainActor
public final class FloatingPillPanelManager {
    public static let shared = FloatingPillPanelManager()
    
    public private(set) var panel: NSPanel?
    private var moveObserver: AnyObject?
    private var initialDragOrigin: NSPoint?
    
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
            updateOrientation(panel: existing, appState: appState)
            updatePanelFrame(for: appState.pillOrientation, isExpanded: appState.isPillExpanded, animated: false)
            return
        }
        
        let pillView = FloatingPillView(
            appState: appState,
            audioEngine: audioEngine,
            coordinator: coordinator,
            isStandalone: true
        )
        
        let hostingView = NSHostingView(rootView: pillView)
        hostingView.autoresizingMask = [.width, .height]
        
        // Dimensioni iniziali compatte per non bloccare lo schermo
        let initialSize = NSSize(width: 170, height: 76)
        let newPanel = NSPanel(
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
        // Disabilitiamo il drag cieco sullo sfondo dell'intera finestra per evitare che click
        // trasparenti blocchino le app sottostanti. Il drag viene gestito esplicitamente dal grip/capsula della pillola.
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
        
        updateOrientation(panel: newPanel, appState: appState)
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
                self.updateOrientation(panel: panel, appState: appState)
            }
        }
    }
    
    // MARK: - Gestione Drag Fluido & Diretto
    
    public func dragPanel(deltaX: CGFloat, deltaY: CGFloat) {
        guard let panel = panel else { return }
        if initialDragOrigin == nil {
            initialDragOrigin = panel.frame.origin
        }
        guard let start = initialDragOrigin else { return }
        // Coordinate macOS: Y cresce verso l'alto; DragGesture deltaY positivo verso il basso.
        let newX = start.x + deltaX
        let newY = start.y - deltaY
        panel.setFrameOrigin(NSPoint(x: newX, y: newY))
    }
    
    public func finishDrag(appState: AppState) {
        guard let panel = panel else { return }
        initialDragOrigin = nil
        updateOrientation(panel: panel, appState: appState)
    }
    
    // MARK: - Adattamento Dinamico Dimensioni NSPanel
    
    public func updatePanelFrame(for orientation: PillOrientation, isExpanded: Bool, animated: Bool = true) {
        guard let panel = panel, let screen = panel.screen ?? NSScreen.main else { return }
        let currentFrame = panel.frame
        
        let targetSize: NSSize
        switch orientation {
        case .horizontal:
            targetSize = isExpanded ? NSSize(width: 400, height: 76) : NSSize(width: 170, height: 76)
        case .vertical:
            targetSize = isExpanded ? NSSize(width: 88, height: 260) : NSSize(width: 88, height: 88)
        }
        
        var newOrigin = currentFrame.origin
        switch orientation {
        case .horizontal:
            // Centra orizzontalmente rispetto alla posizione corrente
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
    
    // MARK: - Orientamento & Docking
    
    public func updateOrientation(panel: NSPanel, appState: AppState) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame
        let midX = panelFrame.midX
        let screenWidth = screenFrame.width
        
        // Isteresi per evitare sfarfallii vicino al confine tra centro e lati
        let isCurrentlyVertical = appState.pillOrientation == .vertical
        let sideRatio: CGFloat = isCurrentlyVertical ? 0.28 : 0.22
        let leftThreshold = screenFrame.minX + screenWidth * sideRatio
        let rightThreshold = screenFrame.maxX - screenWidth * sideRatio
        
        let newOrientation: PillOrientation
        let newDockSide: PillDockSide
        
        if midX < leftThreshold {
            newOrientation = .vertical
            newDockSide = .left
        } else if midX > rightThreshold {
            newOrientation = .vertical
            newDockSide = .right
        } else {
            newOrientation = .horizontal
            newDockSide = .center
        }
        
        if appState.pillOrientation != newOrientation || appState.pillDockSide != newDockSide {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
                appState.pillOrientation = newOrientation
                appState.pillDockSide = newDockSide
            }
            updatePanelFrame(for: newOrientation, isExpanded: appState.isPillExpanded, animated: true)
        }
    }
}
