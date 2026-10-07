import SwiftUI
import LettoreCore
import LettoreEngine

/// Vista ancorata alla tacca (Notch) del MacBook con espansione organica delle ali sinistra/destra.
public struct DynamicNotchView: View {
    @Bindable public var appState: AppState
    public var audioEngine: AudioEngineService
    public var coordinator: PlaybackCoordinator?
    
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
        HStack(spacing: 24) {
            // Ala Sinistra della Tacca: Onde Vocali Fluide
            HStack(spacing: 3) {
                ForEach(0..<min(7, appState.liveWaveformLevels.count), id: \.self) { idx in
                    let level = CGFloat(appState.liveWaveformLevels[idx])
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.0, green: 0.9, blue: 1.0), Color.purple],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3, height: max(5, level * 20))
                }
            }
            .frame(width: 80, height: 28)
            .contentShape(Rectangle())
            .onTapGesture {
                handleTogglePlayPause()
            }
            .help("Riproduci o sospendi audio")
            .accessibilityLabel("Onda sonora")
            
            // Spazio Centrale riservato alla sagoma fisica della camera hardware
            Spacer()
                .frame(width: 140)
            
            // Ala Destra della Tacca: Controlli Rapidi Coordinati
            HStack(spacing: 10) {
                // Frase precedente
                Button(action: {
                    if let coordinator = coordinator {
                        coordinator.skipBackward()
                    } else {
                        _ = appState.rewindChunk()
                    }
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("Frase precedente")
                .accessibilityLabel("Frase precedente")
                
                // Play / Pausa
                Button(action: handleTogglePlayPause) {
                    Image(systemName: appState.playbackState == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(red: 0.0, green: 0.9, blue: 1.0))
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
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("Frase successiva")
                .accessibilityLabel("Frase successiva")
                
                // Velocità
                Text("\(String(format: "%.2f", appState.playbackSpeed))×")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black)
                .shadow(color: Color.black.opacity(0.5), radius: 10, y: 5)
        }
    }
    
    private func handleTogglePlayPause() {
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
