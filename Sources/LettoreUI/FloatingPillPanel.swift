import SwiftUI
import AppKit
import LettoreCore
import LettoreEngine

/// Controller per la finestra fluttuante borderless (NSPanel) della Pillola.
/// Permette alla pillola di fluttuare libera sopra qualsiasi finestra di macOS (Safari, Word, Xcode)
/// senza alcun bordo di finestra, titolo o sfondo grigio.
@MainActor
public final class FloatingPillPanelManager {
    public static let shared = FloatingPillPanelManager()
    
    private var panel: NSPanel?
    private var moveObserver: AnyObject?
    
    private init() {}
    
    public func toggle(appState: AppState, audioEngine: AudioEngineService, coordinator: PlaybackCoordinator? = nil) {
        if let existing = panel, existing.isVisible {
            existing.orderOut(nil)
            return
        }
        show(appState: appState, audioEngine: audioEngine, coordinator: coordinator)
    }
    
    public func show(appState: AppState, audioEngine: AudioEngineService, coordinator: PlaybackCoordinator? = nil) {
        if let existing = panel {
            existing.makeKeyAndOrderFront(nil)
            updateOrientation(panel: existing, appState: appState)
            return
        }
        
        let pillView = FloatingPillView(appState: appState, audioEngine: audioEngine, coordinator: coordinator)
            .padding(40) // Spazio per le ombre soffuse
        
        let hostingView = NSHostingView(rootView: pillView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        // Dimensione 440x440 che accoglie sia l'espansione orizzontale (356x44) sia verticale (52x310)
        let panelDimension: CGFloat = 440
        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelDimension, height: panelDimension),
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
        newPanel.isMovableByWindowBackground = true
        newPanel.contentView = hostingView
        
        // Posiziona la pillola in alto al centro dello schermo principale
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let xPos = screenRect.midX - (panelDimension / 2)
            let yPos = screenRect.maxY - (panelDimension / 2) - 20
            newPanel.setFrameOrigin(NSPoint(x: xPos, y: yPos))
        }
        
        // Osserva i movimenti della finestra per adattare reattivamente l'orientamento
        if let oldObs = moveObserver {
            NotificationCenter.default.removeObserver(oldObs)
        }
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: newPanel,
            queue: .main
        ) { [weak self, weak appState, weak newPanel] _ in
            MainActor.assumeIsolated {
                guard let self = self, let panel = newPanel, let appState = appState else { return }
                self.updateOrientation(panel: panel, appState: appState)
            }
        }
        
        newPanel.makeKeyAndOrderFront(nil)
        self.panel = newPanel
        
        updateOrientation(panel: newPanel, appState: appState)
    }
    
    public func hide() {
        if let obs = moveObserver {
            NotificationCenter.default.removeObserver(obs)
            moveObserver = nil
        }
        panel?.orderOut(nil)
    }
    
    /// Calcola la posizione della pillola rispetto allo schermo e imposta orientamento orizzontale o verticale
    public func updateOrientation(panel: NSPanel, appState: AppState) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame
        let midX = panelFrame.midX
        let screenWidth = screenFrame.width
        
        // Isteresi per evitare sfarfallii vicino al confine tra centro e lati
        let isCurrentlyVertical = appState.pillOrientation == .vertical
        let sideRatio: CGFloat = isCurrentlyVertical ? 0.30 : 0.25
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
        }
    }
}
