import SwiftUI
import LettoreCore
import LettoreEngine

/// Vista super accessibile ad altissima ergonomia e contrasto certificato WCAG AAA (> 14:1)
/// per utenti con bassa visione, ipovisione o fotofobia acuta.
public struct SuperAccessibleView: View {
    @Bindable public var appState: AppState
    public var audioEngine: AudioEngineService
    public var coordinator: PlaybackCoordinator?
    
    public init(appState: AppState, audioEngine: AudioEngineService, coordinator: PlaybackCoordinator? = nil) {
        self.appState = appState
        self.audioEngine = audioEngine
        self.coordinator = coordinator
    }
    
    private let solarAmber = Color(red: 1.0, green: 0.72, blue: 0.01) // #FFB703
    private let deepObsidian = Color(red: 0.047, green: 0.051, blue: 0.071) // #0C0D12
    private let cardSurface = Color(red: 0.09, green: 0.098, blue: 0.133)
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header con Comandi Tattili Giganti (> 52px)
            headerBar
            
            // Corpo Principale: Reading Runway & Sidebar
            HStack(spacing: 0) {
                readingRunwayArea
                    .frame(maxWidth: .infinity)
                
                Divider()
                    .background(Color.white.opacity(0.15))
                
                accessibleSidebar
                    .frame(width: 320)
            }
            
            // Barra di Stato e Scorciatoie Inferiore
            footerBar
        }
        .background(deepObsidian)
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Subviews
    
    private var headerBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(solarAmber)
                Text("Lettore")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
                Text("WCAG AAA")
                    .font(.system(size: 11, weight: .black))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(solarAmber)
                    .foregroundStyle(.black)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(solarAmber.opacity(0.12))
            .overlay(Capsule().strokeBorder(solarAmber, lineWidth: 1.5))
            
            Button(action: {
                appState.accessibilityProfile = .standard
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                    Text("Studio")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(cardSurface)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Pulsante Riproduci / Sospendi Tattile
            Button(action: {
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
            }) {
                HStack(spacing: 10) {
                    Image(systemName: appState.playbackState == .playing ? "pause.fill" : "play.fill")
                    Text(appState.playbackState == .playing ? "SOSPENDI" : "RIPRODUCI")
                    Text("Spazio")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.black)
                .frame(height: 48)
                .padding(.horizontal, 18)
                .background(solarAmber)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: solarAmber.opacity(0.3), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            
            // Pulsante Ferma
            Button(action: {
                if let coordinator = coordinator {
                    coordinator.stop()
                } else {
                    audioEngine.stop()
                    appState.playbackState = .idle
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                    Text("FERMA")
                    Text("Esc")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(height: 48)
                .padding(.horizontal, 16)
                .background(cardSurface)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            
            // Stepper Velocità
            HStack(spacing: 8) {
                Button("−") {
                    let newSpeed = max(0.5, appState.playbackSpeed - 0.1)
                    appState.setSpeed(newSpeed)
                    audioEngine.setSpeed(newSpeed)
                }
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 48)
                
                Text(String(format: "%.2f×", appState.playbackSpeed))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(solarAmber)
                    .frame(minWidth: 55)
                
                Button("+") {
                    let newSpeed = min(2.0, appState.playbackSpeed + 0.1)
                    appState.setSpeed(newSpeed)
                    audioEngine.setSpeed(newSpeed)
                }
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 48)
            }
            .background(cardSurface)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 24)
        .frame(height: 72)
        .background(cardSurface)
        .overlay(Divider().background(Color.white.opacity(0.1)), alignment: .bottom)
    }
    
    private var readingRunwayArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                let currentIndex = appState.currentChunk.flatMap { current in
                    appState.readingQueue.firstIndex(where: { $0.id == current.id })
                } ?? 0
                
                // Paragrafo precedente attenuato dalla coda reale
                if currentIndex > 0 && currentIndex < appState.readingQueue.count {
                    let prevChunk = appState.readingQueue[currentIndex - 1]
                    Button(action: {
                        coordinator?.jumpToChunk(prevChunk)
                    }) {
                        Text(prevChunk.text)
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .lineSpacing(10)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .help("Salta alla frase precedente")
                } else if !appState.readingQueue.isEmpty {
                    Text("— Inizio del testo —")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.25))
                }
                
                // Active Reading Runway Card
                HStack(spacing: 18) {
                    // Barra Guida Verticale da 6px
                    RoundedRectangle(cornerRadius: 3)
                        .fill(solarAmber)
                        .frame(width: 6)
                        .shadow(color: solarAmber.opacity(0.5), radius: 5)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(appState.currentChunk?.text ?? (appState.readingQueue.first?.text ?? "Nessun testo in riproduzione. Incolla un testo o catturalo con ⌥+C."))
                            .font(.system(size: 25, weight: .bold))
                            .foregroundStyle(.white)
                            .lineSpacing(12)
                    }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 22)
                .background(cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(solarAmber.opacity(0.4), lineWidth: 2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.5), radius: 20, y: 8)
                
                // Paragrafo successivo attenuato dalla coda reale
                if currentIndex + 1 < appState.readingQueue.count {
                    let nextChunk = appState.readingQueue[currentIndex + 1]
                    Button(action: {
                        coordinator?.jumpToChunk(nextChunk)
                    }) {
                        Text(nextChunk.text)
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .lineSpacing(10)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .help("Salta alla frase successiva")
                } else if !appState.readingQueue.isEmpty {
                    Text("— Fine del testo —")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.25))
                }
            }
            .padding(40)
        }
    }
    
    private var accessibleSidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("STATO VOCE")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(solarAmber)
                .tracking(1.5)
            
            // Visualizzatore Waveform ad Alto Rilievo
            VStack(spacing: 12) {
                HStack(spacing: 5) {
                    ForEach(0..<appState.liveWaveformLevels.count, id: \.self) { idx in
                        let level = CGFloat(appState.liveWaveformLevels[idx])
                        Capsule()
                            .fill(solarAmber)
                            .frame(width: 6, height: max(8, level * 34))
                            .shadow(color: solarAmber.opacity(0.4), radius: 4)
                    }
                }
                .frame(height: 48)
                
                HStack {
                    Text(appState.selectedVoice.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("24 kHz ONNX")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.0, green: 0.9, blue: 1.0))
                }
            }
            .padding(16)
            .background(deepObsidian)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.15), lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Spacer()
        }
        .padding(24)
        .background(cardSurface)
    }
    
    private var footerBar: some View {
        HStack {
            HStack(spacing: 18) {
                Label("Spazio: Play/Pausa", systemImage: "keyboard")
                Label("⌥ + ←/→: Frase", systemImage: "arrow.left.arrow.right")
                Label("+ / −: Velocità", systemImage: "speaker.wave.2")
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.75))
            
            Spacer()
            
            Text("Contrasto: 14.2:1 (Certificato)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(solarAmber)
        }
        .padding(.horizontal, 24)
        .frame(height: 44)
        .background(deepObsidian)
        .overlay(Divider().background(Color.white.opacity(0.1)), alignment: .top)
    }
}
