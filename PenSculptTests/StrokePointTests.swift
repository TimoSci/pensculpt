import XCTest
@testable import PenSculpt

final class StrokePointTests: XCTestCase {

    func testInitialization() {
        let point = StrokePoint(
            location: CGPoint(x: 100, y: 200),
            pressure: 0.5,
            tilt: 0.3,
            azimuth: 1.2,
            timestamp: 1000.0
        )
        XCTAssertEqual(point.location, CGPoint(x: 100, y: 200))
        XCTAssertEqual(point.pressure, 0.5)
        XCTAssertEqual(point.tilt, 0.3)
        XCTAssertEqual(point.azimuth, 1.2)
        XCTAssertEqual(point.timestamp, 1000.0)
    }

    func testCodable() throws {
        let point = StrokePoint(
            location: CGPoint(x: 50, y: 75),
            pressure: 0.8,
            tilt: 0.1,
            azimuth: 0.5,
            timestamp: 500.0
        )
        let data = try JSONEncoder().encode(point)
        let decoded = try JSONDecoder().decode(StrokePoint.self, from: data)
        XCTAssertEqual(decoded.location, point.location)
        XCTAssertEqual(decoded.pressure, point.pressure)
        XCTAssertEqual(decoded.tilt, point.tilt)
        XCTAssertEqual(decoded.azimuth, point.azimuth)
        XCTAssertEqual(decoded.timestamp, point.timestamp)
    }

    func testEquatable() {
        let a = StrokePoint(location: .zero, pressure: 1, tilt: 0, azimuth: 0, timestamp: 0)
        let b = StrokePoint(location: .zero, pressure: 1, tilt: 0, azimuth: 0, timestamp: 0)
        let c = StrokePoint(location: CGPoint(x: 1, y: 0), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
