import XCTest
import UniformTypeIdentifiers
@testable import PenSculpt

final class PenSculptDocumentTests: XCTestCase {

    func testNewDocumentHasEmptyCanvas() {
        let doc = PenSculptDocument()
        XCTAssertTrue(doc.canvas.strokes.isEmpty)
    }

    func testSnapshotContainsValidData() throws {
        let doc = PenSculptDocument()
        doc.canvas.addStroke(Stroke(points: [
            StrokePoint(location: CGPoint(x: 1, y: 2), pressure: 0.5, tilt: 0, azimuth: 0, timestamp: 0)
        ]))

        let snapshot = try doc.snapshot(contentType: .pensculpt)

        let strokes = try JSONDecoder().decode([Stroke].self, from: snapshot.strokes)
        XCTAssertEqual(strokes.count, 1)
        XCTAssertEqual(strokes.first?.points.first?.location, CGPoint(x: 1, y: 2))

        let meta = try JSONDecoder().decode(DocumentMetadata.self, from: snapshot.metadata)
        XCTAssertEqual(meta.canvasWidth, 1024)
        XCTAssertEqual(meta.canvasHeight, 1366)
    }

    func testSnapshotRoundTrip() throws {
        let doc = PenSculptDocument()
        doc.canvas.addStroke(Stroke(points: [
            StrokePoint(location: CGPoint(x: 5, y: 10), pressure: 0.8, tilt: 0.1, azimuth: 0.2, timestamp: 1)
        ]))

        let snapshot = try doc.snapshot(contentType: .pensculpt)

        // Verify strokes survive encode/decode
        let strokes = try JSONDecoder().decode([Stroke].self, from: snapshot.strokes)
        XCTAssertEqual(strokes.first?.points.first?.pressure, 0.8)
        XCTAssertEqual(strokes.first?.color, .black)
    }
}
