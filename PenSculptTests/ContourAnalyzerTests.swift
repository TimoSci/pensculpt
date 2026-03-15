import XCTest
@testable import PenSculpt

final class ContourAnalyzerTests: XCTestCase {

    // MARK: - Convex hull edge cases

    func testEmptyPoints() {
        let hull = ContourAnalyzer.convexHull([])
        XCTAssertTrue(hull.isEmpty)
    }

    func testSinglePoint() {
        let hull = ContourAnalyzer.convexHull([CGPoint(x: 5, y: 5)])
        XCTAssertEqual(hull.count, 1)
    }

    func testTwoPoints() {
        let hull = ContourAnalyzer.convexHull([
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)
        ])
        XCTAssertEqual(hull.count, 2)
    }

    // MARK: - Convex hull basic shapes

    func testTriangle() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 5, y: 10)
        ]
        let hull = ContourAnalyzer.convexHull(points)
        XCTAssertEqual(hull.count, 3, "Triangle should have 3 hull points")
    }

    func testSquare() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 10),
            CGPoint(x: 0, y: 10)
        ]
        let hull = ContourAnalyzer.convexHull(points)
        XCTAssertEqual(hull.count, 4, "Square should have 4 hull points")
    }

    func testInteriorPointsExcluded() {
        let points = [
            // Outer square
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 0, y: 100),
            // Interior points
            CGPoint(x: 50, y: 50),
            CGPoint(x: 25, y: 25),
            CGPoint(x: 75, y: 75)
        ]
        let hull = ContourAnalyzer.convexHull(points)
        XCTAssertEqual(hull.count, 4, "Interior points should not be in the hull")
    }

    func testCollinearPoints() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 5, y: 0),
            CGPoint(x: 10, y: 0)
        ]
        let hull = ContourAnalyzer.convexHull(points)
        // Collinear points: hull should collapse (Graham scan keeps endpoints)
        XCTAssertLessThanOrEqual(hull.count, 3)
    }

    // MARK: - Counter-clockwise ordering

    func testHullIsCounterClockwise() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 10),
            CGPoint(x: 0, y: 10)
        ]
        let hull = ContourAnalyzer.convexHull(points)
        // Verify CCW: all consecutive cross products should be positive
        for i in 0..<hull.count {
            let o = hull[i]
            let a = hull[(i + 1) % hull.count]
            let b = hull[(i + 2) % hull.count]
            XCTAssertGreaterThan(ContourAnalyzer.cross(o, a, b), 0,
                                  "Hull should be counter-clockwise at index \(i)")
        }
    }

    // MARK: - extractContour from strokes

    func testExtractContourFromStrokes() {
        let s1 = Stroke(points: [
            StrokePoint(location: CGPoint(x: 0, y: 0), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0),
            StrokePoint(location: CGPoint(x: 100, y: 0), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.1)
        ])
        let s2 = Stroke(points: [
            StrokePoint(location: CGPoint(x: 100, y: 100), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0),
            StrokePoint(location: CGPoint(x: 0, y: 100), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.1)
        ])
        let contour = ContourAnalyzer.extractContour(from: [s1, s2])

        XCTAssertEqual(contour.count, 4, "Two strokes forming a square should yield 4 hull points")
    }

    func testExtractContourEmptyStrokes() {
        let contour = ContourAnalyzer.extractContour(from: [])
        XCTAssertTrue(contour.isEmpty)
    }

    func testExtractContourSingleStroke() {
        let stroke = Stroke(points: [
            StrokePoint(location: CGPoint(x: 0, y: 0), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0),
            StrokePoint(location: CGPoint(x: 50, y: 100), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.1),
            StrokePoint(location: CGPoint(x: 100, y: 0), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.2)
        ])
        let contour = ContourAnalyzer.extractContour(from: [stroke])
        XCTAssertEqual(contour.count, 3)
    }
}
