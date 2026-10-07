import SwiftUI
import LettoreCore
import LettoreEngine

/// Vista della pillola fluttuante con animazione elastica Dynamic Island a due stati.
/// - Stato compatto: drag ovunque sulla capsula, indicatore di stato e onda vocale live, zero spazio vuoto.
/// - Stato espanso: controlli completi e compatti (Frase Precedente/Successiva, Play/Pausa, Velocità, Pin, Chiudi).
/// - Nessuna barra inferiore ingannevole stile scrollbar.
public struct FloatingPillView: View {
    @Bindable public var appState: AppState
    public var audioEngine: AudioEngineService
    public var coordinator: PlaybackCoordinator?
    public var isStandalone: Bool
    
    @State private var isHovered: Bool = false
    @State private var hoverDismissTask: Task<Void, Never>? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public init(
        appState: AppState,
        audioEngine: AudioEngineService,
        coordinator: PlaybackCoordinator? = nil,
        isStandalone: Bool = false
    ) {
        self.appState = appState
        self.audioEngine = audioEngine
        self.coordinator = coordinator
        self.isStandalone = isStandalone
    }
    
    private var isExpanded: Bool {
        return isHovered || appState.isPillExpanded
    }
    
    private var effectiveOrientation: PillOrientation {
        return .horizontal
    }
    
    public var body: some View {
        ZStack {
            horizontalPill
        }
        .contentShape(Capsule())
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.76), value: isExpanded)
        .onHover { hovering in
            handleHover(hovering)
        }
    }
    
    // MARK: - Gestione Hover con Grace Period
    
    private func handleHover(_ hovering: Bool) {
        // Se stiamo attivamente trascinando la pillola sullo schermo, blocca qualsiasi transizione hover
        if FloatingPillPanelManager.shared.isDragging { return }
        
        if hovering {
            hoverDismissTask?.cancel()
            hoverDismissTask = nil
            if !isHovered {
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.76)) {
                    isHovered = true
                }
                if isStandalone {
                    FloatingPillPanelManager.shared.updatePanelFrame(
                        for: effectiveOrientation,
                        isExpanded: true,
                        animated: !reduceMotion
                    )
                }
            }
        } else {
            hoverDismissTask?.cancel()
            hoverDismissTask = Task {
                // 350ms di grace period per prevenire scatti o chiusure brusche accidentali
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if !appState.isPillExpanded && !FloatingPillPanelManager.shared.isDragging {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.76)) {
                            isHovered = false
                        }
                        if isStandalone {
                            FloatingPillPanelManager.shared.updatePanelFrame(
                                for: effectiveOrientation,
                                isExpanded: false,
                                animated: !reduceMotion
                            )
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Drag Gesture Fluido & Stabile a Coordinate Schermo Globali
    
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { _ in
                guard isStandalone else { return }
                FloatingPillPanelManager.shared.dragPanelWithCurrentMouse()
            }
            .onEnded { _ in
                guard isStandalone else { return }
                FloatingPillPanelManager.shared.finishDrag(appState: appState)
            }
    }
    
    private func waveformLevel(at index: Int) -> CGFloat {
        guard index >= 0 && index < appState.liveWaveformLevels.count else { return 0.15 }
        return CGFloat(appState.liveWaveformLevels[index])
    }
    
    // MARK: - Layout Orizzontale (Top / Centro Schermo)
    
    private var horizontalPill: some View {
        HStack(spacing: 6) {
            // Sezione Grip & Onde Vocali
            HStack(spacing: 5) {
                if isStandalone {
                    dragGrip
                }
                
                horizontalWaveformSection
            }
            .padding(.leading, 8)
            .padding(.trailing, isExpanded ? 2 : 8)
            
            // Sezione Controlli a Comparsa Orizzontale (compatta, zero spazio extra)
            if isExpanded {
                horizontalControlsSection
                    .padding(.trailing, 8)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.90, anchor: .leading)),
                            removal: .opacity.combined(with: .scale(scale: 0.90, anchor: .leading))
                        )
                    )
            }
        }
        .frame(height: 36)
        .frame(width: isExpanded ? (appState.isUsingSpeechFallback ? 290 : 275) : 96, alignment: .center)
        .background {
            ZStack {
                Capsule()
                    .fill(Color(red: 0.05, green: 0.05, blue: 0.07).opacity(0.96))
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isExpanded ? Color.white.opacity(0.35) : Color.white.opacity(0.18),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.7), radius: isExpanded ? 16 : 8, y: 6)
                    .shadow(
                        color: Color(red: 0.0, green: 0.9, blue: 1.0).opacity(isExpanded ? 0.22 : 0.08),
                        radius: isExpanded ? 12 : 6
                    )
                
                if isStandalone && !isExpanded {
                    NativeDragHandleView(appState: appState)
                        .clipShape(Capsule())
                }
            }
        }
        .clipShape(Capsule())
    }
    
    private var dragGrip: some View {
        ZStack {
            NativeDragHandleView(appState: appState)
            
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.45))
                .allowsHitTesting(false)
        }
        .frame(width: 18, height: 26)
        .help("Trascina la pillola per spostarla")
        .accessibilityLabel("Trascina pillola")
    }
    
    private var horizontalWaveformSection: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<min(5, appState.liveWaveformLevels.count), id: \.self) { idx in
                let level = waveformLevel(at: idx)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.0, green: 0.9, blue: 1.0), Color(red: 0.2, green: 0.95, blue: 0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2.8, height: max(5, level * 20))
                    .shadow(color: Color(red: 0.0, green: 0.9, blue: 1.0).opacity(0.4), radius: 2)
            }
        }
        .frame(width: 32, height: 22, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture {
            handlePlayPause()
        }
        .help(appState.playbackState == .playing ? "Pausa" : "Riproduci")
        .accessibilityLabel(appState.playbackState == .playing ? "Pausa" : "Riproduci")
    }
    
    private var horizontalControlsSection: some View {
        HStack(spacing: 6) {
            // Frase precedente
            Button(action: {
                if let coordinator = coordinator {
                    coordinator.skipBackward()
                } else {
                    _ = appState.rewindChunk()
                }
            }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Frase precedente")
            .accessibilityLabel("Frase precedente")
            
            // Play / Pausa
            Button(action: handlePlayPause) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 26, height: 26)
                        .shadow(color: Color.white.opacity(0.35), radius: 3)
                    
                    Image(systemName: appState.playbackState == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black)
                        .offset(x: appState.playbackState == .playing ? 0 : 1)
                }
            }
            .buttonStyle(.plain)
            .help(appState.playbackState == .playing ? "Metti in pausa" : "Riproduci")
            .accessibilityLabel(appState.playbackState == .playing ? "Pausa" : "Riproduci")
            
            // Frase successiva
            Button(action: {
                if let coordinator = coordinator {
                    coordinator.skipForward()
                } else {
                    _ = appState.advanceChunk()
                }
            }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Frase successiva")
            .accessibilityLabel("Frase successiva")
            
            // Selettore Velocità
            Menu {
                ForEach([0.7, 0.85, 1.0, 1.05, 1.25, 1.5, 1.75, 2.0], id: \.self) { spd in
                    Button("\(String(format: "%.2f", spd))×") {
                        appState.setSpeed(Float(spd))
                        audioEngine.setSpeed(Float(spd))
                    }
                }
            } label: {
                Text("\(String(format: "%.2f", appState.playbackSpeed))×")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.0, green: 0.9, blue: 1.0))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("Velocità di riproduzione")
            .accessibilityLabel("Velocità: \(String(format: "%.2f", appState.playbackSpeed)) per")
            
            // Badge Avviso Fallback (se attivo)
            if appState.isUsingSpeechFallback {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.2))
                    .help(appState.speechFallbackNotice ?? "Voce macOS di fallback attiva (backend Supertonic offline)")
            }
            
            // Blocca / Sblocca espanso (Pin)
            Button(action: {
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75)) {
                    appState.isPillExpanded.toggle()
                }
                if isStandalone {
                    FloatingPillPanelManager.shared.updatePanelFrame(
                        for: effectiveOrientation,
                        isExpanded: appState.isPillExpanded,
                        animated: !reduceMotion
                    )
                }
            }) {
                Image(systemName: appState.isPillExpanded ? "pin.fill" : "pin")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(appState.isPillExpanded ? Color(red: 0.0, green: 0.9, blue: 1.0) : .white.opacity(0.75))
                    .frame(width: 22, height: 22)
                    .background(appState.isPillExpanded ? Color(red: 0.0, green: 0.9, blue: 1.0).opacity(0.2) : Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(appState.isPillExpanded ? "Sblocca espansione automatica" : "Blocca pillola espansa")
            .accessibilityLabel(appState.isPillExpanded ? "Sblocca espansione" : "Blocca pillola espansa")
            
            // Chiudi pillola (solo se fluttuante indipendente)
            if isStandalone {
                Button(action: {
                    FloatingPillPanelManager.shared.hide(appState: appState)
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Chiudi la pillola fluttuante")
                .accessibilityLabel("Chiudi pillola")
            }
        }
    }
    
    // MARK: - Layout Verticale (Lati dello Schermo)
    
    private var verticalPill: some View {
        VStack(spacing: 5) {
            // Drag grip in alto
            if isStandalone {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 22, height: 8)
                    .contentShape(Rectangle())
                    .padding(.top, 4)
            }
            
            // Sezione Onde Vocali Verticale (tappabile per Play/Pausa)
            verticalWaveformSection
                .padding(.top, isStandalone ? 0 : 4)
                .padding(.bottom, isExpanded ? 0 : 4)
            
            // Sezione Controlli Verticali a Comparsa
            if isExpanded {
                verticalControlsSection
                    .padding(.bottom, 6)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.90, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.90, anchor: .top))
                        )
                    )
            }
        }
        .frame(width: 44)
        .frame(height: isExpanded ? 198 : 44, alignment: .top)
        .background {
            Capsule()
                .fill(Color(red: 0.05, green: 0.05, blue: 0.07).opacity(0.96))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isExpanded ? Color.white.opacity(0.35) : Color.white.opacity(0.18),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.7), radius: isExpanded ? 16 : 8, y: 6)
                .shadow(
                    color: Color(red: 0.0, green: 0.9, blue: 1.0).opacity(isExpanded ? 0.22 : 0.08),
                    radius: isExpanded ? 12 : 6
                )
                .contentShape(Capsule())
                .gesture(dragGesture)
        }
        .clipShape(Capsule())
    }
    
    private var verticalWaveformSection: some View {
        HStack(spacing: 2) {
            ForEach(0..<min(4, appState.liveWaveformLevels.count), id: \.self) { idx in
                let level = waveformLevel(at: idx)
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.0, green: 0.9, blue: 1.0), Color(red: 0.2, green: 0.95, blue: 0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2.5, height: max(4, level * 16))
                    .shadow(color: Color(red: 0.0, green: 0.9, blue: 1.0).opacity(0.4), radius: 1.5)
            }
        }
        .frame(width: 24, height: 18, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture {
            handlePlayPause()
        }
        .help(appState.playbackState == .playing ? "Pausa" : "Riproduci")
        .accessibilityLabel(appState.playbackState == .playing ? "Pausa" : "Riproduci")
    }
    
    private var verticalControlsSection: some View {
        VStack(spacing: 5) {
            // Play / Pausa
            Button(action: handlePlayPause) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                        .shadow(color: Color.white.opacity(0.35), radius: 2.5)
                    
                    Image(systemName: appState.playbackState == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.black)
                        .offset(x: appState.playbackState == .playing ? 0 : 1)
                }
            }
            .buttonStyle(.plain)
            .help(appState.playbackState == .playing ? "Pausa" : "Riproduci")
            .accessibilityLabel(appState.playbackState == .playing ? "Pausa" : "Riproduci")
            
            // Navigazione Frasi
            HStack(spacing: 3) {
                Button(action: {
                    if let coordinator = coordinator {
                        coordinator.skipBackward()
                    } else {
                        _ = appState.rewindChunk()
                    }
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 17, height: 17)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Frase precedente")
                .accessibilityLabel("Frase precedente")
                
                Button(action: {
                    if let coordinator = coordinator {
                        coordinator.skipForward()
                    } else {
                        _ = appState.advanceChunk()
                    }
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 17, height: 17)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Frase successiva")
                .accessibilityLabel("Frase successiva")
            }
            
            // Selettore Velocità
            Menu {
                ForEach([0.7, 0.85, 1.0, 1.05, 1.25, 1.5, 1.75, 2.0], id: \.self) { spd in
                    Button("\(String(format: "%.2f", spd))×") {
                        appState.setSpeed(Float(spd))
                        audioEngine.setSpeed(Float(spd))
                    }
                }
            } label: {
                Text("\(String(format: "%.2f", appState.playbackSpeed))×")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.0, green: 0.9, blue: 1.0))
                    .frame(width: 36, height: 16)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Velocità di riproduzione")
            .accessibilityLabel("Velocità: \(String(format: "%.2f", appState.playbackSpeed)) per")
            
            // Avviso Fallback (se attivo)
            if appState.isUsingSpeechFallback {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.2))
                    .help(appState.speechFallbackNotice ?? "Voce macOS di fallback")
            }
            
            // Pulsanti Pin e Chiudi
            HStack(spacing: 3) {
                Button(action: {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75)) {
                        appState.isPillExpanded.toggle()
                    }
                    if isStandalone {
                        FloatingPillPanelManager.shared.updatePanelFrame(
                            for: effectiveOrientation,
                            isExpanded: appState.isPillExpanded,
                            animated: !reduceMotion
                        )
                    }
                }) {
                    Image(systemName: appState.isPillExpanded ? "pin.fill" : "pin")
                        .font(.system(size: 9))
                        .foregroundStyle(appState.isPillExpanded ? Color(red: 0.0, green: 0.9, blue: 1.0) : .white.opacity(0.75))
                        .frame(width: 17, height: 17)
                        .background(appState.isPillExpanded ? Color(red: 0.0, green: 0.9, blue: 1.0).opacity(0.2) : Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(appState.isPillExpanded ? "Sblocca espansione" : "Blocca pillola espansa")
                .accessibilityLabel("Blocca o sblocca espansione")
                
                if isStandalone {
                    Button(action: {
                        FloatingPillPanelManager.shared.hide(appState: appState)
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 17, height: 17)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Chiudi pillola")
                    .accessibilityLabel("Chiudi pillola")
                }
            }
        }
    }
    
    // MARK: - Azioni Comuni
    
    private func handlePlayPause() {
        if appState.readingQueue.isEmpty || appState.currentChunk == nil {
            NotificationCenter.default.post(name: NSNotification.Name("CaptureAXText"), object: nil)
        } else {
            if let coordinator = coordinator {
                coordinator.togglePlayPause()
            } else {
                if appState.playbackState == .playing {
                    audioEngine.pause()
                    appState.playbackState = .paused
                } else {
                    audioEngine.play()
                    appState.playbackState = .playing
                }
            }
        }
    }
}
