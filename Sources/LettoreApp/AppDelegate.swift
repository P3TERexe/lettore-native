import AppKit

/// Delegate per garantire che l'app CLI/SPM venga promossa a vera app GUI macOS con focus in primo piano.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Trasforma il processo da CLI/Accessory a regolare applicazione grafica
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Richiede esplicitamente a macOS di mostrare il popup per i permessi di Accessibilità se non concessi
        let promptOption = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptOption: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            for window in NSApp.windows where window.title == "Lettore Studio" {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                window.isMovableByWindowBackground = true
            }
        }
    }
}
