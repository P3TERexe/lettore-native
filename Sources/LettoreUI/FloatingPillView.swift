import SwiftUI
import LettoreCore
import LettoreEngine

/// Vista della pillola fluttuante con animazione elastica Dynamic Island a due stati.
/// Stato normale: solo onda vocale compatta.
/// Stato hover: espansione dei controlli di riproduzione.
public struct FloatingPillView: View {
    @Bindable public var appState: AppState
    public var audioEngine: AudioEngineService
    public var coordinator: PlaybackCoordinator?
    
    @State private var isHovered: Bool = false
    
    public init(
        appState: AppState,
        audioEngine: AudioEngineService,
        coordinator: PlaybackCoordinator? = nil
    ) {
        self.appState = appState
        self.audioEngine = audioEngine
        self.coordinator = coordinator
    }
    
    public var body: some View {
        ZStack {
            if appState.pillOrientation == .vertical {
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
        .animation(.spring(response: 0.38, dampingFraction: 0.76), value: appState.pillOrientation)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isHovered)
        .onHover { hovering in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                self.isHovered = hovering
            }
        }
    }
    
    // MARK: - Layout Orizzontale (Centro Schermo)
    
    private var horizontalPill: some View {
        HStack(spacing: 0) {
            // Sezione Onde Vocali Orizzontale
            horizontalWaveformSection
                .padding(.leading, 14)
            
            // Sezione Controlli a Comparsa Orizzontale
            if isHovered || appState.isPillExpanded {
                horizontalControlsSection
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.85, anchor: .leading)),
                            removal: .opacity.combined(with: .scale(scale: 0.85, anchor: .leading))
                        )
                    )
            }
        }
        .frame(height: 44)
        .frame(width: isHovered || appState.isPillExpanded ? 356 : 120, alignment: .leading)
        .background {
            Capsule()
                .fill(Color(red: 0.05, green: 0.05, blue: 0.07).opacity(0.92))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isHovered ? Color.white.opacity(0.35) : Color.white.opacity(0.18),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.7), radius: isHovered ? 25 : 12, y: 10)
                .shadow(
                    color: Color(red: 0.0, green: 0.9, blue: 1.0).opacity(isHovered ? 0.25 : 0.1),
                    radius: isHovered ? 20 : 8
                )
        }
        .overlay(alignment: .bottom) {
            // Progress bar orizzontale nella sezione piatta inferiore
            if !appState.readingQueue.isEmpty {
                GeometryReader { geo in
                    let trackWidth = max(0, geo.size.width - 44)
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
        }
        .clipShape(Capsule())
    }
    
    private var horizontalWaveformSection: some View {
        HStack(spacing: 3.5) {
            ForEach(0..<appState.liveWaveformLevels.count, id: \.self) { idx in
                let level = CGFloat(appState.liveWaveformLevels[idx])
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.0, green: 0.9, blue: 1.0), Color(red: 0.2, green: 0.95, blue: 0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3.5, height: max(6, level * 26))
                    .shadow(color: Color(red: 0.0, green: 0.9, blue: 1.0).opacity(0.4), radius: 3)
            }
        }
        .frame(width: 85, height: 26, alignment: .center)
    }
    
    private var horizontalControlsSection: some View {
        HStack(spacing: 10) {
            // Salto indietro 5s
            Button(action: {
                if let coordinator = coordinator {
                    coordinator.skipBackward()
                } else {
                    _ = appState.rewindChunk()
                }
            }) {
                Text("↺ 5s")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
            // Play / Pausa
            Button(action: handlePlayPause) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 28, height: 28)
                        .shadow(color: Color.white.opacity(0.3), radius: 4)
                    
                    Image(systemName: appState.playbackState == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .offset(x: appState.playbackState == .playing ? 0 : 1)
                }
            }
            .buttonStyle(.plain)
            
            // Salto avanti 15s
            Button(action: {
                if let coordinator = coordinator {
                    coordinator.skipForward()
                } else {
                    _ = appState.advanceChunk()
                }
            }) {
                Text("15s ↻")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
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
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.0, green: 0.9, blue: 1.0))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            
            // Navigazione Paragrafi
            HStack(spacing: 4) {
                Button(action: {
                    if let coordinator = coordinator {
                        coordinator.skipBackward()
                    } else {
                        _ = appState.rewindChunk()
                    }
                }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    if let coordinator = coordinator {
                        coordinator.skipForward()
                    } else {
                        _ = appState.advanceChunk()
                    }
                }) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 14)
        }
        .padding(.leading, 8)
    }
    
    // MARK: - Layout Verticale (Lati dello Schermo)
    
    private var verticalPill: some View {
        VStack(spacing: 8) {
            // Sezione Onde Vocali Verticale (in alto)
            verticalWaveformSection
                .padding(.top, isHovered || appState.isPillExpanded ? 10 : 13)
            
            // Sezione Controlli Verticali a Comparsa (espansione verso il basso)
            if isHovered || appState.isPillExpanded {
                verticalControlsSection
                    .padding(.bottom, 10)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.85, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.85, anchor: .top))
                        )
                    )
            }
        }
        .frame(width: 56)
        .frame(height: isHovered || appState.isPillExpanded ? 188 : 48, alignment: .top)
        .background {
            Capsule()
                .fill(Color(red: 0.05, green: 0.05, blue: 0.07).opacity(0.94))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isHovered ? Color.white.opacity(0.35) : Color.white.opacity(0.18),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.7), radius: isHovered ? 20 : 10, y: 8)
                .shadow(
                    color: Color(red: 0.0, green: 0.9, blue: 1.0).opacity(isHovered ? 0.22 : 0.08),
                    radius: isHovered ? 16 : 6
                )
        }
        .overlay(alignment: appState.pillDockSide == .right ? .leading : .trailing) {
            // Progress bar verticale lungo il bordo rivolto verso lo schermo
            if !appState.readingQueue.isEmpty {
                GeometryReader { geo in
                    let trackHeight = max(0, geo.size.height - 40)
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
        }
        .clipShape(Capsule())
    }
    
    private var verticalWaveformSection: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<5, id: \.self) { idx in
                let level = CGFloat(appState.liveWaveformLevels[idx + 1])
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
        .frame(width: 28, height: 20, alignment: .center)
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
            
            // Salto indietro 5s
            Button(action: {
                if let coordinator = coordinator {
                    coordinator.skipBackward()
                } else {
                    _ = appState.rewindChunk()
                }
            }) {
                Text("↺5s")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 38, height: 20)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
            // Salto avanti 15s
            Button(action: {
                if let coordinator = coordinator {
                    coordinator.skipForward()
                } else {
                    _ = appState.advanceChunk()
                }
            }) {
                Text("15s↻")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 38, height: 20)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
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
            
            // Navigazione Paragrafi
            HStack(spacing: 6) {
                Button(action: {
                    if let coordinator = coordinator {
                        coordinator.skipBackward()
                    } else {
                        _ = appState.rewindChunk()
                    }
                }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    if let coordinator = coordinator {
                        coordinator.skipForward()
                    } else {
                        _ = appState.advanceChunk()
                    }
                }) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
            }
            .frame(height: 16)
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
