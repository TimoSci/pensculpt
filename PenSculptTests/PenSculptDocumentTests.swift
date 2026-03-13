import XCTest
import UniformTypeIdentifiers
@testable import PenSculpt

final class PenSculptDocumentTests: XCTestCase {

    func testNewDocumentHasEmptyCanvas() {
        let doc = PenSculptDocument()
        XCTAssertTrue(doc.canvas.strokes.isEmpty)
    }

    func testSnapshotProducesPackageStructure() throws {
        let doc = PenSculptDocument()
        doc.canvas.addStroke(Stroke(points: [
            StrokePoint(location: CGPoint(x: 1, y: 2), pressure: 0.5, tilt: 0, azimuth: 0, timestamp: 0)
        ]))

        let snapshot = try doc.snapshot(contentType: .pensculpt)
        let wrapper = try doc.fileWrapper(
            snapshot: snapshot,
            configuration: .init(existingFile: nil, contentType: .pensculpt)
        )

        XCTAssertTrue(wrapper.isDirectory)
        XCTAssertNotNil(wrapper.fileWrappers?["strokes.json"])
        XCTAssertNotNil(wrapper.fileWrappers?["metadata.json"])
        XCTAssertNotNil(wrapper.fileWrappers?["sculpt_objects"])
    }

    func testRoundTrip() throws {
        let doc = PenSculptDocument()
        doc.canvas.addStroke(Stroke(points: [
            StrokePoint(location: CGPoint(x: 1, y: 2), pressure: 0.5, tilt: 0, azimuth: 0, timestamp: 0)
        ]))

        let snapshot = try doc.snapshot(contentType: .pensculpt)
        let wrapper = try doc.fileWrapper(
            snapshot: snapshot,
            configuration: .init(existingFile: nil, contentType: .pensculpt)
        )

        let config = ReferenceFileDocumentConfiguration(
            file: wrapper,
            contentType: .pensculpt
        )
        let loaded = try PenSculptDocument(configuration: config)
        XCTAssertEqual(loaded.canvas.strokes.count, 1)
        XCTAssertEqual(loaded.canvas.strokes.first?.points.first?.location, CGPoint(x: 1, y: 2))
    }
}
