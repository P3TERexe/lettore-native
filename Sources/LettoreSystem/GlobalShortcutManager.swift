import Foundation
import AppKit
import LettoreCore

/// Gestore delle scorciatoie da tastiera globali (Global Shortcuts) per intercettare gli input anche quando LettoreApp è in background.
/// Usa solo il monitor GLOBALE (NSEvent.addGlobalMonitorForEvents) per non interferire con la catena eventi interna di SwiftUI.
@MainActor
public final class GlobalShortcutManager {
    
    private var globalMonitor: Any?
    
    /// Azione da eseguire quando l'utente preme Cmd+Shift+C
    public var onCaptureRequested: (() -> Void)?
    
    /// Azione da eseguire quando l'utente preme Option+P
    public var onTogglePlaybackRequested: (() -> Void)?
    
    public init() {}
    
    public var isMonitoring: Bool {
        return globalMonitor != nil
    }
    
    /// Registra il monitor globale degli eventi di sistema.
    /// Funziona SOLO quando l'app NON è in primo piano (il caso d'uso principale: l'utente è su Safari/Word).
    /// Non registra un local monitor per evitare di interferire con la catena eventi di SwiftUI.
    public func startMonitoring() {
        guard globalMonitor == nil else { return }
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        
        if globalMonitor != nil {
            print("[GlobalShortcutManager] Monitor globale eventi registrato con successo.")
        } else {
            print("[GlobalShortcutManager] ⚠️ Impossibile registrare monitor globale (Accessibilità non concessa o TCC non attivo).")
        }
    }
    
    public func stopMonitoring() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        // Cmd+Shift+C → Cattura testo dall'app in primo piano
        if event.keyCode == 8 && flags.contains([.command, .shift]) {
            onCaptureRequested?()
        }
        
        // Option+P → Toggle Play/Pausa
        if event.keyCode == 35 && flags.contains(.option) {
            onTogglePlaybackRequested?()
        }
    }
}
