import XCTest
@testable import PenSculpt

final class SkeletonExtractorTests: XCTestCase {

    // MARK: - Edge cases

    func testEmptyContour() {
        let skeleton = SkeletonExtractor.extract(fromPoints: [])
        XCTAssertTrue(skeleton.isEmpty)
    }

    func testTooFewPoints() {
        let skeleton = SkeletonExtractor.extract(fromPoints: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)])
        XCTAssertTrue(skeleton.isEmpty)
    }

    // MARK: - Principal axis

    func testPrincipalAxisHorizontal() {
        // Points spread horizontally — axis should be roughly (1, 0)
        let points = [
            CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 10), CGPoint(x: 0, y: 10)
        ]
        let centroid = SkeletonExtractor.centroid(of: points)
        let axis = SkeletonExtractor.principalAxis(of: points, centroid: centroid)
        XCTAssertGreaterThan(abs(axis.dx), abs(axis.dy),
                              "Horizontal spread should produce a horizontal axis")
    }

    func testPrincipalAxisVertical() {
        // Points spread vertically — axis should be roughly (0, 1)
        let points = [
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 100), CGPoint(x: 0, y: 100)
        ]
        let centroid = SkeletonExtractor.centroid(of: points)
        let axis = SkeletonExtractor.principalAxis(of: points, centroid: centroid)
        XCTAssertGreaterThan(abs(axis.dy), abs(axis.dx),
                              "Vertical spread should produce a vertical axis")
    }

    func testAxisIsUnitLength() {
        let points = [
            CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 30),
            CGPoint(x: 100, y: 0), CGPoint(x: 50, y: -30)
        ]
        let centroid = SkeletonExtractor.centroid(of: points)
        let axis = SkeletonExtractor.principalAxis(of: points, centroid: centroid)
        let length = hypot(axis.dx, axis.dy)
        XCTAssertEqual(length, 1.0, accuracy: 0.001)
    }

    // MARK: - Skeleton extraction

    func testSkeletonFromRectangle() {
        // Wide rectangle — skeleton should run horizontally through the center
        let contour = [
            CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0),
            CGPoint(x: 200, y: 50), CGPoint(x: 0, y: 50)
        ]
        let skeleton = SkeletonExtractor.extract(fromPoints: contour, sampleCount: 5)

        XCTAssertFalse(skeleton.isEmpty)
        // Skeleton points should be near y=25 (center of 0..50)
        for point in skeleton.points {
            XCTAssertEqual(point.position.y, 25, accuracy: 15,
                           "Skeleton should run through the vertical center")
        }
        // Radius should be roughly half the height (~25)
        for point in skeleton.points {
            XCTAssertGreaterThan(point.radius, 5)
        }
    }

    func testSkeletonRadiiDecrease() {
        // Diamond shape — widest in the middle, tapers at ends
        let contour = [
            CGPoint(x: 50, y: 0),   // top
            CGPoint(x: 100, y: 50), // right
            CGPoint(x: 50, y: 100), // bottom
            CGPoint(x: 0, y: 50)    // left
        ]
        let skeleton = SkeletonExtractor.extract(fromPoints: contour, sampleCount: 10)
        XCTAssertFalse(skeleton.isEmpty)

        // The middle sample should have the largest radius
        if skeleton.points.count >= 3 {
            let midIdx = skeleton.points.count / 2
            let midRadius = skeleton.points[midIdx].radius
            let firstRadius = skeleton.points[0].radius
            let lastRadius = skeleton.points[skeleton.points.count - 1].radius
            XCTAssertGreaterThanOrEqual(midRadius, firstRadius - 5)
            XCTAssertGreaterThanOrEqual(midRadius, lastRadius - 5)
        }
    }

    // MARK: - Centroid

    func testCentroid() {
        let points = [
            CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)
        ]
        let c = SkeletonExtractor.centroid(of: points)
        XCTAssertEqual(c.x, 50, accuracy: 0.01)
        XCTAssertEqual(c.y, 50, accuracy: 0.01)
    }

    func testCentroidEmpty() {
        let c = SkeletonExtractor.centroid(of: [])
        XCTAssertEqual(c, .zero)
    }
}

final class SegmenterTests: XCTestCase {

    private func makePoint(_ x: CGFloat, _ y: CGFloat, radius: CGFloat = 10) -> SkeletonPoint {
        SkeletonPoint(position: CGPoint(x: x, y: y), radius: radius)
    }

    func testEmptySkeleton() {
        let skeleton = Skeleton(points: [], axis: .zero)
        let segments = Segmenter.segment(skeleton)
        XCTAssertTrue(segments.isEmpty)
    }

    func testSinglePointSkeleton() {
        let skeleton = Skeleton(points: [makePoint(0, 0)], axis: CGVector(dx: 1, dy: 0))
        let segments = Segmenter.segment(skeleton)
        XCTAssertEqual(segments.count, 1)
    }

    func testStraightSkeletonProducesOneSegment() {
        // Straight line — no curvature — one segment
        let points = (0..<10).map { makePoint(CGFloat($0) * 10, 0) }
        let skeleton = Skeleton(points: points, axis: CGVector(dx: 1, dy: 0))
        let segments = Segmenter.segment(skeleton)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].points.count, 10)
    }

    func testSharpBendSplitsIntoTwoSegments() {
        // L-shaped: horizontal then vertical — sharp 90° bend
        let points = [
            makePoint(0, 0), makePoint(10, 0), makePoint(20, 0),
            makePoint(20, 10), makePoint(20, 20)
        ]
        let skeleton = Skeleton(points: points, axis: CGVector(dx: 1, dy: 0))
        let segments = Segmenter.segment(skeleton, curvatureThreshold: 0.3)
        XCTAssertGreaterThanOrEqual(segments.count, 2,
                                     "A 90° bend should split into at least 2 segments")
    }

    func testCurvatureCalculation() {
        // Straight line: curvature should be 0
        let straight = Segmenter.curvature(
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 20, y: 0))
        XCTAssertEqual(straight, 0, accuracy: 0.01)

        // 90° turn: curvature should be ≈ π/2
        let rightAngle = Segmenter.curvature(
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10))
        XCTAssertEqual(rightAngle, .pi / 2, accuracy: 0.01)
    }

    func testAllPointsPreserved() {
        // All skeleton points should appear in exactly one segment
        let points = [
            makePoint(0, 0), makePoint(10, 0), makePoint(20, 0),
            makePoint(20, 10), makePoint(20, 20)
        ]
        let skeleton = Skeleton(points: points, axis: CGVector(dx: 1, dy: 0))
        let segments = Segmenter.segment(skeleton, curvatureThreshold: 0.3)

        // Split points appear in both segments, so total ≥ original count
        let totalPoints = segments.reduce(0) { $0 + $1.points.count }
        XCTAssertGreaterThanOrEqual(totalPoints, points.count)
    }
}
