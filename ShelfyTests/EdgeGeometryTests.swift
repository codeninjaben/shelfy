import XCTest
@testable import Shelfy

final class EdgeGeometryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
    /// Menu bar at the top (33pt) and a bottom Dock (70pt).
    private let visible = CGRect(x: 0, y: 70, width: 1470, height: 853)
    private let basket = CGSize(width: 244, height: 286)

    private func geometry(edge: ScreenEdge = .right, position: Double = 0.5,
                          screenFrame: CGRect? = nil, visibleFrame: CGRect? = nil,
                          basketSize: CGSize? = nil) -> EdgeGeometry {
        EdgeGeometry(.init(screenFrame: screenFrame ?? screen, visibleFrame: visibleFrame ?? visible,
                           edge: edge, position: position, tabSize: CGSize(width: 9, height: 64),
                           activationDepth: 22, basketSize: basketSize ?? basket))
    }

    func testRightEdgeTabIsFlushWithTheScreenEdge() {
        let layout = geometry()
        XCTAssertEqual(layout.tabRect.maxX, screen.maxX)
        XCTAssertEqual(layout.collapsedFrame.maxX, screen.maxX)
        XCTAssertEqual(layout.collapsedFrame.width, 22)
        XCTAssertEqual(layout.basketRect.maxX, screen.maxX - EdgeGeometry.basketInset)
    }

    func testLeftEdgeMirrorsTheLayout() {
        let layout = geometry(edge: .left)
        XCTAssertEqual(layout.tabRect.minX, screen.minX)
        XCTAssertEqual(layout.collapsedFrame.minX, screen.minX)
        XCTAssertEqual(layout.basketRect.minX, screen.minX + EdgeGeometry.basketInset)
        XCTAssertEqual(layout.expandedFrame.minX, screen.minX)
    }

    func testExpandedPanelNeverCrossesTheEdge() {
        for edge in ScreenEdge.allCases {
            let layout = geometry(edge: edge)
            XCTAssertTrue(screen.contains(layout.expandedFrame), "\(edge) panel spills off screen")
            XCTAssertGreaterThanOrEqual(layout.expandedFrame.minY, visible.minY, "panel covers the Dock")
            XCTAssertLessThanOrEqual(layout.expandedFrame.maxY, visible.maxY, "panel covers the menu bar")
            XCTAssertTrue(layout.expandedFrame.contains(layout.basketRect))
            XCTAssertTrue(layout.expandedFrame.contains(layout.collapsedFrame))
            XCTAssertTrue(layout.expandedFrame.contains(layout.hoverRegion))
        }
    }

    func testThePathFromTabToBasketStaysInsideTheHoverRegion() {
        let layout = geometry()
        // Walk from the tab's center straight into the basket: every point should keep it open.
        let start = CGPoint(x: layout.tabRect.midX, y: layout.tabCenterY)
        let end = CGPoint(x: layout.basketRect.midX, y: layout.basketRect.midY)
        for step in 0...20 {
            let t = CGFloat(step) / 20
            let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            XCTAssertTrue(layout.hoverRegion.contains(point), "gap in hover region at \(point)")
        }
    }

    func testTabStaysClearOfCornersAndBasketStaysInsideTheVisibleFrame() {
        for position in [0.0, 0.5, 1.0] {
            let layout = geometry(position: position)
            XCTAssertGreaterThanOrEqual(layout.tabRect.minY, visible.minY + EdgeGeometry.cornerClearance - 0.5)
            XCTAssertLessThanOrEqual(layout.tabRect.maxY, visible.maxY - EdgeGeometry.cornerClearance + 0.5)
            XCTAssertTrue(visible.insetBy(dx: 0, dy: EdgeGeometry.screenMargin - 0.5).contains(layout.basketRect),
                          "basket leaves the usable area at position \(position)")
        }
    }

    func testVisibleDockOnTheSameEdgeIsAvoided() {
        let dockRight = CGRect(x: 0, y: 0, width: 1400, height: 923)
        let layout = geometry(visibleFrame: dockRight)
        XCTAssertEqual(layout.tabRect.maxX, 1400)
        XCTAssertLessThanOrEqual(layout.expandedFrame.maxX, 1400)
    }

    func testAutoHiddenDockSliverIsIgnored() {
        let hiddenDock = CGRect(x: 0, y: 0, width: 1466, height: 923)
        XCTAssertEqual(geometry(visibleFrame: hiddenDock).tabRect.maxX, screen.maxX)
    }

    func testSecondaryDisplayWithNegativeOrigin() {
        let external = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let externalVisible = CGRect(x: -1920, y: -200, width: 1920, height: 1055)
        let layout = geometry(edge: .left, screenFrame: external, visibleFrame: externalVisible)
        XCTAssertEqual(layout.tabRect.minX, -1920)
        XCTAssertTrue(external.contains(layout.expandedFrame))
    }

    func testBasketNearTheTopDoesNotReachIntoTheMenuBar() {
        let layout = geometry(position: 0, basketSize: CGSize(width: 284, height: 520))
        XCTAssertLessThanOrEqual(layout.expandedFrame.maxY, visible.maxY)
        XCTAssertTrue(layout.expandedFrame.contains(layout.basketRect))
    }

    func testTallBasketIsClampedToTheVisibleFrame() {
        let layout = geometry(position: 1, basketSize: CGSize(width: 284, height: 700))
        XCTAssertGreaterThanOrEqual(layout.basketRect.minY, visible.minY + EdgeGeometry.screenMargin - 0.5)
        XCTAssertLessThanOrEqual(layout.basketRect.maxY, visible.maxY - EdgeGeometry.screenMargin + 0.5)
    }

    func testHiddenTabSensorIsAThinStripAroundTheTab() {
        for edge in ScreenEdge.allCases {
            let layout = geometry(edge: edge)
            XCTAssertEqual(layout.sensorFrame.width, EdgeGeometry.sensorDepth)
            XCTAssertEqual(edge == .right ? layout.sensorFrame.maxX : layout.sensorFrame.minX,
                           edge == .right ? screen.maxX : screen.minX, "sensor must touch the edge")
            XCTAssertLessThanOrEqual(layout.sensorFrame.minY, layout.tabRect.minY - EdgeGeometry.revealSlack + 0.5)
            XCTAssertGreaterThanOrEqual(layout.sensorFrame.maxY, layout.tabRect.maxY + EdgeGeometry.revealSlack - 0.5)
            XCTAssertTrue(layout.revealedFrame.contains(layout.sensorFrame))
            XCTAssertTrue(layout.revealedFrame.contains(layout.collapsedFrame))
            XCTAssertTrue(layout.expandedFrame.contains(layout.collapsedFrame))
        }
    }

    func testSensorStaysOffTheCornersAndBars() {
        for position in [0.0, 1.0] {
            let layout = geometry(position: position)
            XCTAssertGreaterThanOrEqual(layout.sensorFrame.minY, visible.minY + EdgeGeometry.screenMargin - 0.5)
            XCTAssertLessThanOrEqual(layout.sensorFrame.maxY, visible.maxY - EdgeGeometry.screenMargin + 0.5)
        }
    }

    func testPositionRoundTrips() {
        for position in [0.0, 0.25, 0.5, 0.9, 1.0] {
            let layout = geometry(position: position)
            let recovered = EdgeGeometry.position(forTabCenterY: layout.tabCenterY, visibleFrame: visible, tabHeight: 64)
            XCTAssertEqual(recovered, position, accuracy: 0.0001)
        }
    }
}
