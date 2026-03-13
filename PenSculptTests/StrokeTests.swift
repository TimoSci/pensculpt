import XCTest
@testable import PenSculpt

final class StrokeTests: XCTestCase {

    func testInitWithDefaults() {
        let stroke = Stroke(points: [])
        XCTAssertEqual(stroke.color, .black)
        XCTAssertTrue(stroke.points.isEmpty)
        XCTAssertFalse(stroke.id.uuidString.isEmpty)
    }

    func testInitWithPoints() {
        let points = [
            StrokePoint(location: .zero, pressure: 1.0, tilt: 0, azimuth: 0, timestamp: 0),
            StrokePoint(location: CGPoint(x: 10, y: 10), pressure: 0.5, tilt: 0, azimuth: 0, timestamp: 0.1)
        ]
        let stroke = Stroke(points: points)
        XCTAssertEqual(stroke.points.count, 2)
    }

    func testBoundingBox() {
        let points = [
            StrokePoint(location: CGPoint(x: 10, y: 20), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0),
            StrokePoint(location: CGPoint(x: 50, y: 80), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0)
        ]
        let stroke = Stroke(points: points)
        let bounds = stroke.boundingBox
        XCTAssertEqual(bounds.origin.x, 10)
        XCTAssertEqual(bounds.origin.y, 20)
        XCTAssertEqual(bounds.width, 40)
        XCTAssertEqual(bounds.height, 60)
    }

    func testBoundingBoxEmpty() {
        let stroke = Stroke(points: [])
        XCTAssertEqual(stroke.boundingBox, .zero)
    }

    func testCodable() throws {
        let stroke = Stroke(points: [
            StrokePoint(location: .zero, pressure: 1, tilt: 0, azimuth: 0, timestamp: 0)
        ])
        let data = try JSONEncoder().encode(stroke)
        let decoded = try JSONDecoder().decode(Stroke.self, from: data)
        XCTAssertEqual(decoded.id, stroke.id)
        XCTAssertEqual(decoded.points.count, 1)
        XCTAssertEqual(decoded.color, .black)
    }
}
