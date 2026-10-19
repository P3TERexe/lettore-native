import XCTest
import CoreGraphics
@testable import LettoreCore
@testable import LettoreUI

/// Verifica la geometria pura della pillola: dimensioni, ancoraggio e docking.
/// Sono i punti in cui il frame della finestra e il contenuto SwiftUI devono
/// restare d'accordo, altrimenti la capsula "scappa" dal cursore o si taglia.
final class PillGeometryTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1470, height: 923)

    private func resolved(
        _ current: CGRect,
        _ orientation: PillOrientation,
        expanded: Bool = true,
        fallback: Bool = false
    ) -> CGRect {
        FloatingPillPanelManager.resolvedFrame(
            current: current,
            screenRect: screen,
            orientation: orientation,
            isExpanded: expanded,
            isFallback: fallback
        )
    }

    // MARK: - Metriche

    func testContentAlwaysFitsInsidePanel() {
        for orientation in [PillOrientation.horizontal, .vertical] {
            for expanded in [false, true] {
                for fallback in [false, true] {
                    let panel = FloatingPillPanelManager.PillMetrics.panelSize(
                        orientation: orientation,
                        isExpanded: expanded,
                        isFallback: fallback
                    )
                    let content = FloatingPillPanelManager.PillMetrics.contentSize(
                        orientation: orientation,
                        isExpanded: expanded,
                        isFallback: fallback
                    )

                    XCTAssertLessThan(content.width, panel.width, "\(orientation) espansa=\(expanded) fallback=\(fallback)")
                    XCTAssertLessThan(content.height, panel.height, "\(orientation) espansa=\(expanded) fallback=\(fallback)")
                }
            }
        }
    }

    func testFallbackPanelIsWiderThanNormalPanel() {
        let normal = FloatingPillPanelManager.PillMetrics.panelSize(
            orientation: .horizontal, isExpanded: true, isFallback: false
        )
        let fallback = FloatingPillPanelManager.PillMetrics.panelSize(
            orientation: .horizontal, isExpanded: true, isFallback: true
        )
        XCTAssertGreaterThan(fallback.width, normal.width)
    }

    // MARK: - Ancoraggio del grip

    func testVerticalToHorizontalKeepsTopEdge() {
        let vertical = CGRect(x: 700, y: 400, width: 48, height: 170)
        let result = resolved(vertical, .horizontal, expanded: true)

        XCTAssertEqual(result.maxY, vertical.maxY, accuracy: 0.5, "Il bordo superiore non deve saltare")
        XCTAssertEqual(result.width, FloatingPillPanelManager.PillMetrics.horizontalExpanded.width)
        XCTAssertEqual(result.height, FloatingPillPanelManager.PillMetrics.horizontalExpanded.height)
    }

    func testHorizontalToVerticalKeepsTopEdge() {
        let horizontal = CGRect(x: 700, y: 400, width: 282, height: 42)
        let result = resolved(horizontal, .vertical, expanded: true)

        XCTAssertEqual(result.maxY, horizontal.maxY, accuracy: 0.5, "Il bordo superiore non deve saltare")
    }

    func testHorizontalExpansionKeepsLeadingEdgeWhenThereIsRoom() {
        let compact = CGRect(x: 400, y: 400, width: 104, height: 42)
        let result = resolved(compact, .horizontal, expanded: true)

        XCTAssertEqual(result.minX, compact.minX, accuracy: 0.5, "Il grip a sinistra deve restare fermo")
    }

    func testHorizontalExpansionClampsAtRightEdge() {
        let compact = CGRect(x: screen.maxX - 104 - 10, y: 400, width: 104, height: 42)
        let result = resolved(compact, .horizontal, expanded: true)

        XCTAssertLessThanOrEqual(
            result.maxX,
            screen.maxX - FloatingPillPanelManager.PillMetrics.screenInset,
            "La capsula espansa non deve uscire dallo schermo"
        )
    }

    func testVerticalDockSnapsToRightInset() {
        let frame = CGRect(x: screen.maxX - 48 - 20, y: 400, width: 48, height: 104)
        let result = resolved(frame, .vertical, expanded: false)

        let expectedX = screen.maxX - 48 - FloatingPillPanelManager.PillMetrics.screenInset
        XCTAssertEqual(result.minX, expectedX, accuracy: 0.5)
    }

    func testVerticalDockSnapsToLeftInset() {
        let frame = CGRect(x: screen.minX + 20, y: 400, width: 48, height: 104)
        let result = resolved(frame, .vertical, expanded: false)

        let expectedX = screen.minX + FloatingPillPanelManager.PillMetrics.screenInset
        XCTAssertEqual(result.minX, expectedX, accuracy: 0.5)
    }

    func testFrameAlwaysStaysInsideScreen() {
        let cases: [CGRect] = [
            CGRect(x: screen.minX - 500, y: screen.minY - 500, width: 282, height: 42),
            CGRect(x: screen.maxX + 500, y: screen.maxY + 500, width: 282, height: 42),
            CGRect(x: screen.midX, y: screen.midY, width: 48, height: 192)
        ]

        for frame in cases {
            for orientation in [PillOrientation.horizontal, .vertical] {
                let result = resolved(frame, orientation, expanded: true)
                let inset = FloatingPillPanelManager.PillMetrics.screenInset

                XCTAssertGreaterThanOrEqual(result.minX, screen.minX + inset - 0.5)
                XCTAssertLessThanOrEqual(result.maxX, screen.maxX - inset + 0.5)
                XCTAssertGreaterThanOrEqual(result.minY, screen.minY + inset - 0.5)
                XCTAssertLessThanOrEqual(result.maxY, screen.maxY - inset + 0.5)
            }
        }
    }

    // MARK: - Soglia di docking

    func testDockThresholdIsSmallEnoughToAvoidTeleport() {
        // Lo snap massimo coincide con la soglia: deve restare un magnete, non
        // un teletrasporto verso il bordo.
        XCTAssertLessThanOrEqual(FloatingPillPanelManager.PillMetrics.dockThreshold, 60)
    }
}
