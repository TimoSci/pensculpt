import XCTest
@testable import PenSculpt

final class SurfaceCloserTests: XCTestCase {

    private func makeSkeleton(radii: [CGFloat], spacing: CGFloat = 10) -> Skeleton {
        let points = radii.enumerated().map { i, r in
            SkeletonPoint(position: CGPoint(x: 0, y: CGFloat(i) * spacing), radius: r)
        }
        return Skeleton(points: points, axis: CGVector(dx: 0, dy: 1))
    }

    // MARK: - Closed surfaces

    func testBothEndsTaperTowardZero() {
        // A long cylinder should get caps at both ends
        let skeleton = makeSkeleton(radii: Array(repeating: CGFloat(50), count: 20), spacing: 20)
        let closed = SurfaceCloser.close(skeleton)

        // Endpoints should be smaller than the body radius
        let maxR = closed.points.map(\.radius).max() ?? 0
        XCTAssertLessThan(closed.points.first!.radius, maxR * 0.5)
        XCTAssertLessThan(closed.points.last!.radius, maxR * 0.5)
    }

    func testClosedSurfaceHasMorePoints() {
        let skeleton = makeSkeleton(radii: [50, 50, 50])
        let closed = SurfaceCloser.close(skeleton)
        XCTAssertGreaterThan(closed.points.count, skeleton.points.count,
                              "Closing should add taper points")
    }

    func testAlreadyClosedUnchanged() {
        // Already near-zero at both ends
        let skeleton = makeSkeleton(radii: [0.5, 50, 100, 50, 0.5])
        let closed = SurfaceCloser.close(skeleton)
        // Should not add many extra points since ends are already closed
        XCTAssertLessThan(closed.points.count, skeleton.points.count + 4)
    }

    // MARK: - Config

    func testDefaultConfig() {
        let config = SculptConfig.default
        XCTAssertEqual(config.minCurvatureRadius, 25)
    }

    func testConfigCodable() throws {
        let config = SculptConfig(minCurvatureRadius: 42)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SculptConfig.self, from: data)
        XCTAssertEqual(decoded.minCurvatureRadius, 42)
    }
}
