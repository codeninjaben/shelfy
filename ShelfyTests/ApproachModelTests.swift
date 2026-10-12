import XCTest
@testable import Shelfy

/// Replays pointer paths through the approach model. The tab sits on the right edge
/// (x = 1470) spanning y 400–464; coordinates are AppKit screen points.
final class ApproachModelTests: XCTestCase {
    private let rightTab = ApproachModel.Target(edge: .right, edgeX: 1470, tabMinY: 400, tabMaxY: 464)

    private func model(_ target: ApproachModel.Target? = nil,
                       _ sensitivity: HoverSensitivity = .medium) -> ApproachModel {
        var model = ApproachModel(tuning: sensitivity.approachTuning)
        model.target = target ?? rightTab
        return model
    }

    /// Moves the pointer along a straight line at ~120 Hz and records the approach state.
    @discardableResult
    private func move(_ model: inout ApproachModel, from start: CGPoint, to end: CGPoint,
                      seconds: TimeInterval, startingAt time: TimeInterval = 1000) -> [Bool] {
        let steps = max(Int(seconds * 120), 2)
        return (0...steps).map { step in
            let t = Double(step) / Double(steps)
            let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            model.update(location: point, time: time + seconds * t)
            return model.isApproaching
        }
    }

    func testHeadingStraightForTheTabSticksItOutBeforeArrival() {
        var model = model()
        let states = move(&model, from: CGPoint(x: 1240, y: 432), to: CGPoint(x: 1462, y: 432), seconds: 0.35)
        let firstApproach = states.firstIndex(of: true)
        XCTAssertNotNil(firstApproach)
        XCTAssertLessThan(firstApproach ?? .max, states.count - 12, "should stick out at least 0.1 s before arrival")
        XCTAssertTrue(states.last ?? false)
    }

    func testDiagonalApproachInsideTheTriangle() {
        var model = model()
        move(&model, from: CGPoint(x: 1230, y: 650), to: CGPoint(x: 1464, y: 445), seconds: 0.4)
        XCTAssertTrue(model.isApproaching)
    }

    func testAimingAtTheEdgeFarFromTheTabDoesNotCount() {
        var model = model()
        move(&model, from: CGPoint(x: 1250, y: 700), to: CGPoint(x: 1469, y: 760), seconds: 0.35)
        XCTAssertFalse(model.isApproaching, "heading for the edge 300 pt above the tab")
        var below = self.model()
        move(&below, from: CGPoint(x: 1300, y: 250), to: CGPoint(x: 1469, y: 150), seconds: 0.3)
        XCTAssertFalse(below.isApproaching, "heading down and away from the tab")
    }

    func testSlidingAlongTheEdgeDoesNotCount() {
        var model = model()
        move(&model, from: CGPoint(x: 1440, y: 180), to: CGPoint(x: 1440, y: 700), seconds: 0.5)
        XCTAssertFalse(model.isApproaching)
    }

    func testSlowDriftDoesNotCount() {
        var model = model()
        move(&model, from: CGPoint(x: 1300, y: 432), to: CGPoint(x: 1340, y: 432), seconds: 1.0)
        XCTAssertFalse(model.isApproaching, "40 pt/s isn't a deliberate reach")
    }

    func testMovementFarFromTheEdgeIsIgnored() {
        var model = model()
        move(&model, from: CGPoint(x: 300, y: 432), to: CGPoint(x: 1000, y: 432), seconds: 0.4)
        XCTAssertFalse(model.isApproaching)
    }

    func testTurningBackRetractsTheTab() {
        var model = model()
        move(&model, from: CGPoint(x: 1260, y: 432), to: CGPoint(x: 1400, y: 432), seconds: 0.25)
        XCTAssertTrue(model.isApproaching)
        move(&model, from: CGPoint(x: 1400, y: 432), to: CGPoint(x: 1300, y: 432), seconds: 0.2, startingAt: 1000.3)
        XCTAssertFalse(model.isApproaching)
    }

    func testLeavingTheZoneRetractsTheTab() {
        var model = model()
        move(&model, from: CGPoint(x: 1260, y: 432), to: CGPoint(x: 1400, y: 432), seconds: 0.25)
        XCTAssertTrue(model.isApproaching)
        move(&model, from: CGPoint(x: 1400, y: 432), to: CGPoint(x: 1400, y: 900), seconds: 0.3, startingAt: 1000.3)
        XCTAssertFalse(model.isApproaching)
    }

    func testLeftEdgeMirrors() {
        let leftTab = ApproachModel.Target(edge: .left, edgeX: 0, tabMinY: 400, tabMaxY: 464)
        var model = model(leftTab)
        move(&model, from: CGPoint(x: 220, y: 432), to: CGPoint(x: 8, y: 432), seconds: 0.35)
        XCTAssertTrue(model.isApproaching)
        var away = self.model(leftTab)
        move(&away, from: CGPoint(x: 220, y: 432), to: CGPoint(x: 8, y: 432), seconds: 0.35)
        move(&away, from: CGPoint(x: 8, y: 432), to: CGPoint(x: 200, y: 432), seconds: 0.2, startingAt: 1000.4)
        XCTAssertFalse(away.isApproaching)
    }

    func testHigherSensitivityReachesFurther() {
        var low = model(nil, .low)
        var high = model(nil, .high)
        let start = CGPoint(x: 1180, y: 432) // 290 pt from the edge
        let end = CGPoint(x: 1280, y: 432)   // 190 pt from the edge
        move(&low, from: start, to: end, seconds: 0.1)
        move(&high, from: start, to: end, seconds: 0.1)
        XCTAssertFalse(low.isApproaching)
        XCTAssertTrue(high.isApproaching)
    }

    // MARK: Realistic reaches (minimum-jerk motion: speed up, then brake toward the target)

    @discardableResult
    private func reach(_ model: inout ApproachModel, from start: CGPoint, toward end: CGPoint,
                       seconds: TimeInterval, clampX: CGFloat? = nil) -> [Bool] {
        let steps = Int(seconds * 120)
        return (0...steps).map { step in
            let tau = Double(step) / Double(steps)
            let s = 10 * pow(tau, 3) - 15 * pow(tau, 4) + 6 * pow(tau, 5)
            var x = start.x + (end.x - start.x) * s
            if let clampX { x = min(x, clampX) } // the screen edge stops the pointer
            let point = CGPoint(x: x, y: start.y + (end.y - start.y) * s)
            model.update(location: point, time: 1000 + seconds * tau)
            return model.isApproaching
        }
    }

    func testBrakingToStopShortOfTheEdgeDoesNotCount() {
        var model = model()
        // A quick move to something 130 pt from the edge, level with the tab (a sidebar item, say).
        let states = reach(&model, from: CGPoint(x: 1000, y: 432), toward: CGPoint(x: 1340, y: 432), seconds: 0.38)
        XCTAssertFalse(states.contains(true), "braking short of the edge isn't a reach for the tab")
    }

    func testFlickingAtTheEdgeCountsBeforeArrival() {
        var model = model()
        // Aimed past the edge, as people do with screen edges; the edge stops the pointer.
        let states = reach(&model, from: CGPoint(x: 1150, y: 470), toward: CGPoint(x: 1520, y: 440),
                           seconds: 0.32, clampX: 1469)
        let firstApproach = states.firstIndex(of: true)
        XCTAssertNotNil(firstApproach)
        let arrival = states.indices.first { step in
            let tau = Double(step) / Double(states.count - 1)
            return 1150 + 370 * (10 * pow(tau, 3) - 15 * pow(tau, 4) + 6 * pow(tau, 5)) >= 1469
        } ?? states.count
        XCTAssertLessThan(firstApproach ?? .max, arrival, "should stick out before the pointer reaches the edge")
    }
}

final class ApproachTrackerHealthTests: XCTestCase {
    func testSilentMonitorWhileThePointerMovesIsStalled() {
        XCTAssertTrue(ApproachTracker.monitorLooksStalled(now: 1000, lastEvent: 900, systemMouseIdle: 2))
    }

    func testIdlePointerIsNotAStall() {
        XCTAssertFalse(ApproachTracker.monitorLooksStalled(now: 1000, lastEvent: 900, systemMouseIdle: 120),
                       "nobody moved the pointer, so silence is expected")
    }

    func testRecentEventsAreHealthy() {
        XCTAssertFalse(ApproachTracker.monitorLooksStalled(now: 1000, lastEvent: 990, systemMouseIdle: 1))
    }
}
