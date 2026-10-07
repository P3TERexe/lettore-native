import SwiftUI
import LettoreCore
import LettoreEngine

/// Vista della pillola fluttuante con animazione elastica Dynamic Island a due stati.
/// - Stato compatto: visualizzatore onde vocali reattivo, drag grip e rapido feedback play/pause.
/// - Stato espanso: controlli completi (Frase Precedente/Successiva, Play/Pausa, Velocità, Pin, Chiudi).
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
        return isStandalone ? appState.pillOrientation : .horizontal
    }
    
    public var body: some View {
        ZStack {
            if effectiveOrientation == .vertical {
                verticalPill
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92)),
                        removal: .opacity.combined(with: .scale(scale: 0.92))
                    ))
            } else {
                horizontalPill
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92)),
                        removal: .opacity.combined(with: .scale(scale: 0.92))
                    ))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.76), value: effectiveOrientation)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75), value: isExpanded)
        .onHover { hovering in
            handleHover(hovering)
        }
    }
    
    // MARK: - Gestione Hover con Grace Period
    
    private func handleHover(_ hovering: Bool) {
        if hovering {
            hoverDismissTask?.cancel()
            hoverDismissTask = nil
            if !isHovered {
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75)) {
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
                // 350ms di tolleranza per evitare chiusure brusche accidentali
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if !appState.isPillExpanded {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75)) {
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
    
    // MARK: - Drag Gesture per NSPanel
    
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { gesture in
                guard isStandalone else { return }
                FloatingPillPanelManager.shared.dragPanel(
                    deltaX: gesture.translation.width,
                    deltaY: gesture.translation.height
                )
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
        HStack(spacing: 0) {
            // Grip di trascinamento e sezione onde
            HStack(spacing: 6) {
                if isStandalone {
                    dragGrip
                }
                
                horizontalWaveformSection
            }
            .padding(.leading, isStandalone ? 10 : 14)
            .padding(.trailing, isExpanded ? 6 : 14)
            
            // Sezione Controlli a Comparsa Orizzontale
            if isExpanded {
                horizontalControlsSection
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.88, anchor: .leading)),
                            removal: .opacity.combined(with: .scale(scale: 0.88, anchor: .leading))
                        )
                    )
            }
        }
        .frame(height: 44)
        .frame(width: isExpanded ? 360 : (isStandalone ? 140 : 120), alignment: .leading)
        .background {
            Capsule()
                .fill(Color(red: 0.05, green: 0.05, blue: 0.07).opacity(0.94))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isExpanded ? Color.white.opacity(0.35) : Color.white.opacity(0.18),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.7), radius: isExpanded ? 20 : 10, y: 8)
                .shadow(
                    color: Color(red: 0.0, green: 0.9, blue: 1.0).opacity(isExpanded ? 0.25 : 0.1),
                    radius: isExpanded ? 16 : 8
                )
        }
        .overlay(alignment: .bottom) {
            if !appState.readingQueue.isEmpty {
                horizontalProgressBar
            }
        }
        .clipShape(Capsule())
    }
    
    private var dragGrip: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white.opacity(0.4))
            .frame(width: 14, height: 26)
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .help("Trascina per spostare la pillola sullo schermo")
            .accessibilityLabel("Trascina pillola")
    }
    
    private var horizontalWaveformSection: some View {
        HStack(spacing: 3) {
            ForEach(0..<min(7, appState.liveWaveformLevels.count), id: \.self) { idx in
                let level = waveformLevel(at: idx)
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.0, green: 0.9, blue: 1.0), Color(red: 0.2, green: 0.95, blue: 0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3.2, height: max(6, level * 26))
                    .shadow(color: Color(red: 0.0, green: 0.9, blue: 1.0).opacity(0.4), radius: 2)
            }
        }
        .frame(width: isExpanded ? 46 : 68, height: 26, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture {
            handlePlayPause()
        }
        .help(appState.playbackState == .playing ? "Pausa" : "Riproduci")
        .accessibilityLabel(appState.playbackState == .playing ? "Pausa" : "Riproduci")
    }
    
    private var horizontalProgressBar: some View {
        GeometryReader { geo in
            let trackWidth = max(0, geo.size.width - 40)
            let progress = max(0.0, min(1.0, appState.playbackProgress))
            let fillWidth = max(0, trackWidth * CGFloat(progress))
            
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: trackWidth, height: 2.5)
                
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.0, green: 0.9, blue: 1.0), Color(red: 0.2, green: 0.95, blue: 0.5)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth, height: 2.5)
                    .shadow(color: Color(red: 0.0, green: 0.9, blue: 1.0).opacity(0.5), radius: 2)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: 2.5)
        .padding(.bottom, 2.5)
    }
    
    private var horizontalControlsSection: some View {
        HStack(spacing: 8) {
            // Frase precedente
            Button(action: {
                if let coordinator = coordinator {
                    coordinator.skipBackward()
                } else {
                    _ = appState.rewindChunk()
                }
            }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 26, height: 26)
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
                        .frame(width: 28, height: 28)
                        .shadow(color: Color.white.opacity(0.35), radius: 4)
                    
                    Image(systemName: appState.playbackState == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 26, height: 26)
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
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.0, green: 0.9, blue: 1.0))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Velocità di riproduzione")
            .accessibilityLabel("Velocità: \(String(format: "%.2f", appState.playbackSpeed)) per")
            
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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(appState.isPillExpanded ? Color(red: 0.0, green: 0.9, blue: 1.0) : .white.opacity(0.75))
                    .frame(width: 24, height: 24)
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
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Chiudi la pillola fluttuante")
                .accessibilityLabel("Chiudi pillola")
            }
        }
        .padding(.trailing, 10)
    }
    
    // MARK: - Layout Verticale (Lati dello Schermo)
    
    private var verticalPill: some View {
        VStack(spacing: 6) {
            // Drag grip in alto
            if isStandalone {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 28, height: 10)
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    .padding(.top, 6)
            }
            
            // Sezione Onde Vocali Verticale (tappabile per Play/Pausa)
            verticalWaveformSection
                .padding(.top, isStandalone ? 0 : 8)
                .padding(.bottom, isExpanded ? 0 : (isStandalone ? 6 : 8))
            
            // Sezione Controlli Verticali a Comparsa
            if isExpanded {
                verticalControlsSection
                    .padding(.bottom, 8)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.88, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.88, anchor: .top))
                        )
                    )
            }
        }
        .frame(width: 54)
        .frame(height: isExpanded ? 220 : 54, alignment: .top)
        .background {
            Capsule()
                .fill(Color(red: 0.05, green: 0.05, blue: 0.07).opacity(0.94))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isExpanded ? Color.white.opacity(0.35) : Color.white.opacity(0.18),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.7), radius: isExpanded ? 20 : 10, y: 8)
                .shadow(
                    color: Color(red: 0.0, green: 0.9, blue: 1.0).opacity(isExpanded ? 0.22 : 0.08),
                    radius: isExpanded ? 16 : 6
                )
        }
        .overlay(alignment: appState.pillDockSide == .right ? .leading : .trailing) {
            if !appState.readingQueue.isEmpty {
                verticalProgressBar
            }
        }
        .clipShape(Capsule())
    }
    
    private var verticalWaveformSection: some View {
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
                    .frame(width: 3, height: max(5, level * 18))
                    .shadow(color: Color(red: 0.0, green: 0.9, blue: 1.0).opacity(0.4), radius: 2)
            }
        }
        .frame(width: 30, height: 20, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture {
            handlePlayPause()
        }
        .help(appState.playbackState == .playing ? "Pausa" : "Riproduci")
        .accessibilityLabel(appState.playbackState == .playing ? "Pausa" : "Riproduci")
    }
    
    private var verticalProgressBar: some View {
        GeometryReader { geo in
            let trackHeight = max(0, geo.size.height - 36)
            let progress = max(0.0, min(1.0, appState.playbackProgress))
            let fillHeight = max(0, trackHeight * CGFloat(progress))
            
            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 2.5, height: trackHeight)
                
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.0, green: 0.9, blue: 1.0), Color(red: 0.2, green: 0.95, blue: 0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2.5, height: fillHeight)
                    .shadow(color: Color(red: 0.0, green: 0.9, blue: 1.0).opacity(0.6), radius: 2)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(width: 2.5)
        .padding(appState.pillDockSide == .right ? .leading : .trailing, 2.5)
    }
    
    private var verticalControlsSection: some View {
        VStack(spacing: 6) {
            // Play / Pausa
            Button(action: handlePlayPause) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 28, height: 28)
                        .shadow(color: Color.white.opacity(0.35), radius: 3)
                    
                    Image(systemName: appState.playbackState == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .offset(x: appState.playbackState == .playing ? 0 : 1)
                }
            }
            .buttonStyle(.plain)
            .help(appState.playbackState == .playing ? "Pausa" : "Riproduci")
            .accessibilityLabel(appState.playbackState == .playing ? "Pausa" : "Riproduci")
            
            // Navigazione Frasi
            HStack(spacing: 4) {
                Button(action: {
                    if let coordinator = coordinator {
                        coordinator.skipBackward()
                    } else {
                        _ = appState.rewindChunk()
                    }
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 20, height: 20)
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
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 20, height: 20)
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
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.0, green: 0.9, blue: 1.0))
                    .frame(width: 40, height: 18)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("Velocità di riproduzione")
            .accessibilityLabel("Velocità: \(String(format: "%.2f", appState.playbackSpeed)) per")
            
            // Pulsanti Pin e Chiudi
            HStack(spacing: 4) {
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
                        .font(.system(size: 9.5))
                        .foregroundStyle(appState.isPillExpanded ? Color(red: 0.0, green: 0.9, blue: 1.0) : .white.opacity(0.75))
                        .frame(width: 20, height: 20)
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
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 20, height: 20)
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
