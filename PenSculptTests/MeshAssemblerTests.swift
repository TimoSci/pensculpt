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

    // MARK: - Mesh is produced

    func testProducesMeshWithVerticesAndFaces() {
        let primitive = makePrimitive(radii: [10, 10, 10])
        let mesh = MeshAssembler.assemble(from: primitive, radialSegments: 8)
        XCTAssertGreaterThan(mesh.vertexCount, 0)
        XCTAssertGreaterThan(mesh.faceCount, 0)
    }

    func testMoreRadialSegmentsProduceMoreVertices() {
        let primitive = makePrimitive(radii: [10, 10])
        let mesh4 = MeshAssembler.assemble(from: primitive, radialSegments: 4)
        let mesh16 = MeshAssembler.assemble(from: primitive, radialSegments: 16)
        XCTAssertGreaterThan(mesh16.vertexCount, mesh4.vertexCount)
    }

    // MARK: - Geometry correctness

    func testMeshIsCenteredVertically() {
        let primitive = makePrimitive(radii: [10, 10, 10])
        let mesh = MeshAssembler.assemble(from: primitive, radialSegments: 4)

        let yValues = mesh.vertices.map { $0.position.y }
        let yCenter = (yValues.min()! + yValues.max()!) / 2
        XCTAssertEqual(yCenter, 0, accuracy: 1)
    }

    func testTaperClosesEnds() {
        // The mesh should taper toward zero radius at both ends
        let primitive = makePrimitive(radii: [10, 10, 10])
        let mesh = MeshAssembler.assemble(from: primitive, radialSegments: 8)

        // Find the ring with the smallest Y (bottom) and largest Y (top)
        let sortedByY = mesh.vertices.sorted { $0.position.y < $1.position.y }
        let bottomVertex = sortedByY.first!
        let topVertex = sortedByY.last!

        // Bottom and top ring vertices should have very small XZ radius (tapered)
        let bottomRadius = hypot(bottomVertex.position.x, bottomVertex.position.z)
        let topRadius = hypot(topVertex.position.x, topVertex.position.z)
        XCTAssertLessThan(bottomRadius, 5, "Bottom should taper")
        XCTAssertLessThan(topRadius, 5, "Top should taper")
    }

    func testConeVerticesHaveVaryingRadius() {
        let primitive = makePrimitive(
            radii: [20, 10],
            type: .cone(startRadius: 20, endRadius: 10)
        )
        let mesh = MeshAssembler.assemble(from: primitive, radialSegments: 8)

        // Find max and min XZ radii (excluding tapered ends)
        let xzRadii = mesh.vertices.map { hypot($0.position.x, $0.position.z) }
        let maxR = xzRadii.max()!
        let minR = xzRadii.min()!
        XCTAssertGreaterThan(maxR, minR + 1, "Cone should have varying radii")
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
