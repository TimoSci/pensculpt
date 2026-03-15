import XCTest
import simd
@testable import PenSculpt

final class MeshTests: XCTestCase {

    func testEmptyMesh() {
        let mesh = Mesh()
        XCTAssertTrue(mesh.isEmpty)
        XCTAssertEqual(mesh.vertexCount, 0)
        XCTAssertEqual(mesh.faceCount, 0)
    }

    func testMeshWithData() {
        let vertices = [
            MeshVertex(position: SIMD3(0, 0, 0), normal: SIMD3(0, 0, 1)),
            MeshVertex(position: SIMD3(1, 0, 0), normal: SIMD3(0, 0, 1)),
            MeshVertex(position: SIMD3(0, 1, 0), normal: SIMD3(0, 0, 1))
        ]
        let faces = [MeshFace(indices: SIMD3(0, 1, 2))]
        let mesh = Mesh(vertices: vertices, faces: faces)

        XCTAssertFalse(mesh.isEmpty)
        XCTAssertEqual(mesh.vertexCount, 3)
        XCTAssertEqual(mesh.faceCount, 1)
    }

    func testMeshCodable() throws {
        let vertices = [
            MeshVertex(position: SIMD3(1, 2, 3), normal: SIMD3(0, 1, 0)),
            MeshVertex(position: SIMD3(4, 5, 6), normal: SIMD3(0, 1, 0))
        ]
        let faces = [MeshFace(indices: SIMD3(0, 1, 0))]
        let mesh = Mesh(vertices: vertices, faces: faces)

        let data = try JSONEncoder().encode(mesh)
        let decoded = try JSONDecoder().decode(Mesh.self, from: data)

        XCTAssertEqual(decoded.vertexCount, 2)
        XCTAssertEqual(decoded.faceCount, 1)
        XCTAssertEqual(decoded.vertices[0].position, SIMD3(1, 2, 3))
        XCTAssertEqual(decoded.vertices[1].normal, SIMD3(0, 1, 0))
        XCTAssertEqual(decoded.faces[0].indices, SIMD3<UInt32>(0, 1, 0))
    }

    func testMeshEquatable() {
        let v = MeshVertex(position: SIMD3(0, 0, 0), normal: SIMD3(0, 0, 1))
        let f = MeshFace(indices: SIMD3(0, 0, 0))
        let a = Mesh(vertices: [v], faces: [f])
        let b = Mesh(vertices: [v], faces: [f])
        XCTAssertEqual(a, b)
    }

    func testMeshIsEmptyWithVerticesButNoFaces() {
        let v = MeshVertex(position: SIMD3(0, 0, 0), normal: SIMD3(0, 0, 1))
        let mesh = Mesh(vertices: [v], faces: [])
        XCTAssertTrue(mesh.isEmpty)
    }
}

final class SculptObjectTests: XCTestCase {

    func testSculptObjectInit() {
        let mesh = Mesh(
            vertices: [MeshVertex(position: SIMD3(0, 0, 0), normal: SIMD3(0, 0, 1))],
            faces: [MeshFace(indices: SIMD3(0, 0, 0))]
        )
        let strokeID = UUID()
        let obj = SculptObject(mesh: mesh, sourceStrokeIDs: [strokeID])

        XCTAssertFalse(obj.id.uuidString.isEmpty)
        XCTAssertEqual(obj.mesh.vertexCount, 1)
        XCTAssertTrue(obj.sourceStrokeIDs.contains(strokeID))
    }

    func testSculptObjectCodable() throws {
        let mesh = Mesh(
            vertices: [
                MeshVertex(position: SIMD3(1, 2, 3), normal: SIMD3(0, 1, 0)),
                MeshVertex(position: SIMD3(4, 5, 6), normal: SIMD3(0, 1, 0)),
                MeshVertex(position: SIMD3(7, 8, 9), normal: SIMD3(0, 1, 0))
            ],
            faces: [MeshFace(indices: SIMD3(0, 1, 2))]
        )
        let strokeID = UUID()
        let obj = SculptObject(mesh: mesh, sourceStrokeIDs: [strokeID])

        let data = try JSONEncoder().encode(obj)
        let decoded = try JSONDecoder().decode(SculptObject.self, from: data)

        XCTAssertEqual(decoded.id, obj.id)
        XCTAssertEqual(decoded.mesh, mesh)
        XCTAssertEqual(decoded.sourceStrokeIDs, [strokeID])
    }

    func testSculptObjectEquatable() {
        let id = UUID()
        let mesh = Mesh()
        let strokeIDs: Set<UUID> = [UUID()]
        let a = SculptObject(id: id, mesh: mesh, sourceStrokeIDs: strokeIDs)
        let b = SculptObject(id: id, mesh: mesh, sourceStrokeIDs: strokeIDs)
        XCTAssertEqual(a, b)
    }
}
