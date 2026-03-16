import XCTest
import simd
@testable import PenSculpt

final class SculptRendererTests: XCTestCase {

    func testOrthographicProjectionMapsCorners() {
        let mvp = SculptRenderer.orthographicProjection(
            left: -100, right: 100,
            bottom: -100, top: 100,
            near: -100, far: 100
        )

        // Origin maps to clip-space origin
        let origin = mvp * SIMD4<Float>(0, 0, 0, 1)
        XCTAssertEqual(origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(origin.y, 0, accuracy: 0.001)

        // Left-bottom-near corner maps to (-1, -1, -1)
        let lbn = mvp * SIMD4<Float>(-100, -100, -100, 1)
        XCTAssertEqual(lbn.x, -1, accuracy: 0.001)
        XCTAssertEqual(lbn.y, -1, accuracy: 0.001)

        // Right-top-far corner maps to (1, 1, 1)
        let rtf = mvp * SIMD4<Float>(100, 100, 100, 1)
        XCTAssertEqual(rtf.x, 1, accuracy: 0.001)
        XCTAssertEqual(rtf.y, 1, accuracy: 0.001)
    }

    func testOrthographicProjectionPreservesAspect() {
        let wide = SculptRenderer.orthographicProjection(
            left: -200, right: 200,
            bottom: -100, top: 100,
            near: -1, far: 1
        )

        // A point at (100, 50) should map to (0.5, 0.5) — same relative position
        let p = wide * SIMD4<Float>(100, 50, 0, 1)
        XCTAssertEqual(p.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(p.y, 0.5, accuracy: 0.001)
    }

    func testOrthographicProjectionIsConsistent() {
        let mvp1 = SculptRenderer.orthographicProjection(
            left: -50, right: 50, bottom: -50, top: 50, near: -10, far: 10
        )
        let mvp2 = SculptRenderer.orthographicProjection(
            left: -50, right: 50, bottom: -50, top: 50, near: -10, far: 10
        )

        let testPoint = SIMD4<Float>(25, 25, 5, 1)
        let p1 = mvp1 * testPoint
        let p2 = mvp2 * testPoint
        XCTAssertEqual(p1.x, p2.x, accuracy: 0.001)
        XCTAssertEqual(p1.y, p2.y, accuracy: 0.001)
        XCTAssertEqual(p1.z, p2.z, accuracy: 0.001)
    }
}
