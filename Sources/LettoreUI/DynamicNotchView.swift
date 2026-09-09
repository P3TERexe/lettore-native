import SwiftUI
import LettoreCore
import LettoreEngine

/// Vista ancorata alla tacca (Notch) del MacBook con espansione organica delle ali sinistra/destra.
public struct DynamicNotchView: View {
    @Bindable public var appState: AppState
    public var audioEngine: AudioEngineService
    
    public init(appState: AppState, audioEngine: AudioEngineService) {
        self.appState = appState
        self.audioEngine = audioEngine
    }
    
    public var body: some View {
        HStack(spacing: 24) {
            // Ala Sinistra della Tacca: Onde Vocali Fluide
            HStack(spacing: 3) {
                ForEach(0..<appState.liveWaveformLevels.count, id: \.self) { idx in
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
            
            // Spazio Centrale riservato alla sagoma fisica della camera hardware
            Spacer()
                .frame(width: 140)
            
            // Ala Destra della Tacca: Controlli Rapidi
            HStack(spacing: 10) {
                Button(action: {
                    if appState.playbackState == .playing {
                        audioEngine.pause()
                        appState.playbackState = .paused
                    } else {
                        audioEngine.play()
                        appState.playbackState = .playing
                    }
                }) {
                    Image(systemName: appState.playbackState == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(red: 0.0, green: 0.9, blue: 1.0))
                }
                .buttonStyle(.plain)
                
                Text("\(String(format: "%.2f", appState.playbackSpeed))×")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                
                Button(action: { _ = appState.rewindChunk() }) {
                    Image(systemName: "goforward.5")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
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
}
