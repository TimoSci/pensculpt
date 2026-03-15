import XCTest
import simd
@testable import PenSculpt

final class MeshAssemblerTests: XCTestCase {

    private func makeSegment(radii: [CGFloat], spacing: CGFloat = 10) -> SkeletonSegment {
        let points = radii.enumerated().map { i, r in
            SkeletonPoint(position: CGPoint(x: 0, y: CGFloat(i) * spacing), radius: r)
        }
        return SkeletonSegment(points: points)
    }

    private func makePrimitive(radii: [CGFloat], type: PrimitiveType? = nil) -> FittedPrimitive {
        let segment = makeSegment(radii: radii)
        let t = type ?? .cylinder(radius: Float(radii.first ?? 1))
        return FittedPrimitive(type: t, segment: segment)
    }

    // MARK: - Edge cases

    func testEmptySegmentProducesEmptyMesh() {
        let segment = SkeletonSegment(points: [])
        let primitive = FittedPrimitive(type: .custom, segment: segment)
        let mesh = MeshAssembler.assemble(from: primitive)
        XCTAssertTrue(mesh.isEmpty)
    }

    func testSinglePointProducesEmptyMesh() {
        let segment = SkeletonSegment(points: [
            SkeletonPoint(position: .zero, radius: 10)
        ])
        let primitive = FittedPrimitive(type: .cylinder(radius: 10), segment: segment)
        let mesh = MeshAssembler.assemble(from: primitive)
        XCTAssertTrue(mesh.isEmpty)
    }

    // MARK: - Vertex counts (rings + 2 cap vertices)

    func testCylinderVertexCount() {
        let primitive = makePrimitive(radii: [10, 10, 10, 10])
        let mesh = MeshAssembler.assemble(from: primitive, radialSegments: 8)
        // 4 rings × 8 segments + 2 cap vertices = 34
        XCTAssertEqual(mesh.vertexCount, 34)
    }

    func testCylinderFaceCount() {
        let primitive = makePrimitive(radii: [10, 10, 10, 10])
        let mesh = MeshAssembler.assemble(from: primitive, radialSegments: 8)
        // 3 ring gaps × 8 × 2 triangles = 48 body + 8 bottom cap + 8 top cap = 64
        XCTAssertEqual(mesh.faceCount, 64)
    }

    func testRadialSegmentsAffectVertexCount() {
        let primitive = makePrimitive(radii: [10, 10])
        let mesh4 = MeshAssembler.assemble(from: primitive, radialSegments: 4)
        let mesh16 = MeshAssembler.assemble(from: primitive, radialSegments: 16)
        XCTAssertEqual(mesh4.vertexCount, 10)  // 2 rings × 4 + 2 caps
        XCTAssertEqual(mesh16.vertexCount, 34) // 2 rings × 16 + 2 caps
    }

    // MARK: - Geometry correctness

    func testCylinderRingVerticesHaveConstantRadius() {
        let r: Float = 15
        let primitive = makePrimitive(radii: [CGFloat(r), CGFloat(r), CGFloat(r)])
        let mesh = MeshAssembler.assemble(from: primitive, radialSegments: 8)

        // Skip first vertex (bottom cap) and last vertex (top cap)
        for vertex in mesh.vertices.dropFirst().dropLast() {
            let xzRadius = hypot(vertex.position.x, vertex.position.z)
            XCTAssertEqual(xzRadius, r, accuracy: 0.01)
        }
    }

    func testConeVerticesHaveVaryingRadius() {
        let primitive = makePrimitive(
            radii: [20, 10],
            type: .cone(startRadius: 20, endRadius: 10)
        )
        let mesh = MeshAssembler.assemble(from: primitive, radialSegments: 8)

        // First ring (after bottom cap, indices 1..8)
        let firstRing = Array(mesh.vertices[1...8])
        let firstRadius = hypot(firstRing[0].position.x, firstRing[0].position.z)
        XCTAssertEqual(firstRadius, 20, accuracy: 0.1)

        // Second ring (indices 9..16)
        let secondRing = Array(mesh.vertices[9...16])
        let secondRadius = hypot(secondRing[0].position.x, secondRing[0].position.z)
        XCTAssertEqual(secondRadius, 10, accuracy: 0.1)
    }

    func testMeshIsCenteredVertically() {
        let primitive = makePrimitive(radii: [10, 10, 10])
        let mesh = MeshAssembler.assemble(from: primitive, radialSegments: 4)

        let yValues = mesh.vertices.map { $0.position.y }
        let yCenter = (yValues.min()! + yValues.max()!) / 2
        XCTAssertEqual(yCenter, 0, accuracy: 0.1)
    }

    func testMeshHasCaps() {
        let primitive = makePrimitive(radii: [10, 10])
        let mesh = MeshAssembler.assemble(from: primitive, radialSegments: 4)

        // First vertex should be bottom cap (at center, radius 0)
        XCTAssertEqual(mesh.vertices[0].position.x, 0, accuracy: 0.01)
        XCTAssertEqual(mesh.vertices[0].position.z, 0, accuracy: 0.01)

        // Last vertex should be top cap
        let last = mesh.vertices.last!
        XCTAssertEqual(last.position.x, 0, accuracy: 0.01)
        XCTAssertEqual(last.position.z, 0, accuracy: 0.01)
    }

    // MARK: - Face validity

    func testFaceIndicesInRange() {
        let primitive = makePrimitive(radii: [10, 10, 10])
        let mesh = MeshAssembler.assemble(from: primitive, radialSegments: 8)
        let maxIndex = UInt32(mesh.vertexCount)

        for face in mesh.faces {
            XCTAssertLessThan(face.indices.x, maxIndex)
            XCTAssertLessThan(face.indices.y, maxIndex)
            XCTAssertLessThan(face.indices.z, maxIndex)
        }
    }
}
