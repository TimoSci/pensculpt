import XCTest
import simd
@testable import PenSculpt

/// Step-by-step diagnostic for the inference pipeline.
final class PipelineDiagnosticTests: XCTestCase {

    private var sampleStrokes: [Stroke] {
        let leftProfile = Stroke(points: [
            StrokePoint(location: CGPoint(x: 200, y: 100), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0),
            StrokePoint(location: CGPoint(x: 180, y: 200), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.1),
            StrokePoint(location: CGPoint(x: 170, y: 300), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.2),
            StrokePoint(location: CGPoint(x: 180, y: 400), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.3),
            StrokePoint(location: CGPoint(x: 200, y: 500), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.4),
        ])
        let rightProfile = Stroke(points: [
            StrokePoint(location: CGPoint(x: 400, y: 100), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0),
            StrokePoint(location: CGPoint(x: 420, y: 200), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.1),
            StrokePoint(location: CGPoint(x: 430, y: 300), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.2),
            StrokePoint(location: CGPoint(x: 420, y: 400), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.3),
            StrokePoint(location: CGPoint(x: 400, y: 500), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.4),
        ])
        return [leftProfile, rightProfile]
    }

    // MARK: - Contour extraction

    func testContourExtraction() {
        let contour = ContourExtractor.extract(from: sampleStrokes)
        print("📐 Contour: \(contour.count) points")
        XCTAssertGreaterThan(contour.count, 2, "Contour should have at least 3 points")
    }

    // MARK: - Full pipeline

    func testFullPipeline() {
        let result = ShapeInflater.sculpt(from: sampleStrokes)
        print("🏗️ Final mesh: \(result.mesh.vertexCount) vertices, \(result.mesh.faceCount) faces")
        print("🏗️ Source strokes: \(result.sourceStrokeIDs.count)")

        if !result.mesh.isEmpty {
            let positions = result.mesh.vertices.map { $0.position }
            let xs = positions.map(\.x), ys = positions.map(\.y), zs = positions.map(\.z)
            print("   X range: \(xs.min()!) – \(xs.max()!)")
            print("   Y range: \(ys.min()!) – \(ys.max()!)")
            print("   Z range: \(zs.min()!) – \(zs.max()!)")

            let maxIdx = UInt32(result.mesh.vertexCount)
            for face in result.mesh.faces {
                XCTAssertLessThan(face.indices.x, maxIdx, "Face index out of range")
                XCTAssertLessThan(face.indices.y, maxIdx, "Face index out of range")
                XCTAssertLessThan(face.indices.z, maxIdx, "Face index out of range")
            }
        }

        XCTAssertFalse(result.mesh.isEmpty, "Pipeline should produce a non-empty mesh")
    }
}
