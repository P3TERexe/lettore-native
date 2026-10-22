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
    /// Sessione sorgente registrata per l'highlight, se la selezione è stata
    /// letta via AX. Resta `nil` quando si usa il fallback clipboard.
    public let sourceDocumentID: UUID?
    public let sourceRange: SourceTextRange?
    public let sourcePID: pid_t?

    public init(
        text: String,
        sourceAppName: String? = nil,
        selectionBounds: CGRect? = nil,
        usedClipboardFallback: Bool = false,
        sourceDocumentID: UUID? = nil,
        sourceRange: SourceTextRange? = nil,
        sourcePID: pid_t? = nil
    ) {
        self.text = text
        self.sourceAppName = sourceAppName
        self.selectionBounds = selectionBounds
        self.usedClipboardFallback = usedClipboardFallback
        self.sourceDocumentID = sourceDocumentID
        self.sourceRange = sourceRange
        self.sourcePID = sourcePID
    }
}

/// Servizio di cattura del testo nativo macOS basato su Accessibility APIs (AXUIElement).
public actor AXCaptureService {

    /// Sessione AX aperta dalla modalità di lettura continua. Vive solo
    /// all'interno dell'attore: gli elementi AX non sono `Sendable`.
    var continuousSession: ContinuousAXSession?

    /// Sessione di highlight nativa registrata alla cattura.
    var highlightSession: SourceHighlightSession?
    var selectionObserverHandle: AXSelectionObserverHandle?
    var selectionNotificationGeneration = 0

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
        await captureSelectedText(from: nil)
    }

    /// Cattura il testo selezionato nell'app indicata, oppure nell'app in primo
    /// piano se il PID è `nil`.
    ///
    /// Con un PID esplicito non si usa il fallback clipboard: Cmd+C verrebbe
    /// inviato all'app in primo piano (lo Studio), non all'app di origine.
    public func captureSelectedText(from applicationPID: pid_t?) async -> AXCaptureResult? {
        if !AXIsProcessTrusted() {
            print("[AXCapture] ⚠️ Accessibilità NON concessa dal sistema operativo (AXIsProcessTrusted == false).")
            requestAccessibilityPrompt()
        }

        if let applicationPID {
            return captureSelectedText(fromApplication: applicationPID)
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
                let registration = registerSelectionHighlight(
                    focused: focusedElement,
                    sourcePID: processIdentifier(of: focusedElement)
                )
                return AXCaptureResult(
                    text: selectedStr,
                    sourceAppName: appName,
                    selectionBounds: nil,
                    usedClipboardFallback: false,
                    sourceDocumentID: registration.documentID,
                    sourceRange: registration.sourceRange,
                    sourcePID: registration.sourcePID
                )
            }
            print("[AXCapture] Focused element senza testo selezionato (app: \(appName ?? "?"), textResult: \(textResult.rawValue)). Provo il fallback clipboard.")
        } else {
            print("[AXCapture] kAXFocusedUIElementAttribute fallito (codice \(elemResult.rawValue)). Provo il fallback clipboard.")
        }
        
        // Fallback su simulazione Cmd+C via clipboard se AX non espone il testo selezionato
        clearHighlightSession()
        return await captureViaClipboardFallback(appName: appName)
    }

    /// Cattura la selezione dall'app target leggendo solo l'AX, senza inviare
    /// eventi di tastiera. Restituisce `nil` se l'app non espone la selezione.
    private func captureSelectedText(fromApplication pid: pid_t) -> AXCaptureResult? {
        let appElement = AXUIElementCreateApplication(pid)
        let appName = applicationName(for: appElement, pid: pid)

        guard let focusedElement = focusedElement(in: appElement) else {
            print("[AXCapture] App target (PID \(pid)) senza elemento focalizzato: nessuna cattura.")
            return nil
        }

        var selectedTextValue: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedTextValue
        )

        guard textResult == .success,
              let selectedStr = selectedTextValue as? String,
              !selectedStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[AXCapture] Nessuna selezione AX nell'app target (PID \(pid), textResult: \(textResult.rawValue)).")
            return nil
        }

        let registration = registerSelectionHighlight(
            focused: focusedElement,
            sourcePID: pid
        )
        return AXCaptureResult(
            text: selectedStr,
            sourceAppName: appName,
            selectionBounds: nil,
            usedClipboardFallback: false,
            sourceDocumentID: registration.documentID,
            sourceRange: registration.sourceRange,
            sourcePID: registration.sourcePID
        )
    }

    /// Elemento focalizzato nell'app target, con fallback alla finestra
    /// focalizzata/principale quando il focused element non è disponibile.
    private func focusedElement(in application: AXUIElement) -> AXUIElement? {
        let attributes = [
            kAXFocusedUIElementAttribute,
            kAXFocusedWindowAttribute,
            kAXMainWindowAttribute
        ]

        for attribute in attributes {
            var value: AnyObject?
            guard AXUIElementCopyAttributeValue(
                application,
                attribute as CFString,
                &value
            ) == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID() else {
                continue
            }
            return (value as! AXUIElement)
        }

        return nil
    }

    private func applicationName(for application: AXUIElement, pid: pid_t) -> String? {
        var titleValue: AnyObject?
        if AXUIElementCopyAttributeValue(application, kAXTitleAttribute as CFString, &titleValue) == .success,
           let title = titleValue as? String,
           !title.isEmpty {
            return title
        }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }
    
    func captureViaClipboardFallback(appName: String?) async -> AXCaptureResult? {
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
                    print("[AXCapture] Fallback clipboard riuscito (\(copied.count) caratteri).")
                    return AXCaptureResult(
                        text: copied,
                        sourceAppName: appName,
                        selectionBounds: nil,
                        usedClipboardFallback: true
                    )
                }
            }
        }
        
        print("[AXCapture] Fallback clipboard senza risultato (nessun testo copiato).")
        return nil
    }
}
