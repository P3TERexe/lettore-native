import SwiftUI
import AppKit
import LettoreCore

/// Componente AppKit nativo per il trascinamento a 120 FPS della pillola fluttuante.
/// Utilizza il tracking loop modale di macOS (`window.nextEvent`) che cattura il cursore
/// globalmente attraverso tutti i monitor, garantendo zero perdita di eventi e zero scatti
/// anche durante movimenti rapidissimi del mouse.
public struct NativeDragHandleView: NSViewRepresentable {
    public var appState: AppState
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public func makeNSView(context: Context) -> NativeDragHandleNSView {
        let view = NativeDragHandleNSView()
        view.appState = appState
        return view
    }
    
    public func updateNSView(_ nsView: NativeDragHandleNSView, context: Context) {
        nsView.appState = appState
    }
}

public final class NativeDragHandleNSView: NSView {
    public var appState: AppState?
    private var trackingArea: NSTrackingArea?
    
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea {
            removeTrackingArea(old)
        }
        let options: NSTrackingArea.Options = [.activeAlways, .cursorUpdate]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }
    
    public override func cursorUpdate(with event: NSEvent) {
        NSCursor.openHand.set()
    }
    
    public override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
    
    public override func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return }
        print("[NativeDragHandleNSView] mouseDown ricevuto! Avvio window.performDrag(with: event)...")
        FloatingPillPanelManager.shared.dragPanelStarted()
        window.performDrag(with: event)
        FloatingPillPanelManager.shared.dragPanelEnded()
        print("[NativeDragHandleNSView] performDrag completato! Nuova origine: \(window.frame.origin)")
    }
}
