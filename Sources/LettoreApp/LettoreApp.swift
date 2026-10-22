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
                    window.isMovableByWindowBackground = true
                }
            }
        }
    }
}

@main
struct LettoreApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState: AppState
    private let audioEngine: AudioEngineService
    private let axCapture: AXCaptureService
    private let shortcutManager: GlobalShortcutManager
    private let coordinator: PlaybackCoordinator
    private let captureController: ContinuousReadingController
    @State private var sourceHighlightCoordinator: SourceHighlightCoordinator
    @State private var isCaptureLogicSetup = false

    init() {
        let chunker = SentenceChunker()
        let sample = "Benvenuto in Lettore Native. Questa è la nuova architettura 100% nativa macOS in Swift 6 con sintesi vocale fluida e a bassissima latenza. Passa il cursore sulla pillola o premi Play per iniziare l'ascolto."
        let chunks = chunker.chunk(text: sample)
        let state = AppState()
        state.setQueue(chunks)
        if let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           frontmostPID != ProcessInfo.processInfo.processIdentifier {
            state.lastExternalApplicationPID = frontmostPID
        }
        _appState = State(initialValue: state)

        let audioEngine = AudioEngineService()
        let axCapture = AXCaptureService()
        let shortcutManager = GlobalShortcutManager()
        let coordinator = PlaybackCoordinator(appState: state, audioEngine: audioEngine)
        let captureController = ContinuousReadingController(
            appState: state,
            coordinator: coordinator,
            source: axCapture
        )
        let sourceHighlightCoordinator = SourceHighlightCoordinator(
            appState: state,
            highlighter: axCapture,
            isAccessibilityGranted: { AXIsProcessTrusted() },
            stopReading: {
                // La sessione continua possiede già lo stop completo; per il
                // playback non continuo basta fermare il coordinatore.
                if state.isContinuousSessionActive {
                    captureController.stopSession()
                } else {
                    coordinator.stop()
                }
            }
        )

        captureController.onSourceSessionStarted = { [weak sourceHighlightCoordinator] documentID, pid in
            sourceHighlightCoordinator?.begin(documentID: documentID, sourcePID: pid)
        }
        captureController.onSourceSessionEnded = { [weak sourceHighlightCoordinator] in
            sourceHighlightCoordinator?.end()
        }
        coordinator.onCurrentChunkChanged = { [weak sourceHighlightCoordinator] chunk in
            sourceHighlightCoordinator?.update(chunk: chunk)
        }
        coordinator.onPlaybackEnded = { [weak sourceHighlightCoordinator] in
            sourceHighlightCoordinator?.end()
        }

        self.audioEngine = audioEngine
        self.axCapture = axCapture
        self.shortcutManager = shortcutManager
        self.coordinator = coordinator
        self.captureController = captureController
        _sourceHighlightCoordinator = State(initialValue: sourceHighlightCoordinator)
    }
    
    private func setupCaptureLogic(state: AppState) {
        guard !isCaptureLogicSetup else { return }
        isCaptureLogicSetup = true
        
        let captureAction: @Sendable () -> Void = { [axCapture, captureController] in
            Task { @MainActor in
                // Quando il Play parte dalla UI di Lettore (pillola incorporata
                // o fluttuante mentre lo Studio è attivo) l'app in primo piano
                // è Lettore stesso: leggere il suo focused element non trova
                // testo. Si usa l'ultima app esterna attivata, come fa il
                // pulsante "Leggi da qui". La scorciatoia globale continua a
                // leggere l'app davvero in primo piano.
                let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                let isRequestFromLettoreUI = frontmostPID == ProcessInfo.processInfo.processIdentifier
                let sourcePID = isRequestFromLettoreUI
                    ? self.validExternalApplicationPID(for: state)
                    : nil

                if isRequestFromLettoreUI, sourcePID == nil {
                    guard state.playbackState != .playing else { return }
                    // Nessuna app di origine valida: non leggere la UI di
                    // Lettore. Il Play riprende la coda già pronta, se c'è.
                    if state.currentChunk != nil {
                        state.continuationNotice = nil
                        self.coordinator.playCurrentChunk()
                    } else {
                        state.continuationNotice = "Nessuna app di origine disponibile: porta in primo piano l'app con il testo, poi torna qui e riprova."
                    }
                    return
                }

                if state.isContinuousReadingEnabled {
                    let captured = await captureController.captureAndPlay(from: sourcePID)
                    if captured == nil,
                       state.playbackState != .playing,
                       state.currentChunk != nil {
                        // La cattura non ha prodotto testo: il Play non deve
                        // restare muto se c'è una coda già pronta.
                        state.continuationNotice = nil
                        self.coordinator.playCurrentChunk()
                    }
                    return
                }

                guard let result = await axCapture.captureSelectedText(from: sourcePID) else {
                    // Nessuna selezione leggibile: se esiste una coda non
                    // ancora finita, riprendila invece di non fare nulla.
                    if state.playbackState != .playing, state.currentChunk != nil {
                        self.coordinator.playCurrentChunk()
                    }
                    return
                }

                let text = result.trimmedText
                guard !text.isEmpty else {
                    // Nessuna selezione leggibile: se esiste una coda non
                    // ancora finita, riprendila invece di non fare nulla.
                    if state.playbackState != .playing, state.currentChunk != nil {
                        self.coordinator.playCurrentChunk()
                    }
                    return
                }

                // Una nuova cattura (anche non continua) chiude l'avviso
                // persistente della sessione precedente.
                state.continuationNotice = nil
                state.capturedDocumentText = ""

                // Il testo è contiguo nella sorgente: il range della selezione
                // (già avanzato dal trimming) è la base assoluta dei chunk.
                let sourceRange = result.trimmedSourceRange
                let normalizer = TextNormalizer()
                let chunks = normalizer.normalize(
                    SentenceChunker().chunk(
                        text: text,
                        sourceRange: sourceRange,
                        sourceDocumentID: result.sourceDocumentID
                    )
                )

                state.setQueue(chunks)
                if let documentID = result.sourceDocumentID,
                   let sourcePID = result.sourcePID,
                   sourceRange != nil {
                    self.sourceHighlightCoordinator.begin(
                        documentID: documentID,
                        sourcePID: sourcePID
                    )
                } else {
                    self.sourceHighlightCoordinator.end()
                }

                if state.playbackState != .playing {
                    self.coordinator.playCurrentChunk()
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

        shortcutManager.onToggleContinuousReadingRequested = {
            state.isContinuousReadingEnabled.toggle()
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

        // Traccia l'ultima app esterna attivata. Lo Studio è in primo piano
        // quando si preme "Leggi da qui": il PID permette di leggere il testo
        // dall'app da cui l'utente è arrivato invece che dalla UI di Lettore.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let activatedPID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let activatedPID else { return }
                guard activatedPID != ProcessInfo.processInfo.processIdentifier else { return }
                state.lastExternalApplicationPID = activatedPID
            }
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
        // Ascolta richieste di apertura o toggle della pillola fluttuante
        NotificationCenter.default.addObserver(forName: NSNotification.Name("ToggleFloatingPill"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                FloatingPillPanelManager.shared.toggle(appState: state, audioEngine: audioEngine, coordinator: coordinator)
            }
        }
        
        // Mostra la pillola all'avvio dell'applicazione
        NotificationCenter.default.addObserver(forName: NSNotification.Name("ShowFloatingPill"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                FloatingPillPanelManager.shared.show(appState: state, audioEngine: audioEngine, coordinator: coordinator)
            }
        }
    }
    
    /// PID dell'ultima app esterna ancora in esecuzione, mai il PID di
    /// Lettore. Usato quando la cattura parte dalla UI dell'app, che è
    /// inevitabilmente in primo piano.
    private func validExternalApplicationPID(for state: AppState) -> pid_t? {
        guard let pid = state.lastExternalApplicationPID,
              pid != ProcessInfo.processInfo.processIdentifier,
              let application = NSRunningApplication(processIdentifier: pid),
              !application.isTerminated else {
            return nil
        }
        return pid
    }

    var body: some Scene {
        // Finestra Principale Studio / Super Accessibile
        WindowGroup("Lettore Studio", id: "studio-window") {
            if appState.accessibilityProfile == .lowVision {
                SuperAccessibleView(appState: appState, audioEngine: audioEngine, coordinator: coordinator)
                    .frame(minWidth: 960, minHeight: 640)
                    .task { setupCaptureLogic(state: appState) }
            } else {
                LettoreStudioView(
                    appState: appState,
                    audioEngine: audioEngine,
                    coordinator: coordinator,
                    captureController: captureController,
                    axCapture: axCapture,
                    onSourceHighlightBegin: { documentID, pid in
                        sourceHighlightCoordinator.begin(documentID: documentID, sourcePID: pid)
                    },
                    onSourceHighlightEnd: {
                        sourceHighlightCoordinator.end()
                    }
                )
                .frame(minWidth: 960, minHeight: 640)
                .task { setupCaptureLogic(state: appState) }
                .onAppear {
                    // Mostra la pillola fluttuante all'apertura dello Studio
                    FloatingPillPanelManager.shared.show(appState: appState, audioEngine: audioEngine, coordinator: coordinator)
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Strumenti") {
                Button("Mostra / Nascondi Pillola Fluttuante") {
                    FloatingPillPanelManager.shared.toggle(appState: appState, audioEngine: audioEngine, coordinator: coordinator)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Divider()

                Toggle("Lettura continua", isOn: Binding(
                    get: { appState.isContinuousReadingEnabled },
                    set: { appState.isContinuousReadingEnabled = $0 }
                ))
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Toggle("Carica le pagine successive", isOn: Binding(
                    get: { appState.isAutoPageEnabled },
                    set: { appState.isAutoPageEnabled = $0 }
                ))
                .disabled(!appState.isContinuousReadingEnabled)

                Toggle("Evidenzia la frase nell'app di origine", isOn: Binding(
                    get: { appState.isSourceHighlightEnabled },
                    set: { appState.isSourceHighlightEnabled = $0 }
                ))
            }
            CommandGroup(replacing: .appInfo) {
                Button("Informazioni su Lettore Native") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "Lettore Native",
                            .applicationVersion: "0.3.2",
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

            Toggle("Lettura continua", isOn: Binding(
                get: { appState.isContinuousReadingEnabled },
                set: { appState.isContinuousReadingEnabled = $0 }
            ))

            Toggle("Carica le pagine successive", isOn: Binding(
                get: { appState.isAutoPageEnabled },
                set: { appState.isAutoPageEnabled = $0 }
            ))
            .disabled(!appState.isContinuousReadingEnabled)

            Toggle("Evidenzia la frase nell'app di origine", isOn: Binding(
                get: { appState.isSourceHighlightEnabled },
                set: { appState.isSourceHighlightEnabled = $0 }
            ))

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
