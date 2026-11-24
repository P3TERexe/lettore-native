import Foundation
import AppKit
import LettoreCore

/// Scorciatoie gestite dal monitor locale (Lettore in primo piano).
enum LocalShortcut {
    case capture
    case togglePlayback
}

/// Gestore delle scorciatoie da tastiera di Lettore.
/// Usa due monitor di `NSEvent`:
/// - **globale** (`addGlobalMonitorForEvents`), per intercettare i tasti quando
///   Lettore è in background (il caso d'uso principale: l'utente è su Safari/Word);
/// - **locale** (`addLocalMonitorForEvents`), per gli stessi tasti quando Lettore
///   è in primo piano: senza di esso gli hint mostrati nello Studio e nel profilo
///   Bassa Visione non funzionerebbero.
/// Il monitor locale non gestisce `⌘⇧L`: quel comando resta al menu di
/// SwiftUI, che lo esegue già quando l'app è attiva (gestirlo anche qui
/// produrrebbe un doppio trigger).
@MainActor
public final class GlobalShortcutManager {
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    
    /// Azione da eseguire quando l'utente preme Cmd+Shift+C
    public var onCaptureRequested: (() -> Void)?
    
    /// Azione da eseguire quando l'utente preme Option+P
    public var onTogglePlaybackRequested: (() -> Void)?

    /// Azione da eseguire quando l'utente preme Cmd+Shift+L
    public var onToggleContinuousReadingRequested: (() -> Void)?
    
    public init() {}
    
    /// `true` solo quando entrambi i monitor sono attivi: il monitor globale
    /// può mancare se l'Accessibilità non è concessa, il locale se non è stato
    /// ancora registrato.
    public var isMonitoring: Bool {
        return globalMonitor != nil && localMonitor != nil
    }
    
    /// Registra il monitor globale (app in background) e quello locale (app in
    /// primo piano). Ogni monitor viene installato una sola volta e in modo
    /// indipendente: se manca l'Accessibilità il locale funziona comunque e un
    /// successivo `startMonitoring` ritenta solo il globale.
    public func startMonitoring() {
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handleLocalKeyEvent(event) ? nil : event
            }
            if localMonitor != nil {
                print("[GlobalShortcutManager] Monitor locale eventi registrato con successo.")
            } else {
                print("[GlobalShortcutManager] ⚠️ Impossibile registrare monitor locale.")
            }
        }
        
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyEvent(event)
            }
            if globalMonitor != nil {
                print("[GlobalShortcutManager] Monitor globale eventi registrato con successo.")
            } else {
                print("[GlobalShortcutManager] ⚠️ Impossibile registrare monitor globale (Accessibilità non concessa o TCC non attivo).")
            }
        }
    }
    
    public func stopMonitoring() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        // La pressione prolungata genera ripetizioni: una sola cattura o un
        // solo toggle per gesto.
        guard !event.isARepeat else { return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        // Cmd+Shift+C → Cattura testo dall'app in primo piano
        if event.keyCode == 8 && flags.contains([.command, .shift]) {
            ProgrammaticInputGate.suppress()
            onCaptureRequested?()
        }
        
        // Option+P → Toggle Play/Pausa
        if event.keyCode == 35 && flags.contains(.option) {
            ProgrammaticInputGate.suppress()
            onTogglePlaybackRequested?()
        }

        // Cmd+Shift+L → Toggle Lettura continua (DSA-11)
        if event.keyCode == 37 && flags.contains([.command, .shift]) {
            ProgrammaticInputGate.suppress()
            onToggleContinuousReadingRequested?()
        }
    }

    /// Gestisce i tasti quando Lettore è in primo piano.
    /// Ritorna `true` solo se l'evento è stato gestito: in quel caso il chiamante
    /// lo consuma (`nil`), altrimenti l'evento prosegue nella catena normale
    /// (menu, campi di testo, SwiftUI).
    private func handleLocalKeyEvent(_ event: NSEvent) -> Bool {
        // Le sequenze generate da Lettore (PageDown del paging, Cmd+C del
        // fallback clipboard) non sono input dell'utente.
        guard !ProgrammaticInputGate.isSuppressed() else { return false }
        guard !event.isARepeat else { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch Self.localShortcut(forKeyCode: event.keyCode, flags: flags) {
        case .capture:
            // Cmd+Shift+C → Cattura testo
            ProgrammaticInputGate.suppress()
            onCaptureRequested?()
            return true
        case .togglePlayback:
            // Option+P → Toggle Play/Pausa. Fuori dai campi di testo, dove
            // "π" deve restare digitabile.
            guard !isFirstResponderTextEditor() else { return false }
            ProgrammaticInputGate.suppress()
            onTogglePlaybackRequested?()
            return true
        case nil:
            // ⌘⇧L non è gestito qui: è un comando di menu.
            return false
        }
    }

    /// Mappa un tasto sul comando locale corrispondente. È una funzione pura
    /// per poterla verificare senza generare eventi reali.
    nonisolated static func localShortcut(
        forKeyCode keyCode: UInt16,
        flags: NSEvent.ModifierFlags
    ) -> LocalShortcut? {
        if keyCode == 8 && flags.contains([.command, .shift]) {
            return .capture
        }
        // Solo ⌥: Cmd/Shift/Ctrl escludono il menu ⌘⇧P della pillola, che usa
        // lo stesso keyCode.
        if keyCode == 35,
           flags.contains(.option),
           !flags.contains(.command),
           !flags.contains(.shift),
           !flags.contains(.control) {
            return .togglePlayback
        }
        return nil
    }

    /// `true` quando la finestra attiva sta modificando testo: il field editor
    /// di `NSTextField` e gli editor SwiftUI (`TextEditor`, `TextField`) sono
    /// tutti `NSTextView`, quindi il controllo sul first responder li copre.
    private func isFirstResponderTextEditor() -> Bool {
        let responder = NSApp.keyWindow?.firstResponder ?? NSApp.mainWindow?.firstResponder
        return responder is NSTextView || responder is NSTextField
    }
}
