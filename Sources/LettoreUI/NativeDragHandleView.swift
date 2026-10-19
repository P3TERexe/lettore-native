import SwiftUI
import AppKit
import LettoreCore

/// Area del grip della pillola. È un'ancora visiva e di cursore per il drag.
/// La logica non è duplicata: sia il grip sia l'hosting view chiamano lo stesso
/// ingresso del manager (`beginPanelDrag`), che annulla l'animazione di frame e
/// delega a `performDrag`.
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

    /// Il grip è un entry point del drag, ma la logica vive tutta nel manager:
    /// stesso lifecycle manuale, stessa soglia di tap, stesso morphing live.
    public override func mouseDown(with event: NSEvent) {
        guard self.window != nil else { return }
        let manager = FloatingPillPanelManager.shared

        manager.beginPanelDrag(atMouseLocation: NSEvent.mouseLocation) { distance in
            if distance < FloatingPillPanelManager.PillMetrics.tapThreshold {
                manager.dragPanelCancelled()
            } else {
                manager.dragPanelEnded()
            }
        }
    }
}
