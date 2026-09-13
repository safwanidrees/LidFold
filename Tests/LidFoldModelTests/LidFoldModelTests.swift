import XCTest
@testable import LidFoldModel

final class FoldGeometryTests: XCTestCase {

    func testQuadAtFreezeAngleIsTheScreen() {
        let g = FoldGeometry(screenWidth: 1512, screenHeight: 982, freezeAngle: 100)
        let c = g.project(at: 100)
        XCTAssertEqual(c[0].x, 0, accuracy: 1e-6); XCTAssertEqual(c[0].y, 0, accuracy: 1e-6)
        XCTAssertEqual(c[1].x, 1512, accuracy: 1e-6); XCTAssertEqual(c[1].y, 0, accuracy: 1e-6)
        XCTAssertEqual(c[2].x, 1512, accuracy: 1e-6); XCTAssertEqual(c[2].y, 982, accuracy: 1e-6)
        XCTAssertEqual(c[3].x, 0, accuracy: 1e-6); XCTAssertEqual(c[3].y, 982, accuracy: 1e-6)
    }

    func testHingeEdgeNeverMoves() {
        let g = FoldGeometry(screenWidth: 1512, screenHeight: 982, freezeAngle: 100)
        for angle in stride(from: 100.0, through: 20.0, by: -10) {
            let c = g.project(at: angle)
            XCTAssertEqual(c[0].y, 0, accuracy: 1e-6, "hinge at \(angle)")
            XCTAssertEqual(c[1].y, 0, accuracy: 1e-6, "hinge at \(angle)")
        }
    }

    func testPictureRecedesBehindTheGlass() {
        // The far edge climbs past the top of the glass and the sides converge.
        let g = FoldGeometry(screenWidth: 1512, screenHeight: 982, freezeAngle: 100)
        var lastWidth = Double.infinity
        for angle in stride(from: 100.0, through: 40.0, by: -10) {
            let c = g.project(at: angle)
            XCTAssertEqual(c[0].y, 0, accuracy: 1e-9); XCTAssertEqual(c[1].y, 0, accuracy: 1e-9)
            XCTAssertEqual(c[2].y, c[3].y, accuracy: 1e-9, "top edge stays level")
            XCTAssertEqual(c[3].x, 1512 - c[2].x, accuracy: 1e-6, "symmetric")
            let width = c[2].x - c[3].x
            XCTAssertLessThanOrEqual(width, lastWidth + 1e-6, "width at \(angle)")
            lastWidth = width
        }
        XCTAssertLessThan(lastWidth, 1512)
        XCTAssertGreaterThan(g.project(at: 40)[2].y, 982)
    }

    func testZeroDepthKeepsTheScreen() {
        let g = FoldGeometry(screenWidth: 1512, screenHeight: 982, freezeAngle: 100, depth: 0)
        let c = g.project(at: 50)
        XCTAssertEqual(c[2].y, 982, accuracy: 1e-6)
        XCTAssertEqual(c[3].x, 0, accuracy: 1e-6)
    }

    func testHomographyRoundTrips() {
        let g = FoldGeometry(screenWidth: 1512, screenHeight: 982, freezeAngle: 100)
        let quad = g.project(at: 60)
        let m = Homography.matrix(width: 1512, height: 982, to: quad)
        let mapped = Homography.apply(m, to: ScreenPoint(x: 1512, y: 982))
        XCTAssertEqual(mapped.x, quad[2].x, accuracy: 1e-6)
        XCTAssertEqual(mapped.y, quad[2].y, accuracy: 1e-6)
        let back = Homography.apply(m.inverse, to: quad[3])
        XCTAssertEqual(back.x, 0, accuracy: 1e-6)
        XCTAssertEqual(back.y, 982, accuracy: 1e-6)
    }
}

final class FoldCurveTests: XCTestCase {
    func testProgressBoundsAndMonotone() {
        let curve = FoldCurve(startAngle: 100, span: 60)
        XCTAssertEqual(curve.progress(at: 120), 0)
        XCTAssertEqual(curve.progress(at: 100), 0)
        XCTAssertEqual(curve.progress(at: 40), 1)
        XCTAssertEqual(curve.progress(at: 10), 1)
        var last = 0.0
        for angle in stride(from: 100.0, through: 40.0, by: -1) {
            let p = curve.progress(at: angle)
            XCTAssertGreaterThanOrEqual(p, last)
            last = p
        }
        XCTAssertEqual(curve.progress(at: 70), 0.5, accuracy: 1e-9)
    }
}

final class DampedSpringTests: XCTestCase {
    func testSettlesWithoutOvershoot() {
        var spring = DampedSpring(value: 100, frequency: 14)
        var minimum = 100.0
        for _ in 0..<600 {
            spring.advance(toward: 60, dt: 1.0 / 120)
            minimum = min(minimum, spring.value)
        }
        XCTAssertEqual(spring.value, 60, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(minimum, 59.99)
        XCTAssertTrue(spring.isSettled(at: 60))
    }
}

final class HingeAngleTrackerTests: XCTestCase {
    func testVelocityAndPrediction() {
        var tracker = HingeAngleTracker()
        tracker.reset(to: 120, at: 0)
        tracker.ingest(110, at: 0.1)
        tracker.ingest(100, at: 0.2)
        XCTAssertLessThan(tracker.velocity, -50)
        XCTAssertTrue(tracker.isClosing(at: 0.25, within: 1))
        XCTAssertLessThan(tracker.predictedAngle(at: 0.3), 100)
    }

    func testStillLidHasNoVelocity() {
        var tracker = HingeAngleTracker()
        tracker.reset(to: 120, at: 0)
        tracker.ingest(110, at: 0.1)
        tracker.ingest(110, at: 0.7)
        XCTAssertEqual(tracker.velocity, 0)
        XCTAssertEqual(tracker.predictedAngle(at: 0.8), 110)
    }
}

final class FoldDeciderTests: XCTestCase {
    func testRestingBelowStartDoesNotActivate() {
        var tracker = HingeAngleTracker()
        tracker.reset(to: 80, at: 0)
        var decider = FoldDecider(startAngle: 100)
        XCTAssertEqual(decider.update(tracker: tracker, enabled: true, time: 0.1), .idle)
    }

    func testClosingActivatesAndOpeningReleases() {
        var tracker = HingeAngleTracker()
        tracker.reset(to: 130, at: 0)
        var decider = FoldDecider(startAngle: 100)
        tracker.ingest(120, at: 0.1)
        XCTAssertEqual(decider.update(tracker: tracker, enabled: true, time: 0.1), .armed)
        tracker.ingest(105, at: 0.2)
        XCTAssertEqual(decider.update(tracker: tracker, enabled: true, time: 0.2), .armed)
        tracker.ingest(95, at: 0.3)
        XCTAssertEqual(decider.update(tracker: tracker, enabled: true, time: 0.3), .active)
        // Still active just above the start angle (release margin).
        tracker.ingest(102, at: 1.0)
        XCTAssertEqual(decider.update(tracker: tracker, enabled: true, time: 1.0), .active)
        tracker.ingest(106, at: 1.2)
        XCTAssertEqual(decider.update(tracker: tracker, enabled: true, time: 1.2), .idle)
    }

    func testDisabledIsAlwaysIdle() {
        var tracker = HingeAngleTracker()
        tracker.reset(to: 130, at: 0)
        var decider = FoldDecider(startAngle: 100)
        tracker.ingest(90, at: 0.1)
        XCTAssertEqual(decider.update(tracker: tracker, enabled: false, time: 0.1), .idle)
    }
}

final class SimulatedFoldSweepTests: XCTestCase {
    func testSweepEndsAndStaysInRange() {
        let sweep = SimulatedFoldSweep(startedAt: 10, openAngle: 120, closedAngle: 40)
        XCTAssertEqual(sweep.angle(at: 10), 120)
        XCTAssertEqual(sweep.angle(at: 10 + sweep.closingDuration)!, 40, accuracy: 1e-9)
        XCTAssertNil(sweep.angle(at: 10 + sweep.totalDuration + 0.01))
        for t in stride(from: 10.0, to: 10 + sweep.totalDuration, by: 0.05) {
            let a = sweep.angle(at: t)!
            XCTAssertGreaterThanOrEqual(a, 40 - 1e-9)
            XCTAssertLessThanOrEqual(a, 120 + 1e-9)
        }
    }
}
