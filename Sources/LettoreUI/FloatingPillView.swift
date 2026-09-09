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
        HStack(spacing: 0) {
            // Sezione Onde Vocali (Sempre visibile)
            waveformSection
                .padding(.leading, 14)
            
            // Sezione Controlli a Comparsa (Svelata su Hover)
            if isHovered || appState.isPillExpanded {
                controlsSection
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.85, anchor: .leading)),
                            removal: .opacity.combined(with: .scale(scale: 0.85, anchor: .leading))
                        )
                    )
            }
        }
        .frame(height: 44)
        .frame(width: isHovered || appState.isPillExpanded ? 440 : 120, alignment: .leading)
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
            // Progress bar sottile nel bordo inferiore della pillola
            if !appState.readingQueue.isEmpty {
                GeometryReader { geo in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.0, green: 0.9, blue: 1.0), Color(red: 0.2, green: 0.95, blue: 0.5)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progressFraction, height: 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.easeInOut(duration: 0.3), value: progressFraction)
                }
                .frame(height: 3)
                .clipShape(Capsule())
                .padding(.horizontal, 1)
                .padding(.bottom, 1)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isHovered)
        .onHover { hovering in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                self.isHovered = hovering
            }
        }
    }
    
    private var progressFraction: CGFloat {
        guard !appState.readingQueue.isEmpty else { return 0 }
        let currentIndex = appState.currentChunk?.index ?? 0
        return CGFloat(currentIndex + 1) / CGFloat(appState.readingQueue.count)
    }
    
    // MARK: - Subviews
    
    private var waveformSection: some View {
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
    
    private var controlsSection: some View {
        HStack(spacing: 12) {
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
            
            // Play / Pausa con Anello di Avanzamento Circolare
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 2.5)
                    .frame(width: 32, height: 32)
                
                Circle()
                    .trim(from: 0.0, to: appState.playbackState == .playing ? 0.85 : 0.25)
                    .stroke(
                        Color(red: 0.2, green: 0.95, blue: 0.5),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 32, height: 32)
                
                Button(action: {
                    // Se la coda è vuota o abbiamo finito le frasi, cattura nuovo testo (come Cmd+Shift+C)
                    if appState.readingQueue.isEmpty || appState.currentChunk == nil {
                        NotificationCenter.default.post(name: NSNotification.Name("CaptureAXText"), object: nil)
                    } else {
                        // Altrimenti si comporta come un normale Play/Pausa
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
                }) {
                    Image(systemName: appState.playbackState == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 24, height: 24)
                        .background(Color.white)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            
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
                Button(action: { _ = appState.rewindChunk() }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                
                Button(action: { _ = appState.advanceChunk() }) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 14)
        }
        .padding(.leading, 8)
    }
}
