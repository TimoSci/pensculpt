import XCTest
@testable import PenSculpt

final class CanvasTests: XCTestCase {

    func testInitEmpty() {
        let canvas = Canvas()
        XCTAssertTrue(canvas.strokes.isEmpty)
        XCTAssertEqual(canvas.size, CGSize(width: 1024, height: 1366))
    }

    func testAddStroke() {
        var canvas = Canvas()
        let stroke = Stroke(points: [
            StrokePoint(location: .zero, pressure: 1, tilt: 0, azimuth: 0, timestamp: 0)
        ])
        canvas.addStroke(stroke)
        XCTAssertEqual(canvas.strokes.count, 1)
        XCTAssertEqual(canvas.strokes.first?.id, stroke.id)
    }

    func testRemoveStroke() {
        var canvas = Canvas()
        let stroke = Stroke(points: [
            StrokePoint(location: .zero, pressure: 1, tilt: 0, azimuth: 0, timestamp: 0)
        ])
        canvas.addStroke(stroke)
        canvas.removeStroke(id: stroke.id)
        XCTAssertTrue(canvas.strokes.isEmpty)
    }

    func testClearStrokes() {
        var canvas = Canvas()
        canvas.addStroke(Stroke(points: []))
        canvas.addStroke(Stroke(points: []))
        canvas.clearStrokes()
        XCTAssertTrue(canvas.strokes.isEmpty)
    }

    func testCodable() throws {
        var canvas = Canvas()
        canvas.addStroke(Stroke(points: [
            StrokePoint(location: CGPoint(x: 5, y: 5), pressure: 0.5, tilt: 0, azimuth: 0, timestamp: 1)
        ]))
        let data = try JSONEncoder().encode(canvas)
        let decoded = try JSONDecoder().decode(Canvas.self, from: data)
        XCTAssertEqual(decoded.strokes.count, 1)
        XCTAssertEqual(decoded.size, canvas.size)
    }
}
