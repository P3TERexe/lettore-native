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

    @State private var hoverDismissTask: Task<Void, Never>? = nil
    /// Hover della pillola incorporata nello Studio. Quella flottante usa il
    /// flag del manager, così non può restare disallineata dal frame finestra.
    @State private var isEmbeddedHovered: Bool = false
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
        if appState.isPillExpanded { return true }
        return isStandalone
            ? FloatingPillPanelManager.shared.isHoverExpanded
            : isEmbeddedHovered
    }

    private var effectiveOrientation: PillOrientation {
        return isStandalone ? appState.pillOrientation : .horizontal
    }

    /// Spazio riservato al contenuto dentro la finestra. Deriva dalle stesse
    /// metriche del pannello meno il margine di sicurezza, così il contenuto
    /// non può mai essere più grande della finestra che lo ospita.
    private var contentSize: CGSize {
        FloatingPillPanelManager.PillMetrics.contentSize(
            orientation: effectiveOrientation,
            isExpanded: isExpanded,
            isFallback: appState.isUsingSpeechFallback
        )
    }

    public var body: some View {
        ZStack {
            if effectiveOrientation == .vertical {
                verticalPill
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.94)),
                            removal: .opacity.combined(with: .scale(scale: 0.94))
                        )
                    )
            } else {
                horizontalPill
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.94)),
                            removal: .opacity.combined(with: .scale(scale: 0.94))
                        )
                    )
            }
        }
        .contentShape(Capsule())
        .animation(morphAnimation, value: effectiveOrientation)
        .animation(morphAnimation, value: isExpanded)
        .onHover { hovering in
            handleHover(hovering)
        }
        .onReceive(NotificationCenter.default.publisher(for: .floatingPillTogglePlayPause)) { _ in
            handlePlayPause()
        }
        .onChange(of: appState.isUsingSpeechFallback) { _, _ in
            // Il badge di fallback allarga il contenuto: senza questo la finestra
            // resterebbe della misura precedente e taglierebbe i controlli.
            guard isStandalone else { return }
            FloatingPillPanelManager.shared.updatePanelFrame(
                for: effectiveOrientation,
                isExpanded: isExpanded,
                animated: !reduceMotion
            )
        }
        .onDisappear {
            hoverDismissTask?.cancel()
            hoverDismissTask = nil
        }
    }

    /// Stessa curva e stessa durata del frame della finestra: se il contenuto
    /// morphasse con una spring più lenta, durante la transizione verrebbe
    /// disegnato fuori dalla capsula.
    private var morphAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: FloatingPillPanelManager.PillMetrics.morphDuration)
    }

    // MARK: - Hover

    private func handleHover(_ hovering: Bool) {
        hoverDismissTask?.cancel()
        hoverDismissTask = nil

        if hovering {
            setHoverExpanded(true)
            return
        }

        hoverDismissTask = Task { @MainActor in
            // Grace period: evita il collasso mentre il cursore attraversa il bordo.
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            setHoverExpanded(false)
        }
    }

    private func setHoverExpanded(_ expanded: Bool) {
        let isCurrentlyExpanded = isStandalone
            ? FloatingPillPanelManager.shared.isHoverExpanded
            : isEmbeddedHovered
        guard isCurrentlyExpanded != expanded else { return }

        let manager = FloatingPillPanelManager.shared
        // Durante il drag la finestra si muove sotto il cursore: cambiare forma
        // in quel momento sposterebbe il grip rispetto al mouse.
        guard !isStandalone || !manager.isDragging else { return }

        if isStandalone {
            manager.isHoverExpanded = expanded
        } else {
            isEmbeddedHovered = expanded
        }

        guard isStandalone else { return }
        manager.updatePanelFrame(
            for: effectiveOrientation,
            isExpanded: expanded || appState.isPillExpanded,
            animated: !reduceMotion
        )
    }

    private func waveformLevel(at index: Int) -> CGFloat {
        guard index >= 0 && index < appState.liveWaveformLevels.count else { return 0.15 }
        return CGFloat(appState.liveWaveformLevels[index])
    }

    // MARK: - Layout Orizzontale (Top / Centro Schermo)

    private var horizontalPill: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                if isStandalone {
                    dragGrip
                }

                horizontalWaveformSection
            }
            .padding(.leading, 8)
            .padding(.trailing, isExpanded ? 2 : 8)

            if isExpanded {
                horizontalControlsSection
                    .padding(.trailing, 8)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .leading)),
                            removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .leading))
                        )
                    )
            }
        }
        .frame(width: contentSize.width, height: contentSize.height)
        .background(pillBackground)
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
                    .fill(waveformGradient)
                    .frame(width: 2.8, height: max(5, level * 20))
                    .shadow(color: brandCyan.opacity(0.4), radius: 2)
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
            skipBackwardButton(size: 22, iconSize: 10)
            playPauseButton(size: 26, iconSize: 10)
            skipForwardButton(size: 22, iconSize: 10)
            speedMenu(width: nil, height: nil, fontSize: 9.5)

            if appState.isUsingSpeechFallback {
                fallbackBadge(size: 10)
            }

            pinButton(size: 22, iconSize: 9.5)

            if isStandalone {
                closeButton(size: 22, iconSize: 9.5)
            }
        }
    }

    // MARK: - Layout Verticale (Lati dello Schermo)

    private var verticalPill: some View {
        VStack(spacing: 6) {
            if isStandalone {
                verticalDragGrip
            }

            verticalWaveformSection

            if isExpanded {
                verticalControlsSection
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
                        )
                    )
            } else {
                verticalCompactPlayIndicator
            }
        }
        .padding(.vertical, 6)
        .frame(width: contentSize.width, height: contentSize.height, alignment: .top)
        .background(pillBackground)
        .clipShape(Capsule())
    }

    private var verticalDragGrip: some View {
        ZStack {
            NativeDragHandleView(appState: appState)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.45))
                .allowsHitTesting(false)
        }
        .frame(width: 20, height: 12)
        .help("Trascina la pillola per spostarla")
        .accessibilityLabel("Trascina pillola")
    }

    private var verticalWaveformSection: some View {
        HStack(spacing: 2.2) {
            ForEach(0..<min(4, appState.liveWaveformLevels.count), id: \.self) { idx in
                let level = waveformLevel(at: idx)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(waveformGradient)
                    .frame(width: 2.6, height: max(5, level * 18))
                    .shadow(color: brandCyan.opacity(0.4), radius: 2)
            }
        }
        .frame(width: 22, height: 20, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture {
            handlePlayPause()
        }
        .help(appState.playbackState == .playing ? "Pausa" : "Riproduci")
        .accessibilityLabel(appState.playbackState == .playing ? "Pausa" : "Riproduci")
    }

    private var verticalCompactPlayIndicator: some View {
        VStack(spacing: 4) {
            Button(action: handlePlayPause) {
                ZStack {
                    Circle()
                        .fill(appState.playbackState == .playing ? brandCyan : Color.white.opacity(0.18))
                        .frame(width: 22, height: 22)
                        .shadow(
                            color: appState.playbackState == .playing ? brandCyan.opacity(0.4) : .clear,
                            radius: 3
                        )

                    Image(systemName: appState.playbackState == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(appState.playbackState == .playing ? Color.black : Color.white)
                        .offset(x: appState.playbackState == .playing ? 0 : 0.8)
                }
            }
            .buttonStyle(.plain)
            .help(appState.playbackState == .playing ? "Pausa" : "Riproduci")
            .accessibilityLabel(appState.playbackState == .playing ? "Pausa" : "Riproduci")

            Circle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 3, height: 3)
                .allowsHitTesting(false)
        }
    }

    private var verticalControlsSection: some View {
        VStack(spacing: 6) {
            playPauseButton(size: 26, iconSize: 10)

            HStack(spacing: 3) {
                skipBackwardButton(size: 18, iconSize: 9)
                skipForwardButton(size: 18, iconSize: 9)
            }

            speedMenu(width: 34, height: 17, fontSize: 8.5)

            if appState.isUsingSpeechFallback {
                fallbackBadge(size: 9.5)
            }

            HStack(spacing: 3) {
                pinButton(size: 18, iconSize: 9)

                if isStandalone {
                    closeButton(size: 18, iconSize: 8.5)
                }
            }
        }
    }

    // MARK: - Componenti condivisi (una sola definizione per entrambi gli orientamenti)

    private var brandCyan: Color {
        Color(red: 0.0, green: 0.9, blue: 1.0)
    }

    private var waveformGradient: LinearGradient {
        LinearGradient(
            colors: [brandCyan, Color(red: 0.2, green: 0.95, blue: 0.5)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var pillBackground: some View {
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
                .shadow(color: brandCyan.opacity(isExpanded ? 0.22 : 0.08), radius: isExpanded ? 12 : 6)

            // Il drag in compatto è gestito dall'hosting view a livello di finestra,
            // quindi qui non serve un secondo overlay reattivo.
        }
    }

    private func playPauseButton(size: CGFloat, iconSize: CGFloat) -> some View {
        Button(action: handlePlayPause) {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: size, height: size)
                    .shadow(color: Color.white.opacity(0.35), radius: 3)

                Image(systemName: appState.playbackState == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(.black)
                    .offset(x: appState.playbackState == .playing ? 0 : 1)
            }
        }
        .buttonStyle(.plain)
        .help(appState.playbackState == .playing ? "Metti in pausa" : "Riproduci")
        .accessibilityLabel(appState.playbackState == .playing ? "Pausa" : "Riproduci")
    }

    private func skipBackwardButton(size: CGFloat, iconSize: CGFloat) -> some View {
        Button(action: {
            if let coordinator = coordinator {
                coordinator.skipBackward()
            } else {
                _ = appState.rewindChunk()
            }
        }) {
            Image(systemName: "backward.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: size, height: size)
                .background(Color.white.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Frase precedente")
        .accessibilityLabel("Frase precedente")
    }

    private func skipForwardButton(size: CGFloat, iconSize: CGFloat) -> some View {
        Button(action: {
            if let coordinator = coordinator {
                coordinator.skipForward()
            } else {
                _ = appState.advanceChunk()
            }
        }) {
            Image(systemName: "forward.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: size, height: size)
                .background(Color.white.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Frase successiva")
        .accessibilityLabel("Frase successiva")
    }

    private func speedMenu(width: CGFloat?, height: CGFloat?, fontSize: CGFloat) -> some View {
        Menu {
            ForEach([0.7, 0.85, 1.0, 1.05, 1.25, 1.5, 1.75, 2.0], id: \.self) { spd in
                Button("\(String(format: "%.2f", spd))×") {
                    appState.setSpeed(Float(spd))
                    audioEngine.setSpeed(Float(spd))
                }
            }
        } label: {
            Text("\(String(format: "%.2f", appState.playbackSpeed))×")
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(brandCyan)
                .frame(width: width, height: height)
                .padding(.horizontal, width == nil ? 5 : 0)
                .padding(.vertical, width == nil ? 2.5 : 0)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: width == nil ? 5 : 4.5))
        }
        .buttonStyle(.plain)
        .help("Velocità di riproduzione")
        .accessibilityLabel("Velocità: \(String(format: "%.2f", appState.playbackSpeed)) per")
    }

    private func fallbackBadge(size: CGFloat) -> some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.2))
            .help(appState.speechFallbackNotice ?? "Voce macOS di fallback attiva (backend Supertonic offline)")
    }

    private func pinButton(size: CGFloat, iconSize: CGFloat) -> some View {
        Button(action: {
            appState.isPillExpanded.toggle()
            if isStandalone {
                FloatingPillPanelManager.shared.updatePanelFrame(
                    for: effectiveOrientation,
                    isExpanded: isExpanded,
                    animated: !reduceMotion
                )
            }
        }) {
            Image(systemName: appState.isPillExpanded ? "pin.fill" : "pin")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(appState.isPillExpanded ? brandCyan : .white.opacity(0.75))
                .frame(width: size, height: size)
                .background(appState.isPillExpanded ? brandCyan.opacity(0.2) : Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(appState.isPillExpanded ? "Sblocca espansione automatica" : "Blocca pillola espansa")
        .accessibilityLabel(appState.isPillExpanded ? "Sblocca espansione" : "Blocca pillola espansa")
    }

    private func closeButton(size: CGFloat, iconSize: CGFloat) -> some View {
        Button(action: {
            FloatingPillPanelManager.shared.hide(appState: appState)
        }) {
            Image(systemName: "xmark")
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: size, height: size)
                .background(Color.white.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Chiudi la pillola fluttuante")
        .accessibilityLabel("Chiudi pillola")
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
