import SwiftUI
import AppKit
import LettoreCore
import LettoreEngine
import LettoreSystem
import LettoreUI

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
            for window in NSApp.windows {
                if window.title == "Lettore Studio" {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
            }
        }
    }
}

@main
struct LettoreApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState: AppState
    private let audioEngine = AudioEngineService()
    private let axCapture = AXCaptureService()
    private let shortcutManager = GlobalShortcutManager()
    private let coordinator: PlaybackCoordinator
    @State private var isCaptureLogicSetup = false
    
    init() {
        let state = AppState()
        _appState = State(initialValue: state)
        
        self.coordinator = PlaybackCoordinator(appState: state, audioEngine: audioEngine)
    }
    
    private func setupCaptureLogic(state: AppState) {
        guard !isCaptureLogicSetup else { return }
        isCaptureLogicSetup = true
        
        let captureAction: @Sendable () -> Void = { [axCapture] in
            Task {
                if let result = await axCapture.captureSelectedText() {
                    let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    
                    await MainActor.run {
                        let normalizer = TextNormalizer()
                        let normalized = normalizer.normalize(text: text)
                        let chunker = SentenceChunker()
                        let chunks = chunker.chunk(text: normalized)
                        
                        state.setQueue(chunks)
                        if state.playbackState != .playing {
                            self.coordinator.playCurrentChunk()
                        }
                    }
                }
            }
        }
        
        state.isAccessibilityGranted = AXIsProcessTrusted()
        
        shortcutManager.onTogglePlaybackRequested = { [weak coordinator] in
            if state.playbackState == .playing {
                coordinator?.stop()
            } else {
                coordinator?.playCurrentChunk()
            }
        }
        
        shortcutManager.onCaptureRequested = captureAction
        if state.isAccessibilityGranted {
            shortcutManager.startMonitoring()
        } else {
            print("[LettoreApp] ⚠️ Monitor scorciatoie in attesa dei permessi di Accessibilità...")
        }
        
        // Ascolta richieste di cattura provenienti dalla UI (es. Pillola)
        NotificationCenter.default.addObserver(forName: NSNotification.Name("CaptureAXText"), object: nil, queue: .main) { _ in
            captureAction()
        }
        
        // Ri-sincronizza permessi e monitor scorciatoie quando l'utente torna sull'applicazione
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let isTrusted = AXIsProcessTrusted()
                state.isAccessibilityGranted = isTrusted
                if isTrusted && !shortcutManager.isMonitoring {
                    shortcutManager.startMonitoring()
                }
            }
        }
        
        // Ascolta richiesta manuale di verifica permessi dalla UI (es. pulsante "Verifica Ora")
        NotificationCenter.default.addObserver(forName: NSNotification.Name("CheckAccessibilityPermissions"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let promptOption = "AXTrustedCheckOptionPrompt" as CFString
                let options = [promptOption: true] as CFDictionary
                let isTrusted = AXIsProcessTrustedWithOptions(options)
                state.isAccessibilityGranted = isTrusted
                if isTrusted && !shortcutManager.isMonitoring {
                    shortcutManager.startMonitoring()
                }
            }
        }
    }
    
    var body: some Scene {
        // Finestra Principale Studio / Super Accessibile
        WindowGroup("Lettore Studio", id: "studio-window") {
            if appState.accessibilityProfile == .lowVision {
                SuperAccessibleView(appState: appState, audioEngine: audioEngine)
                    .frame(minWidth: 960, minHeight: 640)
                    .task { setupCaptureLogic(state: appState) }
            } else {
                LettoreStudioView(
                    appState: appState,
                    audioEngine: audioEngine,
                    coordinator: coordinator,
                    axCapture: axCapture
                )
                .frame(minWidth: 960, minHeight: 640)
                .task { setupCaptureLogic(state: appState) }
            }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Informazioni su Lettore Native") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "Lettore Native",
                            .applicationVersion: "3.0.0",
                            .version: "Native macOS Edition",
                            .credits: NSAttributedString(
                                string: "Applicazione 100% nativa progettata per l'accessibilità.\nSintesi neurale locale potenziata da Supertonic ONNX.",
                                attributes: [
                                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                                    .foregroundColor: NSColor.labelColor
                                ]
                            )
                        ]
                    )
                }
            }
        }
        
        // Menu Bar Item di Sistema
        MenuBarExtra("Lettore", systemImage: "waveform.badge.magnifyingglass") {
            Button("Mostra / Nascondi Pillola Fluttuante") {
                FloatingPillPanelManager.shared.toggle(appState: appState, audioEngine: audioEngine, coordinator: coordinator)
            }
            Divider()
            Button("Profilo Bassa Visione (WCAG AAA)") {
                appState.accessibilityProfile = (appState.accessibilityProfile == .lowVision) ? .standard : .lowVision
            }
            Divider()
            Button("Esci da Lettore") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

/// Helper AppKit per ottenere il blur di sistema nativo NSVisualEffectView in SwiftUI.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
