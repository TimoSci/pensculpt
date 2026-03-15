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

    // MARK: - Curvature enforcement

    func testCurvatureSmooths() {
        // Sharp jump in radius: 0, 0, 100, 100 → should be smoothed
        let skeleton = makeSkeleton(radii: [0.5, 0.5, 100, 100, 100])
        let config = SculptConfig(minCurvatureRadius: 30)
        let closed = SurfaceCloser.close(skeleton, config: config)

        // The curvature enforcement should prevent the sharp 0→100 jump
        let radii = closed.points.map(\.radius)
        for i in 1..<radii.count {
            let delta = radii[i] - radii[i - 1]
            // No massive jumps
            XCTAssertLessThan(delta, 60, "Radius change should be bounded: \(radii[i-1]) → \(radii[i])")
        }
    }

    func testHighCurvatureRadiusProducesSmoother() {
        let skeleton = makeSkeleton(radii: [10, 80, 10, 80, 10])
        let smooth = SurfaceCloser.close(skeleton, config: SculptConfig(minCurvatureRadius: 50))
        let sharp = SurfaceCloser.close(skeleton, config: SculptConfig(minCurvatureRadius: 5))

        // Higher curvature radius should produce smaller max radius delta
        let smoothDeltas = zip(smooth.points.dropFirst(), smooth.points).map { abs($0.radius - $1.radius) }
        let sharpDeltas = zip(sharp.points.dropFirst(), sharp.points).map { abs($0.radius - $1.radius) }
        let smoothMaxDelta = smoothDeltas.max() ?? 0
        let sharpMaxDelta = sharpDeltas.max() ?? 0
        XCTAssertLessThan(smoothMaxDelta, sharpMaxDelta + 1,
                           "Higher curvature radius should be smoother")
    }

    // MARK: - Config

    func testDefaultConfig() {
        let config = SculptConfig.default
        XCTAssertEqual(config.minCurvatureRadius, 40)
    }

    func testConfigCodable() throws {
        let config = SculptConfig(minCurvatureRadius: 42)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SculptConfig.self, from: data)
        XCTAssertEqual(decoded.minCurvatureRadius, 42)
    }
}
