import Foundation
import CoreGraphics

/// Geometria pura della pillola fluttuante.
///
/// Possiede dimensioni canoniche, ancoraggio del grip, clamp allo schermo e
/// isteresi del docking. Non conosce AppKit: il pannello host si limita ad
/// applicare i frame calcolati qui.
public enum PillGeometry {
    /// Dimensioni canoniche della finestra. Unica fonte di verità: il contenuto
    /// SwiftUI resta sempre più piccolo di questi valori, mai più grande.
    public static let horizontalCompact = CGSize(width: 104, height: 42)
    public static let horizontalExpanded = CGSize(width: 282, height: 42)
    public static let horizontalExpandedFallback = CGSize(width: 298, height: 42)
    public static let verticalCompact = CGSize(width: 48, height: 104)
    public static let verticalExpanded = CGSize(width: 48, height: 170)
    public static let verticalExpandedFallback = CGSize(width: 48, height: 192)

    /// Margine di sicurezza dai bordi dello schermo visibile.
    public static let screenInset: CGFloat = 8

    /// Distanza entro cui la pillola si aggancia al bordo laterale mentre
    /// viene trascinata. L'aggancio è "morbido": una volta docked, la
    /// pillola resta al bordo finché il cursore non si allontana oltre
    /// `dockExitThreshold`, così il magnete non sfarfalla sul confine.
    public static let dockThreshold: CGFloat = 60

    /// Soglia di uscita dal dock (isteresi). Più alta della soglia di
    /// ingresso per evitare oscillazioni orizzontale ↔ verticale.
    public static let dockExitThreshold: CGFloat = 130

    /// Spostamento massimo del cursore (in punti) entro cui un click resta
    /// un tap: oltre è un trascinamento. Il tremolio della mano su un click
    /// reale arriva a 4-5px, quindi la soglia deve essere più larga.
    public static let tapThreshold: CGFloat = 8

    /// Durata del morphing, condivisa da finestra e contenuto SwiftUI.
    /// Una sola curva per entrambi: se divergono, il contenuto viene
    /// disegnato fuori dalla capsula durante la transizione.
    public static let morphDuration: TimeInterval = 0.28

    public static func panelSize(orientation: PillOrientation, isExpanded: Bool, isFallback: Bool) -> CGSize {
        switch orientation {
        case .horizontal:
            if !isExpanded { return horizontalCompact }
            return isFallback ? horizontalExpandedFallback : horizontalExpanded
        case .vertical:
            if !isExpanded { return verticalCompact }
            return isFallback ? verticalExpandedFallback : verticalExpanded
        }
    }

    /// Il contenuto SwiftUI è sempre più piccolo della finestra che lo ospita.
    public static func contentSize(orientation: PillOrientation, isExpanded: Bool, isFallback: Bool) -> CGSize {
        let panel = panelSize(orientation: orientation, isExpanded: isExpanded, isFallback: isFallback)
        let horizontalInset: CGFloat = orientation == .horizontal ? 8 : 6
        return CGSize(width: panel.width - horizontalInset, height: panel.height - 6)
    }

    /// Calcola il frame obiettivo a partire da un frame corrente.
    /// Funzione pura sulla geometria: nessun accesso a stato o schermi reali.
    ///
    /// `dockSide` è esplicito: l'isteresi vive in `resolvedDock`, non qui.
    public static func resolvedFrame(
        current: CGRect,
        screenRect: CGRect,
        orientation: PillOrientation,
        isExpanded: Bool,
        isFallback: Bool,
        dockSide: PillDockSide = .center
    ) -> CGRect {
        let targetSize = panelSize(
            orientation: orientation,
            isExpanded: isExpanded,
            isFallback: isFallback
        )
        var newOrigin = current.origin

        switch orientation {
        case .horizontal:
            // Grip a sinistra: resta fermo il bordo sinistro. Il clamp sposta
            // solo quanto basta quando la capsula espansa supera il bordo destro.
            newOrigin.x = current.minX
            newOrigin.y = current.maxY - targetSize.height

        case .vertical:
            // Grip in alto: resta fermo il bordo superiore, in dock come in undock.
            newOrigin.y = current.maxY - targetSize.height

            switch dockSide {
            case .right:
                newOrigin.x = screenRect.maxX - targetSize.width - screenInset
            case .left:
                newOrigin.x = screenRect.minX + screenInset
            case .center:
                newOrigin.x = current.midX - targetSize.width / 2
            }
        }

        newOrigin = clampedOrigin(newOrigin, size: targetSize, in: screenRect)
        return CGRect(origin: newOrigin, size: targetSize)
    }

    /// Isteresi del docking: si entra con la soglia bassa, si esce solo
    /// superando quella alta. Deterministica e simmetrica in dock e undock.
    public static func resolvedDock(
        previous: PillDockSide,
        leftDist: CGFloat,
        rightDist: CGFloat
    ) -> PillDockSide {
        let enter = dockThreshold
        let exit = dockExitThreshold

        switch previous {
        case .left:
            if leftDist <= exit { return .left }
            return rightDist <= enter ? .right : .center
        case .right:
            if rightDist <= exit { return .right }
            return leftDist <= enter ? .left : .center
        case .center:
            if leftDist <= enter { return .left }
            if rightDist <= enter { return .right }
            return .center
        }
    }

    /// Docking durante il drag: le distanze sono quelle del cursore, l'unico
    /// punto che riflette l'intenzione dell'utente. Il frame della finestra è
    /// ingannevole perché la capsula espansa viene clampata al bordo molto
    /// prima che il puntatore ci arrivi.
    public static func resolvedLiveDock(
        previous: PillDockSide,
        cursorX: CGFloat,
        screenRect: CGRect
    ) -> PillDockSide {
        resolvedDock(
            previous: previous,
            leftDist: cursorX - screenRect.minX,
            rightDist: screenRect.maxX - cursorX
        )
    }

    private static func clampedOrigin(_ origin: CGPoint, size: CGSize, in screenRect: CGRect) -> CGPoint {
        let minX = screenRect.minX + screenInset
        let maxX = screenRect.maxX - size.width - screenInset
        let minY = screenRect.minY + screenInset
        let maxY = screenRect.maxY - size.height - screenInset

        return CGPoint(
            x: max(minX, min(maxX, origin.x)),
            y: max(minY, min(maxY, origin.y))
        )
    }
}
