import SwiftUI
import AppKit
import LettoreCore
import LettoreEngine
import LettoreSystem
import LettoreUI

@main
struct LettoreApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState: AppState
    private let shortcutManager: GlobalShortcutManager
    private let coordinator: PlaybackCoordinator
    private let readingCapture: ReadingCaptureController
    @State private var sourceHighlightCoordinator: SourceHighlightCoordinator
    @State private var isCaptureLogicSetup = false
    private let captureGate: CaptureInFlightGate

    init() {
        let sample = "Benvenuto in Lettore Native. Questa è la nuova architettura 100% nativa macOS in Swift 6 con sintesi vocale fluida e a bassissima latenza. Passa il cursore sulla pillola o premi Play per iniziare l'ascolto."
        let chunks = ReadingTextPreparer().prepareInitial(text: sample, mode: .off).chunks
        let sourceApplications = SystemSourceApplicationProvider()
        let state = AppState()
        state.setQueue(chunks)
        if let frontmostPID = sourceApplications.frontmostApplicationPID,
           frontmostPID != sourceApplications.currentProcessIdentifier {
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
        let readingCapture = ReadingCaptureController(
            appState: state,
            selectedText: axCapture,
            sourceApplications: sourceApplications,
            continuousCapture: { [captureController] applicationPID in
                await captureController.captureAndPlay(from: applicationPID)
            },
            cancelContinuousSession: { [captureController] in
                captureController.stopSession()
            }
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
        // Lo Stop esplicito dello Studio svuota la coda: invalida anche le
        // catture e le preparazioni in volo, altrimenti una richiesta partita
        // prima dello stop può ripopolarla subito dopo. Weak per non creare un
        // ciclo coordinator → closure → controller.
        //
        // Il gate viene invalidato per primo: libera subito RIPRODUCI/⌥P e
        // supera la cattura in volo, che alla sua risposta non potrà più
        // applicare l'esito alla sessione nuova.
        let captureGate = CaptureInFlightGate()
        coordinator.onExplicitStop = { [weak captureController, weak readingCapture, captureGate] in
            captureGate.invalidate()
            captureController?.stopSession()
            readingCapture?.invalidatePendingRequests()
        }

        self.shortcutManager = shortcutManager
        self.coordinator = coordinator
        self.readingCapture = readingCapture
        self.captureGate = captureGate
        _sourceHighlightCoordinator = State(initialValue: sourceHighlightCoordinator)
    }
    
    private func setupCaptureLogic(state: AppState) {
        guard !isCaptureLogicSetup else { return }
        isCaptureLogicSetup = true
        
        let captureAction: @Sendable () -> Void = { [readingCapture, coordinator, sourceHighlightCoordinator, state, captureGate] in
            Task { @MainActor in
                // Il token lega busy ed esito alla stessa cattura: dopo uno
                // stop la vecchia risposta non deve né applicare il proprio
                // esito né liberare il gate della cattura nuova.
                guard let generation = captureGate.begin() else { return }
                defer { captureGate.end(generation) }

                let outcome = await readingCapture.captureFromFrontmost(
                    isContinuousEnabled: state.isContinuousReadingEnabled
                )

                guard captureGate.isCurrent(generation) else { return }

                switch outcome {
                case .captured(let selection):
                    // La nuova selezione sostituisce la coda: ferma prima la
                    // sessione precedente, altrimenti il vecchio audio
                    // avanzerebbe la coda nuova saltandone il primo chunk.
                    coordinator.stop()
                    if let documentID = selection.sourceDocumentID,
                       let sourcePID = selection.sourcePID,
                       selection.trimmedSourceRange != nil {
                        sourceHighlightCoordinator.begin(documentID: documentID, sourcePID: sourcePID)
                    } else {
                        sourceHighlightCoordinator.end()
                    }
                    coordinator.playCurrentChunk()
                case .fellBackToQueue:
                    // `play()` riprende una pausa invece di risintetizzare il
                    // chunk dall'inizio.
                    coordinator.play()
                case .continuous, .unavailable:
                    break
                }
            }
        }
        
        state.isAccessibilityGranted = AXIsProcessTrusted()
        
        // Con la coda vuota (dopo "Ferma") il toggle sarebbe un no-op: ⌥P
        // riparte dalla cattura, come il RIPRODUCI della vista accessibile.
        shortcutManager.onTogglePlaybackRequested = { [weak coordinator] in
            if state.playbackState == .idle && state.readingQueue.isEmpty {
                NotificationCenter.default.post(name: NSNotification.Name("CaptureAXText"), object: nil)
            } else {
                coordinator?.togglePlayPause()
            }
        }

        shortcutManager.onToggleContinuousReadingRequested = {
            state.isContinuousReadingEnabled.toggle()
        }
        
        shortcutManager.onCaptureRequested = captureAction
        // Il monitor locale non richiede Accessibilità: va avviato sempre, così
        // ⌘⇧C e ⌥P funzionano in Studio anche senza permesso. Il monitor
        // globale (app in background) fallisce senza permesso e viene
        // ritentato su didBecomeActive, perché isMonitoring resta false.
        shortcutManager.startMonitoring()
        if !shortcutManager.isMonitoring {
            print("[LettoreApp] ⚠️ Monitor globale scorciatoie in attesa dei permessi di Accessibilità (monitor locale attivo).")
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
    }

    var body: some Scene {
        // Finestra Principale Studio / Super Accessibile
        WindowGroup("Lettore Studio", id: "studio-window") {
            if appState.accessibilityProfile == .lowVision {
                SuperAccessibleView(appState: appState, coordinator: coordinator)
                    .frame(minWidth: 960, minHeight: 640)
                    .task { setupCaptureLogic(state: appState) }
            } else {
                LettoreStudioView(
                    appState: appState,
                    coordinator: coordinator,
                    readingCapture: readingCapture,
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
                    FloatingPillPanelManager.shared.show(appState: appState, coordinator: coordinator)
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Strumenti") {
                Button("Mostra / Nascondi Pillola Fluttuante") {
                    FloatingPillPanelManager.shared.toggle(appState: appState, coordinator: coordinator)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Ferma e svuota coda") {
                    coordinator.stopAndClearQueue()
                }

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
                            .applicationVersion: "0.3.3",
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
                FloatingPillPanelManager.shared.toggle(appState: appState, coordinator: coordinator)
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
