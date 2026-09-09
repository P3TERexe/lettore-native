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
            return
        }
        
        let pillView = FloatingPillView(appState: appState, audioEngine: audioEngine, coordinator: coordinator)
            .padding(40) // Spazio abbondante per non tagliare le ombre
        
        let hostingView = NSHostingView(rootView: pillView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        // Finestra molto più grande della pillola per ospitare l'ampio raggio dell'ombra
        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 160),
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
            let xPos = screenRect.midX - 300
            let yPos = screenRect.maxY - 160
            newPanel.setFrameOrigin(NSPoint(x: xPos, y: yPos))
        }
        
        newPanel.makeKeyAndOrderFront(nil)
        self.panel = newPanel
    }
    
    public func hide() {
        panel?.orderOut(nil)
    }
}
