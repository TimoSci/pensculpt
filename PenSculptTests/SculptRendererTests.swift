import XCTest
import simd
@testable import PenSculpt

final class SculptRendererTests: XCTestCase {

    private let viewSize = CGSize(width: 1024, height: 1366)

    private func makeStroke(from: CGPoint, to: CGPoint) -> Stroke {
        Stroke(points: [
            StrokePoint(location: from, pressure: 1, tilt: 0, azimuth: 0, timestamp: 0),
            StrokePoint(location: to, pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.1)
        ])
    }

    /// Applies the MVP matrix to a 2D point, returns the clip-space position.
    private func project(_ point: CGPoint, mvp: simd_float4x4) -> SIMD4<Float> {
        let p = SIMD4<Float>(Float(point.x), Float(point.y), 0, 1)
        return mvp * p
    }

    // MARK: - Tests

    func testSmallStrokesNotEnlarged() {
        // A small stroke spanning 100x10 points
        let stroke = makeStroke(from: CGPoint(x: 500, y: 500), to: CGPoint(x: 600, y: 510))
        let mvp = SculptRenderer.fittedProjection(strokes: [stroke], viewSize: viewSize)

        // Project the stroke endpoints to clip space
        let p1 = project(CGPoint(x: 500, y: 500), mvp: mvp)
        let p2 = project(CGPoint(x: 600, y: 510), mvp: mvp)

        // In clip space, the range is [-1, 1] = 2 units = viewSize points
        // At 1:1 scale, 100pt horizontal distance = 100/1024 * 2 = 0.195 clip units
        let expectedClipWidth = 2.0 * 100.0 / Float(viewSize.width)
        let actualClipWidth = abs(p2.x - p1.x)

        // The actual width should be approximately the expected width (1:1, not enlarged)
        XCTAssertEqual(actualClipWidth, expectedClipWidth, accuracy: 0.05,
                       "Small stroke should render at 1:1 scale, not enlarged. " +
                       "Expected clip width ≈\(expectedClipWidth), got \(actualClipWidth)")
    }

    func testLargeStrokesShrunkToFit() {
        // A stroke spanning the full viewport width
        let stroke = makeStroke(from: CGPoint(x: 0, y: 500), to: CGPoint(x: 2000, y: 500))
        let mvp = SculptRenderer.fittedProjection(strokes: [stroke], viewSize: viewSize)

        let p1 = project(CGPoint(x: 0, y: 500), mvp: mvp)
        let p2 = project(CGPoint(x: 2000, y: 500), mvp: mvp)

        // The stroke is wider than the viewport — it should be shrunk to fit
        // Both endpoints should be within clip space [-1, 1]
        XCTAssertGreaterThan(p1.x, -1.1, "Left endpoint should be within clip space")
        XCTAssertLessThan(p2.x, 1.1, "Right endpoint should be within clip space")
    }

    func testStrokesCenteredInViewport() {
        // A stroke at an off-center position
        let stroke = makeStroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 200))
        let mvp = SculptRenderer.fittedProjection(strokes: [stroke], viewSize: viewSize)

        // The center of the stroke (150, 150) should map near clip-space origin (0, 0)
        let center = project(CGPoint(x: 150, y: 150), mvp: mvp)
        XCTAssertEqual(center.x, 0, accuracy: 0.1,
                       "Stroke center X should map to clip-space center")
        XCTAssertEqual(center.y, 0, accuracy: 0.1,
                       "Stroke center Y should map to clip-space center")
    }

    func testEmptyStrokesProduces1to1Projection() {
        let mvp = SculptRenderer.fittedProjection(strokes: [], viewSize: viewSize)

        // With no strokes, origin should map to top-left of clip space
        let origin = project(.zero, mvp: mvp)
        XCTAssertEqual(origin.x, -1, accuracy: 0.01)
        XCTAssertEqual(origin.y, 1, accuracy: 0.01, "Y=0 should map to top (1 in clip space)")

        // Bottom-right corner should map to (1, -1)
        let corner = project(CGPoint(x: viewSize.width, y: viewSize.height), mvp: mvp)
        XCTAssertEqual(corner.x, 1, accuracy: 0.01)
        XCTAssertEqual(corner.y, -1, accuracy: 0.01)
    }

    func testMultipleStrokesBoundingBox() {
        let s1 = makeStroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 200))
        let s2 = makeStroke(from: CGPoint(x: 800, y: 800), to: CGPoint(x: 900, y: 900))
        let mvp = SculptRenderer.fittedProjection(strokes: [s1, s2], viewSize: viewSize)

        // Combined center is (500, 500) — should map near origin
        let center = project(CGPoint(x: 500, y: 500), mvp: mvp)
        XCTAssertEqual(center.x, 0, accuracy: 0.1)
        XCTAssertEqual(center.y, 0, accuracy: 0.1)

        // Both stroke endpoints should be visible (within clip space)
        let topLeft = project(CGPoint(x: 100, y: 100), mvp: mvp)
        let bottomRight = project(CGPoint(x: 900, y: 900), mvp: mvp)
        XCTAssertGreaterThan(topLeft.x, -1.1)
        XCTAssertLessThan(bottomRight.x, 1.1)
    }
}
