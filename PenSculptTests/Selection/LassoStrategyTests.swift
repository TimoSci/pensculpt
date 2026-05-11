import XCTest
import PencilKit
@testable import PenSculpt

final class LassoStrategyTests: XCTestCase {

    func testPointInPolygon() {
        let square = [
            CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100), CGPoint(x: 0, y: 0)
        ]
        XCTAssertTrue(LassoStrategy.contains(CGPoint(x: 50, y: 50), in: square))
        XCTAssertFalse(LassoStrategy.contains(CGPoint(x: 150, y: 50), in: square))
        XCTAssertFalse(LassoStrategy.contains(CGPoint(x: 50, y: 150), in: square))
    }

    func testStrokeSelectedWhenAnyPointIsInside() {
        let points = (0..<10).map {
            StrokePoint(location: CGPoint(x: CGFloat($0) * 10, y: 50),
                        pressure: 1, tilt: 0, azimuth: 0, timestamp: 0)
        }
        let stroke = Stroke(points: points)

        // Polygon catches half the stroke — admitted.
        let halfPolygon = [
            CGPoint(x: -1, y: 0), CGPoint(x: 46, y: 0),
            CGPoint(x: 46, y: 100), CGPoint(x: -1, y: 100), CGPoint(x: -1, y: 0)
        ]
        XCTAssertTrue(LassoStrategy.isStrokeSelected(stroke, by: halfPolygon))

        // Polygon catches just the first point — still admitted (any-point rule).
        let slimPolygon = [
            CGPoint(x: -1, y: 0), CGPoint(x: 5, y: 0),
            CGPoint(x: 5, y: 100), CGPoint(x: -1, y: 100), CGPoint(x: -1, y: 0)
        ]
        XCTAssertTrue(LassoStrategy.isStrokeSelected(stroke, by: slimPolygon))

        // Polygon entirely off the stroke — not admitted.
        let missPolygon = [
            CGPoint(x: 200, y: 0), CGPoint(x: 300, y: 0),
            CGPoint(x: 300, y: 100), CGPoint(x: 200, y: 100), CGPoint(x: 200, y: 0)
        ]
        XCTAssertFalse(LassoStrategy.isStrokeSelected(stroke, by: missPolygon))
    }

    func testPKStrokeLocationsPreservedAfterConversion() {
        let inputLocation = CGPoint(x: 500, y: 700)
        let pkPoint = PKStrokePoint(location: inputLocation, timeOffset: 0,
                                     size: CGSize(width: 5, height: 5), opacity: 1,
                                     force: 1, azimuth: 0, altitude: .pi / 4)
        let path = PKStrokePath(controlPoints: [pkPoint], creationDate: Date())
        let pkStroke = PKStroke(ink: PKInk(.pen, color: .black), path: path)
        let stroke = StrokeConverter.convert(pkStroke)

        XCTAssertEqual(stroke.points[0].location.x, 500, accuracy: 1)
        XCTAssertEqual(stroke.points[0].location.y, 700, accuracy: 1)
    }

    func testLassoSelectsStrokeAtSameCoordinates() {
        let points = [
            StrokePoint(location: CGPoint(x: 500, y: 700), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0),
            StrokePoint(location: CGPoint(x: 510, y: 710), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.1)
        ]
        let stroke = Stroke(points: points)

        let polygon = [
            CGPoint(x: 450, y: 650), CGPoint(x: 550, y: 650),
            CGPoint(x: 550, y: 750), CGPoint(x: 450, y: 750), CGPoint(x: 450, y: 650)
        ]
        XCTAssertTrue(LassoStrategy.isStrokeSelected(stroke, by: polygon))
    }
}
