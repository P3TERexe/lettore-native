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
    public var audioEngine: AudioEngineService
    public var coordinator: PlaybackCoordinator
    public var axCapture: AXCaptureService
    
    @State private var inputText: String = ""
    @State private var showingNotchPreview: Bool = false
    
    public init(
        appState: AppState,
        audioEngine: AudioEngineService,
        coordinator: PlaybackCoordinator,
        axCapture: AXCaptureService = AXCaptureService()
    ) {
        self.appState = appState
        self.audioEngine = audioEngine
        self.coordinator = coordinator
        self.axCapture = axCapture
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
        .preferredColorScheme(.dark)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .sheet(isPresented: $showingNotchPreview) {
            notchPreviewSheet
        }
    }
    
    // MARK: - Header Toolbar
    
    private var headerToolbar: some View {
        HStack(spacing: 16) {
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
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("100% Native Swift 6 · ANE")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(brandCyan)
                }
            }
            
            Spacer()
            
            // Switcher Modalità di Presentazione
            HStack(spacing: 6) {
                modeButton(title: "Studio", icon: "macwindow", isSelected: true) {}
                
                modeButton(title: "Pillola Libera", icon: "capsule.portrait", isSelected: false) {
                    FloatingPillPanelManager.shared.toggle(appState: appState, audioEngine: audioEngine, coordinator: coordinator)
                }
                
                modeButton(title: "Tacca Notch", icon: "menubar.arrow.up.rectangle", isSelected: false) {
                    showingNotchPreview = true
                }
                
                modeButton(title: "Bassa Visione", icon: "eye.fill", isSelected: false) {
                    appState.accessibilityProfile = .lowVision
                }
            }
            .padding(4)
            .background(Color.black.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            
            Spacer()
            
            // Pulsanti Cattura Rapida e Pin
            HStack(spacing: 8) {
                actionButton(
                    icon: appState.isAlwaysOnTop ? "pin.fill" : "pin",
                    title: appState.isAlwaysOnTop ? "Sempre Sopra: ON" : "Sempre Sopra: OFF"
                ) {
                    appState.isAlwaysOnTop.toggle()
                    for window in NSApp.windows where window.frame.width >= 800 && !(window is NSPanel) {
                        window.level = appState.isAlwaysOnTop ? .floating : .normal
                    }
                }
                
                actionButton(icon: "bolt.fill", title: "App AX") {
                    captureFromFrontmostApp()
                }
                
                actionButton(icon: "doc.on.clipboard", title: "Appunti") {
                    pasteFromClipboard()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(red: 0.08, green: 0.09, blue: 0.12))
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
                
                // Centratura Pillola
                HStack {
                    Spacer()
                    FloatingPillView(appState: appState, audioEngine: audioEngine, coordinator: coordinator)
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
            HStack(spacing: 12) {
                TextField("Scrivi o incolla nuovo testo da ascoltare...", text: $inputText)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.black.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
                
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
        VStack(alignment: .leading, spacing: 22) {
            // Sezione Voci Neurali
            VStack(alignment: .leading, spacing: 10) {
                Text("VOCE NEURALE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                
                VStack(spacing: 8) {
                    voiceRow(id: "M1", name: "Marco (Supertonic M1)", isSelected: appState.selectedVoice.id == "M1")
                    voiceRow(id: "F1", name: "Giulia (Supertonic F1)", isSelected: appState.selectedVoice.id == "F1")
                    voiceRow(id: "M2", name: "Luca (Supertonic M2)", isSelected: appState.selectedVoice.id == "M2")
                    voiceRow(id: "F2", name: "Sofia (Supertonic F2)", isSelected: appState.selectedVoice.id == "F2")
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
                        let floatVal = Float(newVal)
                        appState.playbackSpeed = floatVal
                        audioEngine.setSpeed(floatVal)
                    }
                ), in: 0.5...2.5, step: 0.05)
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
                
                HStack(spacing: 5) {
                    ForEach(0..<appState.liveWaveformLevels.count, id: \.self) { idx in
                        let level = CGFloat(appState.liveWaveformLevels[idx])
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [brandCyan, brandGreen],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: max(6, level * 40))
                    }
                }
                .frame(height: 44, alignment: .bottom)
                .padding(10)
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // Box Info Performance
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundStyle(brandGreen)
                    Text("Apple Neural Engine")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                
                Text("Esecuzione 100% offline su Silicon ANE. RAM < 45 MB, latenza First-Chunk < 60 ms.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Spacer()
        }
        .padding(20)
        .background(Color(red: 0.08, green: 0.09, blue: 0.12))
    }
    
    // MARK: - Subviews Helpers
    
    private func modeButton(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? brandCyan : Color.clear)
            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
    
    private func actionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.08))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
    
    private func voiceRow(id: String, name: String, isSelected: Bool) -> some View {
        Button(action: {
            appState.selectedVoice = VoiceProfile(id: id, name: name, language: "it", gender: id.contains("_f") ? "female" : "male")
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
            appState.playbackSpeed = val
            audioEngine.setSpeed(val)
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
            
            DynamicNotchView(appState: appState, audioEngine: audioEngine)
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
        
        coordinator.stop()
        let normalizer = TextNormalizer()
        let normalized = normalizer.normalize(text: text)
        let chunker = SentenceChunker()
        let chunks = chunker.chunk(text: normalized)
        
        appState.setQueue(chunks)
        inputText = ""
    }
    
    private func captureFromFrontmostApp() {
        Task {
            if let result = await axCapture.captureSelectedText() {
                await MainActor.run {
                    self.inputText = result.text
                    processNewInput()
                }
            }
        }
    }
    
    private func pasteFromClipboard() {
        if let clipText = NSPasteboard.general.string(forType: .string), !clipText.isEmpty {
            self.inputText = clipText
            processNewInput()
        }
    }
}
