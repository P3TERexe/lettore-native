import SwiftUI
import LettoreCore

/// Barre dell'onda vocale live in una view dedicata.
///
/// La lettura di `liveWaveformLevels` resta confinata a questo body: il
/// campionamento a 20 Hz invalida solo questa vista, non le schermate che la
/// ospitano. I parametri replicano le cinque rese esistenti (Studio, vista
/// accessibile, Notch, pillola orizzontale e pillola verticale) senza
/// cambiarne l'aspetto.
public struct WaveformBarsView: View {
    public let appState: AppState
    /// Numero massimo di barre; `nil` significa tutte quelle disponibili.
    public let maxBars: Int?
    public let spacing: CGFloat
    /// Larghezza fissa della barra; `nil` significa barra elastica.
    public let barWidth: CGFloat?
    /// Altezza massima a livello 1.0, prima del minimo.
    public let maxBarHeight: CGFloat
    public let minBarHeight: CGFloat
    /// Raggio degli angoli; `nil` disegna una capsula.
    public let cornerRadius: CGFloat?
    public let fill: AnyShapeStyle
    public let shadowColor: Color
    public let shadowRadius: CGFloat

    public init(
        appState: AppState,
        maxBars: Int? = nil,
        spacing: CGFloat,
        barWidth: CGFloat? = nil,
        maxBarHeight: CGFloat,
        minBarHeight: CGFloat,
        cornerRadius: CGFloat? = nil,
        fill: AnyShapeStyle,
        shadowColor: Color = .clear,
        shadowRadius: CGFloat = 0
    ) {
        self.appState = appState
        self.maxBars = maxBars
        self.spacing = spacing
        self.barWidth = barWidth
        self.maxBarHeight = maxBarHeight
        self.minBarHeight = minBarHeight
        self.cornerRadius = cornerRadius
        self.fill = fill
        self.shadowColor = shadowColor
        self.shadowRadius = shadowRadius
    }

    public var body: some View {
        let levels = appState.liveWaveformLevels
        let count = min(maxBars ?? levels.count, levels.count)

        HStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { idx in
                bar(level: CGFloat(levels[idx]))
            }
        }
    }

    @ViewBuilder
    private func bar(level: CGFloat) -> some View {
        let height = max(minBarHeight, level * maxBarHeight)
        if shadowRadius > 0 {
            barBody(height: height)
                .shadow(color: shadowColor, radius: shadowRadius)
        } else {
            barBody(height: height)
        }
    }

    @ViewBuilder
    private func barBody(height: CGFloat) -> some View {
        if let barWidth {
            barShape
                .frame(width: barWidth, height: height)
        } else {
            barShape
                .frame(maxWidth: .infinity)
                .frame(height: height)
        }
    }

    private var barShape: some View {
        Group {
            if let cornerRadius {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(fill)
            } else {
                Capsule()
                    .fill(fill)
            }
        }
    }
}
