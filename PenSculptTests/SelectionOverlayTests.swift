import XCTest
@testable import PenSculpt

final class SelectionOverlayTests: XCTestCase {

    // Lasso flow (ported from LassoViewTests)

    func testLassoBeginAndEndProducesPolygon() {
        let v = SelectionView()
        var captured: [CGPoint]?
        v.onLassoCompleted = { captured = $0 }

        v.beginStroke(displayPoint: CGPoint(x: 0, y: 0), targetPoint: CGPoint(x: 0, y: 0))
        v.continueStroke(displayPoint: CGPoint(x: 10, y: 0), targetPoint: CGPoint(x: 10, y: 0))
        v.continueStroke(displayPoint: CGPoint(x: 10, y: 10), targetPoint: CGPoint(x: 10, y: 10))
        v.endStroke()

        XCTAssertNotNil(captured)
        XCTAssertEqual(captured?.first, captured?.last, "polygon should be closed")
    }

    func testLassoTooShortDoesNotFireCallback() {
        let v = SelectionView()
        var fired = false
        v.onLassoCompleted = { _ in fired = true }
        v.beginStroke(displayPoint: .zero, targetPoint: .zero)
        v.endStroke()
        XCTAssertFalse(fired)
    }

    // Grow flow (new)

    func testGrowGestureFiresWithPointOriginWhenNoStrokeAtTap() {
        let v = SelectionView()
        var captured: GrowOrigin?
        v.onGrowGestureStarted = { captured = $0 }

        v.beginGrow(at: CGPoint(x: 50, y: 50), strokes: [])
        XCTAssertEqual(captured, .point(CGPoint(x: 50, y: 50)))
    }

    func testGrowGestureFiresWithStrokeOriginWhenTapHitsStroke() {
        let v = SelectionView()
        var captured: GrowOrigin?
        v.onGrowGestureStarted = { captured = $0 }

        let id = UUID()
        let s = Stroke(id: id, points: [
            StrokePoint(location: CGPoint(x: 50, y: 50), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0)
        ])
        v.beginGrow(at: CGPoint(x: 51, y: 51), strokes: [s])
        // 51,51 is within the default hit-tolerance (8pt) of (50,50)
        XCTAssertEqual(captured, .stroke(strokeID: id, anchor: CGPoint(x: 51, y: 51)))
    }

    func testGrowEndFiresEndCallback() {
        let v = SelectionView()
        var ended = false
        v.onGrowGestureEnded = { ended = true }
        v.beginGrow(at: .zero, strokes: [])
        v.endGrow()
        XCTAssertTrue(ended)
    }
}
