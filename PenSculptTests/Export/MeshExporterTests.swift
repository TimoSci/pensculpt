import XCTest
import simd
@testable import PenSculpt

final class MeshExporterTests: XCTestCase {

    private func makeCube() -> SculptObject {
        let positions: [SIMD3<Float>] = [
            [-1, -1, -1], [ 1, -1, -1], [ 1,  1, -1], [-1,  1, -1],
            [-1, -1,  1], [ 1, -1,  1], [ 1,  1,  1], [-1,  1,  1],
        ]
        let vertices = positions.map { MeshVertex(position: $0, normal: normalize($0)) }
        let faces: [MeshFace] = [
            MeshFace(indices: [0, 1, 2]), MeshFace(indices: [0, 2, 3]),
            MeshFace(indices: [4, 6, 5]), MeshFace(indices: [4, 7, 6]),
            MeshFace(indices: [0, 4, 5]), MeshFace(indices: [0, 5, 1]),
            MeshFace(indices: [3, 2, 6]), MeshFace(indices: [3, 6, 7]),
            MeshFace(indices: [0, 3, 7]), MeshFace(indices: [0, 7, 4]),
            MeshFace(indices: [1, 5, 6]), MeshFace(indices: [1, 6, 2]),
        ]
        let mesh = Mesh(vertices: vertices, faces: faces)
        return SculptObject(mesh: mesh, sourceStrokeIDs: [])
    }

    func testExportOBJContainsExpectedVertexAndFaceCounts() throws {
        let cube = makeCube()
        let url = try MeshExporter.export([cube], format: .obj)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.pathExtension, "obj")

        let text = try String(contentsOf: url, encoding: .utf8)
        let vLines = text.split(separator: "\n").filter { $0.hasPrefix("v ") }
        let fLines = text.split(separator: "\n").filter { $0.hasPrefix("f ") }
        XCTAssertEqual(vLines.count, 8)
        XCTAssertEqual(fLines.count, 12)
    }

    func testExportEmptyArrayThrowsEmptyContent() {
        XCTAssertThrowsError(try MeshExporter.export([], format: .obj)) { error in
            guard case ExportError.emptyContent = error else {
                XCTFail("Expected .emptyContent, got \(error)")
                return
            }
        }
    }
}
