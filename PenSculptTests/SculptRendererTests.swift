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

    private func project(_ point: CGPoint, mvp: simd_float4x4) -> SIMD4<Float> {
        mvp * SIMD4<Float>(Float(point.x), Float(point.y), 0, 1)
    }

    func testEmptyStrokesProduces1to1Projection() {
        let mvp = SculptRenderer.fittedProjection(strokes: [], viewSize: viewSize)

        let origin = project(.zero, mvp: mvp)
        XCTAssertEqual(origin.x, -1, accuracy: 0.01)
        XCTAssertEqual(origin.y, 1, accuracy: 0.01)

        let corner = project(CGPoint(x: viewSize.width, y: viewSize.height), mvp: mvp)
        XCTAssertEqual(corner.x, 1, accuracy: 0.01)
        XCTAssertEqual(corner.y, -1, accuracy: 0.01)
    }

    func test1to1ProjectionPreservesPosition() {
        // With the 1:1 projection, strokes appear at their original canvas position
        let stroke = makeStroke(from: CGPoint(x: 500, y: 500), to: CGPoint(x: 600, y: 510))
        let mvp = SculptRenderer.fittedProjection(strokes: [stroke], viewSize: viewSize)

        // A point at the center of the viewport should map to clip-space (0, 0)
        let center = project(CGPoint(x: 512, y: 683), mvp: mvp)
        XCTAssertEqual(center.x, 0, accuracy: 0.01)
        XCTAssertEqual(center.y, 0, accuracy: 0.01)

        // The stroke position should map to the same relative position as on the canvas
        let p = project(CGPoint(x: 500, y: 500), mvp: mvp)
        let expectedX = (500.0 / 1024.0) * 2.0 - 1.0  // ≈ -0.024
        let expectedY = -((500.0 / 1366.0) * 2.0 - 1.0) // ≈ 0.268
        XCTAssertEqual(p.x, Float(expectedX), accuracy: 0.01)
        XCTAssertEqual(p.y, Float(expectedY), accuracy: 0.01)
    }

    func testProjectionIsConsistentRegardlessOfStrokeContent() {
        // 1:1 projection should be the same regardless of what strokes are passed
        let small = makeStroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 20, y: 20))
        let large = makeStroke(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 2000, y: 2000))

        let mvpSmall = SculptRenderer.fittedProjection(strokes: [small], viewSize: viewSize)
        let mvpLarge = SculptRenderer.fittedProjection(strokes: [large], viewSize: viewSize)

        // Both should produce the same projection (1:1 viewport mapping)
        let testPoint = CGPoint(x: 500, y: 500)
        let pSmall = project(testPoint, mvp: mvpSmall)
        let pLarge = project(testPoint, mvp: mvpLarge)
        XCTAssertEqual(pSmall.x, pLarge.x, accuracy: 0.001)
        XCTAssertEqual(pSmall.y, pLarge.y, accuracy: 0.001)
    }
}
