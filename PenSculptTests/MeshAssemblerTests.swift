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

    // MARK: - Vertex counts

    func testCylinderVertexCount() {
        let primitive = makePrimitive(radii: [10, 10, 10, 10])
        let mesh = MeshAssembler.assemble(from: primitive, radialSegments: 8)
        // 4 rings × 8 segments = 32 vertices
        XCTAssertEqual(mesh.vertexCount, 32)
    }

    func testCylinderFaceCount() {
        let primitive = makePrimitive(radii: [10, 10, 10, 10])
        let mesh = MeshAssembler.assemble(from: primitive, radialSegments: 8)
        // 3 gaps between 4 rings × 8 segments × 2 triangles = 48
        XCTAssertEqual(mesh.faceCount, 48)
    }

    func testRadialSegmentsAffectVertexCount() {
        let primitive = makePrimitive(radii: [10, 10])
        let mesh4 = MeshAssembler.assemble(from: primitive, radialSegments: 4)
        let mesh16 = MeshAssembler.assemble(from: primitive, radialSegments: 16)
        XCTAssertEqual(mesh4.vertexCount, 8)  // 2 rings × 4
        XCTAssertEqual(mesh16.vertexCount, 32) // 2 rings × 16
    }

    // MARK: - Geometry correctness

    func testCylinderVerticesHaveConstantRadius() {
        let r: Float = 15
        let primitive = makePrimitive(radii: [CGFloat(r), CGFloat(r), CGFloat(r)])
        let mesh = MeshAssembler.assemble(from: primitive, radialSegments: 8)

        for vertex in mesh.vertices {
            let xzRadius = hypot(vertex.position.x, vertex.position.z)
            XCTAssertEqual(xzRadius, r, accuracy: 0.01,
                           "All vertices should be at radius \(r)")
        }
    }

    func testConeVerticesHaveVaryingRadius() {
        let primitive = makePrimitive(
            radii: [20, 10],
            type: .cone(startRadius: 20, endRadius: 10)
        )
        let mesh = MeshAssembler.assemble(from: primitive, radialSegments: 8)

        // First ring should have radius ≈ 20
        let firstRing = Array(mesh.vertices.prefix(8))
        let firstRadius = hypot(firstRing[0].position.x, firstRing[0].position.z)
        XCTAssertEqual(firstRadius, 20, accuracy: 0.1)

        // Second ring should have radius ≈ 10
        let secondRing = Array(mesh.vertices.suffix(8))
        let secondRadius = hypot(secondRing[0].position.x, secondRing[0].position.z)
        XCTAssertEqual(secondRadius, 10, accuracy: 0.1)
    }

    func testMeshIsCenteredVertically() {
        let primitive = makePrimitive(radii: [10, 10, 10])
        let mesh = MeshAssembler.assemble(from: primitive, radialSegments: 4)

        let yValues = mesh.vertices.map { $0.position.y }
        let yCenter = (yValues.min()! + yValues.max()!) / 2
        XCTAssertEqual(yCenter, 0, accuracy: 0.1,
                       "Mesh should be centered at y=0")
    }

    func testNormalsPointOutward() {
        let primitive = makePrimitive(radii: [10, 10])
        let mesh = MeshAssembler.assemble(from: primitive, radialSegments: 8)

        for vertex in mesh.vertices {
            let radialDir = SIMD2<Float>(vertex.position.x, vertex.position.z)
            let normalXZ = SIMD2<Float>(vertex.normal.x, vertex.normal.z)
            // Dot product should be positive (normal points outward)
            let dot = radialDir.x * normalXZ.x + radialDir.y * normalXZ.y
            XCTAssertGreaterThan(dot, 0, "Normal should point outward from axis")
        }
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
