import Foundation
@preconcurrency import ApplicationServices
import CoreGraphics
import AppKit
import LettoreCore

/// Risultato di un'operazione di cattura del testo da un'applicazione esterna.
public struct AXCaptureResult: Sendable {
    public let text: String
    public let sourceAppName: String?
    public let selectionBounds: CGRect?
    public let usedClipboardFallback: Bool
    
    public init(
        text: String,
        sourceAppName: String? = nil,
        selectionBounds: CGRect? = nil,
        usedClipboardFallback: Bool = false
    ) {
        self.text = text
        self.sourceAppName = sourceAppName
        self.selectionBounds = selectionBounds
        self.usedClipboardFallback = usedClipboardFallback
    }
}

/// Servizio di cattura del testo nativo macOS basato su Accessibility APIs (AXUIElement).
public actor AXCaptureService {
    
    public init() {}
    
    /// Verifica se l'applicazione ha i permessi di Accessibilità concessi nelle Preferenze di Sistema.
    public func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }
    
    /// Apre direttamente la pagina Privacy & Sicurezza -> Accessibilità nelle Impostazioni di macOS.
    @MainActor
    public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Richiede al sistema operativo di mostrare il prompt per concedere i permessi di Accessibilità.
    public func requestAccessibilityPrompt() {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    /// Cattura il testo attualmente selezionato nell'applicazione attiva in primo piano.
    public func captureSelectedText() async -> AXCaptureResult? {
        if !AXIsProcessTrusted() {
            print("[AXCapture] ⚠️ Accessibilità NON concessa dal sistema operativo (AXIsProcessTrusted == false).")
            requestAccessibilityPrompt()
        }
        
        let systemWide = AXUIElementCreateSystemWide()
        var focusedAppValue: AnyObject?
        
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppValue
        )
        
        var appName: String? = nil
        if appResult == .success, let appElement = focusedAppValue as! AXUIElement? {
            var titleValue: AnyObject?
            if AXUIElementCopyAttributeValue(appElement, kAXTitleAttribute as CFString, &titleValue) == .success,
               let titleStr = titleValue as? String {
                appName = titleStr
            }
        } else {
            print("[AXCapture] Nota: kAXFocusedApplicationAttribute restituito con codice \(appResult.rawValue)")
        }
        
        var focusedElementValue: AnyObject?
        let elemResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementValue
        )
        
        if elemResult == .success, let focusedElement = focusedElementValue as! AXUIElement? {
            // Tenta di leggere direttamente l'attributo kAXSelectedTextAttribute
            var selectedTextValue: AnyObject?
            let textResult = AXUIElementCopyAttributeValue(
                focusedElement,
                kAXSelectedTextAttribute as CFString,
                &selectedTextValue
            )
            
            if textResult == .success, let selectedStr = selectedTextValue as? String, !selectedStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return AXCaptureResult(
                    text: selectedStr,
                    sourceAppName: appName,
                    selectionBounds: nil,
                    usedClipboardFallback: false
                )
            }
        }
        
        // Fallback su simulazione Cmd+C via clipboard se AX non espone il testo selezionato
        return await captureViaClipboardFallback(appName: appName)
    }
    
    private func captureViaClipboardFallback(appName: String?) async -> AXCaptureResult? {
        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        
        // Simula Cmd+C
        let src = CGEventSource(stateID: .hidSystemState)
        let keyC: CGKeyCode = 8 // Codice per tasto 'C' su tastiera Mac
        
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: keyC, keyDown: true)
        cmdDown?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: keyC, keyDown: false)
        cmdUp?.flags = .maskCommand
        
        cmdDown?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
        
        // Attendi brevemente l'aggiornamento della clipboard (fino a 150ms)
        for _ in 0..<15 {
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            if pasteboard.changeCount != previousChangeCount {
                if let copied = pasteboard.string(forType: .string), !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return AXCaptureResult(
                        text: copied,
                        sourceAppName: appName,
                        selectionBounds: nil,
                        usedClipboardFallback: true
                    )
                }
            }
        }
        
        return nil
    }
}
