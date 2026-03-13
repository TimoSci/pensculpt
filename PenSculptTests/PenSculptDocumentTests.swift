import XCTest
@testable import PenSculpt

final class PenSculptDocumentTests: XCTestCase {

    func testNewDocumentHasEmptyCanvas() {
        let doc = PenSculptDocument()
        XCTAssertTrue(doc.canvas.strokes.isEmpty)
    }

    func testSnapshotRoundTrip() throws {
        let doc = PenSculptDocument()
        doc.canvas.addStroke(Stroke(points: [
            StrokePoint(location: CGPoint(x: 1, y: 2), pressure: 0.5, tilt: 0, azimuth: 0, timestamp: 0)
        ]))

        let data = try JSONEncoder().encode(doc.canvas)
        let decoded = try JSONDecoder().decode(Canvas.self, from: data)
        XCTAssertEqual(decoded.strokes.count, 1)
        XCTAssertEqual(decoded.strokes.first?.points.first?.location, CGPoint(x: 1, y: 2))
    }
}
