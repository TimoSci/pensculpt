import XCTest
import simd
@testable import PenSculpt

final class InferencePipelineTests: XCTestCase {

    private func makeStroke(points: [(CGFloat, CGFloat)]) -> Stroke {
        Stroke(points: points.enumerated().map { i, p in
            StrokePoint(location: CGPoint(x: p.0, y: p.1),
                        pressure: 1, tilt: 0, azimuth: 0,
                        timestamp: TimeInterval(i) * 0.1)
        })
    }

    func testInferProducesNonEmptyMesh() {
        // Draw a simple triangle shape
        let stroke = makeStroke(points: [
            (100, 0), (200, 0), (200, 100), (100, 100)
        ])
        let result = ShapeInflater.sculpt(from: [stroke])

        XCTAssertFalse(result.mesh.isEmpty, "Pipeline should produce a mesh")
        XCTAssertGreaterThan(result.mesh.vertexCount, 0)
        XCTAssertGreaterThan(result.mesh.faceCount, 0)
    }

    func testInferPreservesSourceStrokeIDs() {
        let s1 = makeStroke(points: [(0, 0), (100, 0), (100, 100), (0, 100)])
        let s2 = makeStroke(points: [(50, 50), (150, 50), (150, 150)])
        let result = ShapeInflater.sculpt(from: [s1, s2])

        XCTAssertTrue(result.sourceStrokeIDs.contains(s1.id))
        XCTAssertTrue(result.sourceStrokeIDs.contains(s2.id))
    }

    func testInferFromEmptyStrokesProducesEmptyMesh() {
        let result = ShapeInflater.sculpt(from: [])
        XCTAssertTrue(result.mesh.isEmpty)
    }

    func testMeshVerticesHaveValidNormals() {
        let stroke = makeStroke(points: [
            (0, 0), (100, 0), (100, 200), (0, 200)
        ])
        let result = ShapeInflater.sculpt(from: [stroke])

        for vertex in result.mesh.vertices {
            let len = simd_length(vertex.normal)
            XCTAssertEqual(len, 1.0, accuracy: 0.1,
                           "Normals should be approximately unit length")
        }
    }

    func testMeshFaceIndicesValid() {
        let stroke = makeStroke(points: [
            (50, 0), (100, 50), (50, 100), (0, 50)
        ])
        let result = ShapeInflater.sculpt(from: [stroke])
        let maxIdx = UInt32(result.mesh.vertexCount)

        for face in result.mesh.faces {
            XCTAssertLessThan(face.indices.x, maxIdx)
            XCTAssertLessThan(face.indices.y, maxIdx)
            XCTAssertLessThan(face.indices.z, maxIdx)
        }
    }
}
