import XCTest
@testable import PenSculpt

final class GrowStrategyTests: XCTestCase {

    private func stroke(at points: [CGPoint], id: UUID = UUID()) -> Stroke {
        let sps = points.map {
            StrokePoint(location: $0, pressure: 1, tilt: 0, azimuth: 0, timestamp: 0)
        }
        return Stroke(id: id, points: sps)
    }

    private func canvas(_ strokes: [Stroke]) -> Canvas {
        var c = Canvas()
        c.strokes = strokes
        return c
    }

    // MARK: start

    func testStrokeOriginIncludesItselfAtT0() {
        let id = UUID()
        let seed = stroke(at: [CGPoint(x: 100, y: 100)], id: id)
        let other = stroke(at: [CGPoint(x: 500, y: 500)])
        let session = GrowStrategy.start(
            origin: .stroke(strokeID: id, anchor: CGPoint(x: 100, y: 100)),
            canvas: canvas([seed, other])
        )
        XCTAssertTrue(session.includedStrokeIDs.contains(id))
        XCTAssertFalse(session.includedStrokeIDs.contains(other.id))
    }

    func testPointOriginIncludesNothingAtT0WhenNoStrokeWithinInitialRadius() {
        let far = stroke(at: [CGPoint(x: 500, y: 500)])
        let session = GrowStrategy.start(
            origin: .point(.zero),
            canvas: canvas([far])
        )
        XCTAssertTrue(session.includedStrokeIDs.isEmpty)
    }

    func testPointOriginIncludesStrokeWithinInitialRadius() {
        // initialRadius = 8 → strokes within 8 of origin enter immediately.
        let close = stroke(at: [CGPoint(x: 5, y: 0)])
        let session = GrowStrategy.start(
            origin: .point(.zero),
            canvas: canvas([close])
        )
        XCTAssertTrue(session.includedStrokeIDs.contains(close.id))
    }

    // MARK: tick — monotonic radius

    func testRadiusGrowsMonotonically() {
        let s = stroke(at: [CGPoint(x: 1000, y: 1000)])
        let session = GrowStrategy.start(origin: .point(.zero), canvas: canvas([s]))
        var lastR = session.currentRadius
        for _ in 0..<10 {
            let frame = session.tick(deltaTime: 1.0 / 60.0)
            XCTAssertGreaterThanOrEqual(frame.radius, lastR)
            lastR = frame.radius
        }
    }

    // MARK: tick — admits strokes within radius

    func testTickIncludesCloseStrokeAfterEnoughTime() {
        // Stroke at distance 40; baseGrowthSpeed=50 px/s → reaches in ~0.64s.
        let target = stroke(at: [CGPoint(x: 40, y: 0)])
        let session = GrowStrategy.start(origin: .point(.zero), canvas: canvas([target]))
        let totalTime: TimeInterval = 1.0  // give it enough margin
        var t: TimeInterval = 0
        let dt = 1.0 / 60.0
        while t < totalTime {
            _ = session.tick(deltaTime: dt)
            t += dt
        }
        XCTAssertTrue(session.includedStrokeIDs.contains(target.id))
    }

    // MARK: pause behavior

    func testPauseTriggersWhenNextStrokeIsFar() {
        // Tight cluster near origin (immediate inclusion), then a big gap, then an isolated stroke.
        let cluster = (0..<3).map { i in
            stroke(at: [CGPoint(x: CGFloat(i) * 5, y: 0)])
        }
        let isolated = stroke(at: [CGPoint(x: 500, y: 0)])
        let session = GrowStrategy.start(
            origin: .point(.zero),
            canvas: canvas(cluster + [isolated])
        )
        // After cluster inclusion, density factor should drop below 1.0 within a few ticks.
        var sawPause = false
        for _ in 0..<10 {
            let frame = session.tick(deltaTime: 1.0 / 60.0)
            if frame.isPaused { sawPause = true; break }
        }
        XCTAssertTrue(sawPause, "Expected pause when the only remaining candidate is far away")
    }

    // MARK: finalize

    func testFinalizeReturnsCurrentlyIncludedSet() {
        let id = UUID()
        let seed = stroke(at: [CGPoint(x: 0, y: 0)], id: id)
        let session = GrowStrategy.start(
            origin: .stroke(strokeID: id, anchor: .zero),
            canvas: canvas([seed])
        )
        XCTAssertEqual(session.finalize(), [id])
    }

    func testFinalizeIsIdempotent() {
        let id = UUID()
        let seed = stroke(at: [CGPoint(x: 0, y: 0)], id: id)
        let session = GrowStrategy.start(
            origin: .stroke(strokeID: id, anchor: .zero),
            canvas: canvas([seed])
        )
        XCTAssertEqual(session.finalize(), session.finalize())
    }
}
