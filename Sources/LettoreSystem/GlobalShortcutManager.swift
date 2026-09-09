import Foundation
import AppKit
import LettoreCore

/// Gestore delle scorciatoie da tastiera globali (Global Shortcuts) per intercettare gli input anche quando LettoreApp è in background.
@MainActor
public final class GlobalShortcutManager {
    
    private var globalEventMonitor: Any?
    
    /// Azione da eseguire quando l'utente preme Cmd+Shift+C
    public var onCaptureRequested: (() -> Void)?
    
    /// Azione da eseguire quando l'utente preme Option+P
    public var onTogglePlaybackRequested: (() -> Void)?
    
    public init() {}
    
    /// Registra i monitor degli eventi di sistema.
    /// Richiede che l'applicazione abbia i permessi di Accessibilità concessi in Impostazioni di Sistema.
    public func startMonitoring() {
        if globalEventMonitor != nil { return }
        
        // Ascolta gli eventi keyDown globali (quando l'app NON è in primo piano)
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        
        // Ascolta gli eventi keyDown locali (quando l'app È in primo piano)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil // L'evento è stato consumato
            }
            return event
        }
    }
    
    public func stopMonitoring() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
    }
    
    /// Rileva e smista gli hotkey
    /// - Returns: true se l'evento è stato consumato (per il local monitor)
    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode
        
        // KeyCode 8 = 'C', Modificatori = Cmd + Shift
        if keyCode == 8 && modifierFlags.contains([.command, .shift]) {
            onCaptureRequested?()
            return true
        }
        
        // KeyCode 35 = 'P', Modificatori = Option (Alternate)
        if keyCode == 35 && modifierFlags.contains(.option) {
            onTogglePlaybackRequested?()
            return true
        }
        
        return false
    }
}
