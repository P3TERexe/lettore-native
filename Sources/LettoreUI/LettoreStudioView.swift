import SwiftUI
import AppKit
import LettoreCore
import LettoreEngine
import LettoreSystem

/// Vista principale Studio per macOS.
/// Offre una console di lettura completa, visualizzazione dei blocchi/frasi segmentate,
/// anteprima interattiva della Pillola Dynamic Island e controlli avanzati del motore vocale.
public struct LettoreStudioView: View {
    @Bindable public var appState: AppState
    public var coordinator: PlaybackCoordinator
    public var readingCapture: ReadingCaptureController
    /// Apre la sessione di highlight dopo una cattura non continua. `nil` nei
    /// test o nelle anteprime senza composizione App.
    public var onSourceHighlightBegin: ((UUID, pid_t) -> Void)?
    public var onSourceHighlightEnd: (() -> Void)?
    
    @State private var inputText: String = ""
    @State private var showingNotchPreview: Bool = false
    @State private var isCapturing: Bool = false
    /// Token della cattura avviata dallo Studio: uno Stop o una nuova coda
    /// superano il token, così la risposta AX tardiva non riaccende il
    /// pulsante né applica l'esito alla sessione nuova.
    @State private var captureToken: UInt64 = 0
    @State private var isReconnecting: Bool = false
    
    public init(
        appState: AppState,
        coordinator: PlaybackCoordinator,
        readingCapture: ReadingCaptureController,
        onSourceHighlightBegin: ((UUID, pid_t) -> Void)? = nil,
        onSourceHighlightEnd: (() -> Void)? = nil
    ) {
        self.appState = appState
        self.coordinator = coordinator
        self.readingCapture = readingCapture
        self.onSourceHighlightBegin = onSourceHighlightBegin
        self.onSourceHighlightEnd = onSourceHighlightEnd
    }
    
    private let brandCyan = Color(red: 0.0, green: 0.9, blue: 1.0)
    private let brandGreen = Color(red: 0.2, green: 0.95, blue: 0.5)
    private let bgDark = Color(red: 0.06, green: 0.07, blue: 0.10)
    private let cardBg = Color(red: 0.10, green: 0.12, blue: 0.17)
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Superiore con Branding e Switcher Modalità
            headerToolbar
            
            Divider()
                .background(Color.white.opacity(0.12))
            
            if !appState.isAccessibilityGranted {
                accessibilityStatusBanner
                
                Divider()
                    .background(Color.white.opacity(0.12))
            }
            
            if appState.isUsingSpeechFallback, let notice = appState.speechFallbackNotice {
                speechFallbackBanner(notice: notice)
                
                Divider()
                    .background(Color.white.opacity(0.12))
            }

            if let notice = appState.continuationNotice {
                continuationNoticeBanner(notice: notice)

                Divider()
                    .background(Color.white.opacity(0.12))
            }
            
            // Corpo Principale: Canvas di Lettura & Sidebar Parametri
            HStack(spacing: 0) {
                mainReadingCanvas
                    .frame(maxWidth: .infinity)
                
                Divider()
                    .background(Color.white.opacity(0.12))
                
                sidebarControls
                    .frame(width: 320)
            }
        }
        .background(bgDark)
        .ignoresSafeArea(edges: .top)
        .preferredColorScheme(.dark)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onChange(of: appState.sessionGeneration) { _, _ in
            // Stop o sostituzione della coda: la cattura in volo è superata.
            // Il pulsante non deve restare "Cattura…" fino alla risposta AX.
            captureToken &+= 1
            isCapturing = false
        }
        .sheet(isPresented: $showingNotchPreview) {
            notchPreviewSheet
        }
    }
    
    // MARK: - Header Toolbar
    
    private var headerToolbar: some View {
        HStack(spacing: 14) {
            // Logo & Badge Versione
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [brandCyan.opacity(0.8), brandGreen.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lettore Studio")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text("100% Native Swift 6 · ANE")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(brandCyan)
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            
            Spacer()
            
            // Switcher Profilo di Vista (Mutuamente esclusivo: Studio vs Bassa Visione)
            HStack(spacing: 4) {
                modeButton(title: "Studio", icon: "macwindow", isSelected: appState.accessibilityProfile == .standard) {
                    appState.accessibilityProfile = .standard
                }
                
                modeButton(title: "Bassa Visione", icon: "eye.fill", isSelected: appState.accessibilityProfile == .lowVision) {
                    appState.accessibilityProfile = .lowVision
                }
            }
            .padding(4)
            .background(Color.black.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if appState.isContinuousReadingEnabled {
                HStack(spacing: 5) {
                    Image(systemName: appState.isFetchingMoreText
                          ? "arrow.triangle.2.circlepath"
                          : "text.line.last.and.arrowtriangle.forward")
                        .font(.system(size: 10, weight: .bold))
                    Text(appState.isFetchingMoreText
                         ? "Carico..."
                         : (appState.isContinuousDocumentPaged ? "Continua · pagine" : "Continua"))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(appState.isContinuousSessionActive ? brandGreen : brandCyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder((appState.isContinuousSessionActive ? brandGreen : brandCyan).opacity(0.35), lineWidth: 1)
                )
            }
            
            Spacer()
            
            // Strumenti & Finestre Ausiliarie
            HStack(spacing: 8) {
                actionButton(
                    icon: "text.cursor",
                    title: isCapturing ? "Cattura…" : "Leggi da qui",
                    isActive: appState.isContinuousReadingEnabled,
                    isDisabled: isCapturing,
                    fixedWidth: 132,
                    isBusy: isCapturing
                ) {
                    captureFromFrontmostApp()
                }

                actionButton(
                    icon: "capsule.portrait",
                    title: "Pillola",
                    isActive: appState.isFloatingPillVisible
                ) {
                    FloatingPillPanelManager.shared.toggle(appState: appState, coordinator: coordinator)
                }
                
                actionButton(
                    icon: "menubar.arrow.up.rectangle",
                    title: "Notch",
                    isActive: false
                ) {
                    showingNotchPreview = true
                }
                
                actionButton(
                    icon: appState.isAlwaysOnTop ? "pin.fill" : "pin",
                    title: "Sempre Sopra",
                    isActive: appState.isAlwaysOnTop
                ) {
                    appState.isAlwaysOnTop.toggle()
                    for window in NSApp.windows {
                        if window.title == "Lettore Studio" {
                            window.level = appState.isAlwaysOnTop ? .floating : .normal
                        }
                    }
                }
            }
        }
        .padding(.leading, 80) // Spazio FISSO e NON comprimibile per i semafori macOS
        .padding(.trailing, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Color(red: 0.08, green: 0.09, blue: 0.12))
    }
    
    // MARK: - Accessibility Status Banner
    
    private var accessibilityStatusBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.2))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Permessi di Accessibilità Non Attivi o Da Sincronizzare")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                
                Text("Necessari per catturare il testo con ⌘⇧C nelle app esterne. Se l'interruttore in macOS è già attivo ma non rileva i tasti, rimuovi 'Lettore Native' con '-' e riaggiungilo con '+'.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button("Apri Impostazioni") {
                    AXCaptureService.openAccessibilitySettings()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(red: 1.0, green: 0.72, blue: 0.2).opacity(0.2))
                .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.3))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(red: 1.0, green: 0.72, blue: 0.2).opacity(0.4), lineWidth: 1)
                )
                
                Button("Verifica Ora") {
                    NotificationCenter.default.post(name: NSNotification.Name("CheckAccessibilityPermissions"), object: nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.12))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(red: 0.18, green: 0.13, blue: 0.05))
    }
    
    // MARK: - Speech Fallback Warning Banner
    
    private func speechFallbackBanner(notice: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.2))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Voce di Sistema macOS in uso (Fallback)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button("Riconnetti Supertonic") {
                // Un solo tentativo alla volta: due tap avvierebbero due
                // loadModel e l'esito più lento potrebbe sovrascrivere quello
                // appena applicato.
                guard !isReconnecting else { return }
                isReconnecting = true
                // La riconnessione può completare dopo uno Stop: badge e
                // avvisi valgono solo per la sessione da cui sono partiti,
                // altrimenti riaccenderebbero lo stato su una coda ormai
                // svuotata. I fallimenti di sintesi, invece, appartengono al
                // motore: vanno dimenticati subito, così la prossima cattura
                // ritenta davvero la voce neurale.
                let generation = appState.sessionGeneration
                Task {
                    do {
                        try await coordinator.supertonicPipeline.loadModel()
                        await MainActor.run {
                            isReconnecting = false
                            coordinator.clearSynthesisFailures()
                            guard appState.isSessionCurrent(generation) else { return }
                            appState.isUsingSpeechFallback = false
                            appState.speechFallbackNotice = nil
                        }
                    } catch {
                        await MainActor.run {
                            isReconnecting = false
                            guard appState.isSessionCurrent(generation) else { return }
                            appState.isUsingSpeechFallback = true
                            appState.speechFallbackNotice = "Ritentativo fallito: \(error.localizedDescription). Assicurati che il backend Python sia attivo su 127.0.0.1:7788."
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isReconnecting)
            .opacity(isReconnecting ? 0.5 : 1)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(red: 1.0, green: 0.72, blue: 0.2).opacity(0.2))
            .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(red: 1.0, green: 0.72, blue: 0.2).opacity(0.4), lineWidth: 1)
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(red: 0.20, green: 0.14, blue: 0.05))
    }
    
    // MARK: - Lettura Continua: Avviso Persistente

    private func continuationNoticeBanner(notice: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "text.line.last.and.arrowtriangle.forward")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(brandCyan)

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.isContinuousReadingEnabled ? "Lettura continua" : "Cattura")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)

                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            }

            Spacer()

            // La lettura continua ha ⌘⇧L (menu); con la modalità spenta
            // l'azione successiva è la cattura, che ha ⌘⇧C
            // (`GlobalShortcutManager`, monitor globale + locale).
            if appState.isContinuousReadingEnabled {
                Text("⌘⇧L")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                Text("⌘⇧C")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(red: 0.06, green: 0.15, blue: 0.18))
    }

    // MARK: - Canvas di Lettura Centrale
    
    private var mainReadingCanvas: some View {
        VStack(spacing: 18) {
            // Card Player Pillola Interattiva
            VStack(spacing: 8) {
                HStack {
                    Text("PLAYER DINAMICO")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                    
                    Spacer()
                    
                    Text("Passa il mouse per espandere i comandi Dynamic Island")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(brandCyan.opacity(0.8))
                }
                .padding(.horizontal, 8)
                
                // Centratura Pillola (Modalità incorporata nello Studio: orizzontale fissa)
                HStack {
                    Spacer()
                    FloatingPillView(
                        appState: appState,
                        coordinator: coordinator,
                        isStandalone: false
                    )
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            .padding(14)
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            
            // Lista Frasi Segmentate (Coda di Lettura)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "text.quote")
                        .foregroundStyle(brandCyan)
                    Text("Frasi Segmentate (\(appState.readingQueue.count))")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    if let current = appState.currentChunk {
                        Text("Frase \(current.index + 1) di \(appState.readingQueue.count)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(brandGreen)
                    }

                    Button(action: {
                        coordinator.stopAndClearQueue()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("Svuota coda")
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        // Area tappabile di almeno 22pt anche se il testo è
                        // compatto: lo stop è distruttivo e non deve chiedere mira.
                        .frame(minHeight: 22)
                        .contentShape(Rectangle())
                        .background(Color.white.opacity(0.08))
                        .foregroundStyle(.white.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Interrompe la lettura e svuota la coda")
                    // Il nome accessibile contiene il testo visibile
                    // ("Svuota coda"), altrimenti Voice Control non può
                    // attivarlo pronunciando la label a schermo (WCAG 2.5.3).
                    .accessibilityLabel("Svuota coda e ferma la lettura")
                    .accessibilityHint("Interrompe la lettura e svuota la coda")
                }
                
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(appState.readingQueue) { chunk in
                            let isCurrent = appState.currentChunk?.id == chunk.id
                            
                            HStack(alignment: .top, spacing: 12) {
                                // Badge Numero Frase
                                Text("\(chunk.index + 1)")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(isCurrent ? Color.black : .white.opacity(0.6))
                                    .frame(width: 26, height: 26)
                                    .background(isCurrent ? brandCyan : Color.white.opacity(0.1))
                                    .clipShape(Circle())
                                
                                // Testo Frase
                                Text(chunk.text)
                                    .font(.system(size: 15, weight: isCurrent ? .semibold : .regular))
                                    .foregroundStyle(isCurrent ? .white : .white.opacity(0.8))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                // Tasto Ascolta Frase
                                Button(action: {
                                    jumpToChunk(chunk)
                                }) {
                                    Image(systemName: isCurrent && appState.playbackState == .playing ? "speaker.wave.3.fill" : "play.circle")
                                        .font(.system(size: 18))
                                        .foregroundStyle(isCurrent ? brandCyan : .white.opacity(0.4))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(14)
                            .background(isCurrent ? brandCyan.opacity(0.12) : Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(isCurrent ? brandCyan.opacity(0.5) : Color.clear, lineWidth: 1.5)
                            )
                            .onTapGesture {
                                jumpToChunk(chunk)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            
            // Box di Input Rapido per Nuovo Testo
            HStack(spacing: 8) {
                TextField("Scrivi o incolla nuovo testo da ascoltare...", text: $inputText)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.black.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
                    .onSubmit {
                        processNewInput()
                    }
                
                Button(action: {
                    pasteFromClipboard()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.clipboard")
                        Text("Incolla")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(.white.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Incolla dagli appunti di sistema e avvia la lettura")
                
                Button(action: {
                    processNewInput()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("Segmenta & Leggi")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(colors: [brandCyan, brandGreen], startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }
    
    // MARK: - Sidebar Parametri & Voci
    
    private var sidebarControls: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                // Sezione Lingua & Voci Neurali
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("LINGUA & VOCE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        if appState.isUsingSpeechFallback {
                            Text("Fallback Sistema")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.2))
                        } else {
                            Text("Supertonic Neurale")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(brandGreen)
                        }
                    }
                    
                    // Picker Lingua
                    Picker("", selection: $appState.selectedLanguage) {
                        ForEach(VoiceProfile.supportedLanguages, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 4)
                    
                    // Lista Voci Filtrate
                    VStack(spacing: 8) {
                        ForEach(appState.filteredVoices) { voice in
                            voiceRow(id: voice.id, name: "\(voice.name)", isSelected: appState.selectedVoice.id == voice.id)
                        }
                    }
                }
                
                // Sezione Velocità Riproduzione
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("VELOCITÀ")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                        
                        Spacer()
                        
                        Text("\(String(format: "%.2f", appState.playbackSpeed))×")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(brandCyan)
                    }
                    
                    Slider(value: Binding(
                        get: { Double(appState.playbackSpeed) },
                        set: { newVal in
                            coordinator.setSpeed(Float(newVal))
                        }
                    ), in: 0.5...2.0, step: 0.05)
                    .tint(brandCyan)
                    
                    HStack(spacing: 6) {
                        speedPresetButton(0.75)
                        speedPresetButton(1.0)
                        speedPresetButton(1.25)
                        speedPresetButton(1.5)
                        speedPresetButton(2.0)
                    }
                }
                
                // Monitor Spettro Audio
                VStack(alignment: .leading, spacing: 10) {
                    Text("MONITOR LIVE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                    
                    WaveformBarsView(
                        appState: appState,
                        spacing: 5,
                        maxBarHeight: 40,
                        minBarHeight: 6,
                        cornerRadius: 3,
                        fill: AnyShapeStyle(
                            LinearGradient(
                                colors: [brandCyan, brandGreen],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    )
                    .frame(height: 44, alignment: .bottom)
                    .padding(10)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                // Configurazione Performance & Latenza Vocale (PERF-1, PERF-2, PERF-3)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(brandGreen)
                        Text("VELOCITÀ & PERFORMANCE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    
                    // Selettore Step Qualità/Latenza
                    HStack(spacing: 6) {
                        stepOptionButton(title: "Turbo (5)", steps: 5)
                        stepOptionButton(title: "Bilanciato (8)", steps: 8)
                        stepOptionButton(title: "Hi-Fi (12)", steps: 12)
                    }
                    
                    Toggle(isOn: firstChunkBoostBinding) {
                        Text("Boost primo chunk")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(.white.opacity(isFirstChunkBoostAvailable ? 0.8 : 0.45))
                    }
                    .toggleStyle(SwitchToggleStyle(tint: brandGreen))
                    .disabled(!isFirstChunkBoostAvailable)
                    .help(isFirstChunkBoostAvailable
                          ? "Riduce a 5 step la sola sintesi del primo chunk; il resto della lettura resta a 8."
                          : "Attivo solo con qualità bilanciata (8 step): con Turbo (5) e Hi-Fi (12) il primo chunk usa già gli step scelti.")
                    .padding(.top, 2)
                    
                    // Telemetria Reale Misurata
                    VStack(alignment: .leading, spacing: 4) {
                        if let latency = appState.lastFirstChunkLatencyMs {
                            HStack {
                                Text("Latenza Primo Chunk:")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.5))
                                Spacer()
                                Text("\(String(format: "%.0f", latency)) ms")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(latency < 250 ? brandGreen : brandCyan)
                            }
                        }
                        if let synthMs = appState.lastSynthesisLatencyMs {
                            HStack {
                                Text("Tempo Sintesi Chunk:")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.5))
                                Spacer()
                                Text("\(String(format: "%.0f", synthMs)) ms")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        if appState.lastFirstChunkLatencyMs == nil && appState.lastSynthesisLatencyMs == nil {
                            Text("Cache L1/L2 e Ring Buffer N+2 attivi.")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(12)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Lettura Continua (DSA-11)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "text.line.last.and.arrowtriangle.forward")
                            .foregroundStyle(brandCyan)
                        Text("LETTURA CONTINUA")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        Text("⌘⇧L")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    Toggle(isOn: $appState.isContinuousReadingEnabled) {
                        Text("Leggi dalla selezione o dal cursore")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .toggleStyle(SwitchToggleStyle(tint: brandGreen))

                    Text("Il punto di partenza è solo l'inizio: la lettura prosegue nel documento.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle(isOn: $appState.isAutoPageEnabled) {
                        Text("Carica le pagine successive")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .toggleStyle(SwitchToggleStyle(tint: brandGreen))
                    .disabled(!appState.isContinuousReadingEnabled)

                    Toggle(isOn: $appState.isSourceHighlightEnabled) {
                        Text("Evidenzia la frase nell'app di origine")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .toggleStyle(SwitchToggleStyle(tint: brandGreen))

                    Text("Se l'app non supporta la selezione nativa, la frase corrente resta evidenziata nello Studio.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)

                    if let notice = appState.sourceHighlightNotice {
                        Text(notice)
                            .font(.system(size: 10))
                            .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.2))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        Text("Filtro rumore")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))

                        Spacer()

                        Picker("Filtro rumore", selection: $appState.noiseFilterMode) {
                            ForEach(NoiseFilterMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 120)
                        .disabled(!appState.isContinuousReadingEnabled)
                    }

                    if appState.isContinuousSessionActive {
                        HStack(spacing: 6) {
                            Image(systemName: appState.isContinuousDocumentPaged
                                  ? "rectangle.stack.fill"
                                  : "checkmark.circle.fill")
                                .font(.system(size: 10))
                            Text(appState.isContinuousDocumentPaged
                                 ? "Documento caricato a pagine"
                                 : "Sessione continua attiva")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(brandGreen)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(18)
        }
        .background(Color(red: 0.08, green: 0.09, blue: 0.12))
    }
    
    // MARK: - Subviews Helpers
    
    private func modeButton(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? brandCyan : Color.clear)
            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
    
    private func actionButton(
        icon: String,
        title: String,
        isActive: Bool = false,
        isDisabled: Bool = false,
        fixedWidth: CGFloat? = nil,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isBusy {
                    // Occupa lo stesso spazio dell'icona: la toolbar resta
                    // ferma mentre la cattura è in corso.
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                        .tint(brandCyan)
                        .frame(width: 11, height: 11)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundStyle(isActive ? brandGreen : .white)
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            // Larghezza minima fissa per i pulsanti con testo variabile
            // ("Leggi da qui" / "Cattura…"): i vicini non si spostano.
            .frame(minWidth: fixedWidth ?? 0)
            .background(isActive ? brandGreen.opacity(0.15) : Color.white.opacity(0.08))
            .foregroundStyle(isActive ? brandGreen : .white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isActive ? brandGreen.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }
    
    private func voiceRow(id: String, name: String, isSelected: Bool) -> some View {
        Button(action: {
            if let found = VoiceProfile.standardVoices.first(where: { $0.id == id }) {
                appState.selectedVoice = found
            }
        }) {
            HStack {
                Circle()
                    .fill(isSelected ? brandCyan : Color.white.opacity(0.2))
                    .frame(width: 8, height: 8)
                
                Text(name)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(brandCyan)
                }
            }
            .padding(10)
            .background(isSelected ? brandCyan.opacity(0.15) : Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
    
    private func speedPresetButton(_ val: Float) -> some View {
        Button(action: {
            coordinator.setSpeed(val)
        }) {
            Text("\(String(format: "%.2f", val))×")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(abs(appState.playbackSpeed - val) < 0.01 ? brandCyan : Color.white.opacity(0.08))
                .foregroundStyle(abs(appState.playbackSpeed - val) < 0.01 ? Color.black : Color.white.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
    
    /// Il toggle mostra spento quando il boost non è disponibile, senza perdere
    /// la scelta persistita: tornando a Bilanciato l'utente la ritrova.
    private var firstChunkBoostBinding: Binding<Bool> {
        Binding(
            get: { appState.isFirstChunkBoostEnabled && isFirstChunkBoostAvailable },
            set: { newValue in
                guard isFirstChunkBoostAvailable else { return }
                appState.isFirstChunkBoostEnabled = newValue
            }
        )
    }

    private var isFirstChunkBoostAvailable: Bool {
        // Il boost scende a 5 step: con Turbo (5) non cambierebbe nulla e con
        // Hi-Fi (12) abbasserebbe la qualità scelta. La policy vive in
        // `SynthesisQuality` per non duplicarla fra UI e motore.
        SynthesisQuality.isBoostApplicable(steps: appState.synthesisSteps)
    }

    private func stepOptionButton(title: String, steps: Int) -> some View {
        Button(action: {
            appState.synthesisSteps = steps
        }) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(appState.synthesisSteps == steps ? brandGreen : Color.white.opacity(0.08))
                .foregroundStyle(appState.synthesisSteps == steps ? Color.black : Color.white.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
    
    private var notchPreviewSheet: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Anteprima Dynamic Notch")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button("Chiudi") {
                    showingNotchPreview = false
                }
            }
            
            DynamicNotchView(appState: appState, coordinator: coordinator)
                .padding(20)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            
            Text("Su MacBook con tacca hardware, questo pannello si ancora automaticamente all'area top-notch senza coprire la finestra attiva.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(24)
        .frame(width: 600, height: 260)
        .background(Color(red: 0.1, green: 0.1, blue: 0.14))
    }
    
    // MARK: - Azioni
    
    private func jumpToChunk(_ chunk: ReadingChunk) {
        coordinator.jumpToChunk(chunk)
    }
    
    private func playCurrentChunk() {
        coordinator.playCurrentChunk()
    }
    
    private func processNewInput() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Lo stesso token delle catture: un Invio superato da una cattura
        // (o viceversa) non può sostituire la coda della richiesta più recente.
        let generation = readingCapture.beginManualReadingRequest()

        coordinator.stop()
        onSourceHighlightEnd?()
        appState.continuationNotice = nil
        appState.capturedDocumentText = ""
        // Svuota subito lo snapshot: un testo digitato durante la
        // preparazione non deve essere cancellato al completamento.
        inputText = ""

        Task { @MainActor in
            let reading = await Task.detached(priority: .userInitiated) {
                ReadingTextPreparer().prepareInitial(text: text, mode: .off)
            }.value

            guard readingCapture.isCurrentReadingRequest(generation) else { return }
            appState.setQueue(reading.chunks)
            coordinator.playCurrentChunk()
        }
    }

    /// Riproduce la selezione già preparata dal controller di cattura.
    private func playCapturedSelection(_ selection: CapturedSelection) {
        coordinator.stop()
        guard !appState.readingQueue.isEmpty else { return }

        // `inputText` è la bozza dell'utente: il testo catturato vive nella
        // coda e non deve sovrascrivere ciò che è stato digitato nel frattempo.
        if let documentID = selection.sourceDocumentID,
           let sourcePID = selection.sourcePID,
           selection.trimmedSourceRange != nil {
            onSourceHighlightBegin?(documentID, sourcePID)
        } else {
            onSourceHighlightEnd?()
        }

        coordinator.playCurrentChunk()
    }
    
    private func captureFromFrontmostApp() {
        guard !isCapturing else { return }
        // Il token lega busy ed esito alla stessa cattura: dopo uno Stop il
        // defer della cattura superata non deve sbloccare quella nuova.
        captureToken &+= 1
        let token = captureToken
        isCapturing = true
        Task { @MainActor in
            defer {
                if captureToken == token { isCapturing = false }
            }

            let outcome = await readingCapture.playFromUI(
                isContinuousEnabled: appState.isContinuousReadingEnabled
            )

            guard captureToken == token else { return }

            switch outcome {
            case .captured(let selection):
                playCapturedSelection(selection)
            case .continuous:
                // Il documento catturato vive in `appState` e nella coda:
                // non deve sovrascrivere la bozza dell'utente.
                break
            case .fellBackToQueue:
                requestAccessibilityPermissionIfNeeded()
                coordinator.play()
            case .unavailable:
                requestAccessibilityPermissionIfNeeded()
            }
        }
    }

    private func requestAccessibilityPermissionIfNeeded() {
        guard !appState.isAccessibilityGranted else { return }
        NotificationCenter.default.post(
            name: NSNotification.Name("CheckAccessibilityPermissions"),
            object: nil
        )
    }
    
    private func pasteFromClipboard() {
        if let clipText = NSPasteboard.general.string(forType: .string), !clipText.isEmpty {
            self.inputText = clipText
            processNewInput()
        }
    }
}
