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

final class MeshBVHTests: XCTestCase {

    /// Brute-force ray cast for comparison (front-face only, matching BVH).
    private func bruteForceRaycast(mesh: Mesh, origin: SIMD3<Float>, direction: SIMD3<Float>) -> (t: Float, faceIndex: Int)? {
        var closestT: Float = Float.infinity
        var hitFace = -1
        for (fi, face) in mesh.faces.enumerated() {
            let v0 = mesh.vertices[Int(face.indices.x)].position
            let v1 = mesh.vertices[Int(face.indices.y)].position
            let v2 = mesh.vertices[Int(face.indices.z)].position
            let edge1 = v1 - v0, edge2 = v2 - v0
            let h = cross(direction, edge2)
            let a = dot(edge1, h)
            guard a > 1e-6 else { continue }
            let f = 1.0 / a
            let s = origin - v0
            let u = f * dot(s, h)
            guard u >= 0 && u <= 1 else { continue }
            let q = cross(s, edge1)
            let v = f * dot(direction, q)
            guard v >= 0 && u + v <= 1 else { continue }
            let t = f * dot(edge2, q)
            guard t > 1e-6 else { continue }
            if t < closestT { closestT = t; hitFace = fi }
        }
        return hitFace >= 0 ? (closestT, hitFace) : nil
    }

    /// Two parallel quads at z=5 and z=0. Ray from z=10 going in -z should hit z=5 first.
    func testBVHReturnsNearestSurface() {
        // Near quad at z=5 (front-facing: CCW from +z perspective)
        // Far quad at z=0
        let vertices = [
            // Near quad (z=5)
            MeshVertex(position: SIMD3(-1, -1, 5), normal: SIMD3(0, 0, 1)),
            MeshVertex(position: SIMD3( 1, -1, 5), normal: SIMD3(0, 0, 1)),
            MeshVertex(position: SIMD3( 1,  1, 5), normal: SIMD3(0, 0, 1)),
            MeshVertex(position: SIMD3(-1,  1, 5), normal: SIMD3(0, 0, 1)),
            // Far quad (z=0)
            MeshVertex(position: SIMD3(-1, -1, 0), normal: SIMD3(0, 0, 1)),
            MeshVertex(position: SIMD3( 1, -1, 0), normal: SIMD3(0, 0, 1)),
            MeshVertex(position: SIMD3( 1,  1, 0), normal: SIMD3(0, 0, 1)),
            MeshVertex(position: SIMD3(-1,  1, 0), normal: SIMD3(0, 0, 1)),
        ]
        let faces = [
            // Near quad (CCW from +z: 0,1,2 and 0,2,3)
            MeshFace(indices: SIMD3(0, 1, 2)),
            MeshFace(indices: SIMD3(0, 2, 3)),
            // Far quad (CCW from +z: 4,5,6 and 4,6,7)
            MeshFace(indices: SIMD3(4, 5, 6)),
            MeshFace(indices: SIMD3(4, 6, 7)),
        ]
        let mesh = Mesh(vertices: vertices, faces: faces)
        let bvh = MeshBVH(mesh: mesh)

        let origin = SIMD3<Float>(0, 0, 10)
        let direction = SIMD3<Float>(0, 0, -1)

        let bvhResult = bvh.raycast(origin: origin, direction: direction)
        let bruteResult = bruteForceRaycast(mesh: mesh, origin: origin, direction: direction)

        XCTAssertNotNil(bvhResult)
        XCTAssertNotNil(bruteResult)
        XCTAssertEqual(bvhResult!.t, bruteResult!.t, accuracy: 1e-4,
                       "BVH t=\(bvhResult!.t) but brute force t=\(bruteResult!.t)")
        // Near surface is at z=5, so t should be 5 (origin z=10, direction z=-1)
        XCTAssertEqual(bvhResult!.t, 5.0, accuracy: 1e-4,
                       "Should hit near surface at t=5, got t=\(bvhResult!.t)")
    }

    /// Many overlapping layers — BVH must still find the closest.
    func testBVHWithManyOverlappingLayers() {
        var vertices: [MeshVertex] = []
        var faces: [MeshFace] = []
        // Create 10 front-facing quads at z = 0, 1, 2, ..., 9
        for layer in 0..<10 {
            let z = Float(layer)
            let base = UInt32(layer * 4)
            vertices.append(contentsOf: [
                MeshVertex(position: SIMD3(-1, -1, z), normal: SIMD3(0, 0, 1)),
                MeshVertex(position: SIMD3( 1, -1, z), normal: SIMD3(0, 0, 1)),
                MeshVertex(position: SIMD3( 1,  1, z), normal: SIMD3(0, 0, 1)),
                MeshVertex(position: SIMD3(-1,  1, z), normal: SIMD3(0, 0, 1)),
            ])
            faces.append(MeshFace(indices: SIMD3(base, base+1, base+2)))
            faces.append(MeshFace(indices: SIMD3(base, base+2, base+3)))
        }
        let mesh = Mesh(vertices: vertices, faces: faces)
        let bvh = MeshBVH(mesh: mesh)

        let origin = SIMD3<Float>(0, 0, 20)
        let direction = SIMD3<Float>(0, 0, -1)

        let bvhResult = bvh.raycast(origin: origin, direction: direction)
        let bruteResult = bruteForceRaycast(mesh: mesh, origin: origin, direction: direction)

        XCTAssertNotNil(bvhResult)
        XCTAssertNotNil(bruteResult)
        // Nearest layer is at z=9, so t should be 11 (origin z=20, z=9 → t=11)
        XCTAssertEqual(bvhResult!.t, 11.0, accuracy: 1e-4,
                       "Should hit nearest layer at z=9, got t=\(bvhResult!.t)")
        XCTAssertEqual(bvhResult!.t, bruteResult!.t, accuracy: 1e-4)
    }

    /// Reproduce the exact hitTest math using ShapeInflater's actual winding convention.
    /// ShapeInflater front faces: (tl, tr, bl) which produces normals in -z.
    /// This means front surface is BACK-FACING relative to the ray direction (0,0,-1).
    /// With abs(a) > 1e-6, the ray should still hit the nearest surface.
    func testHitTestWithShapeInflaterWinding() {
        // Replicate ShapeInflater winding:
        // Front face at z=+5: indices (tl, tr, bl) → normal in -z (back-facing to camera ray)
        // Back face at z=-5: indices (tlB, blB, trB) → normal in +z (front-facing to camera ray)
        let vertices = [
            // Front quad at z=+5 — large enough to always be hit
            MeshVertex(position: SIMD3(-50, -50, 5), normal: SIMD3(0, 0, -1)),
            MeshVertex(position: SIMD3( 50, -50, 5), normal: SIMD3(0, 0, -1)),
            MeshVertex(position: SIMD3(-50,  50, 5), normal: SIMD3(0, 0, -1)),
            MeshVertex(position: SIMD3( 50,  50, 5), normal: SIMD3(0, 0, -1)),
            // Back quad at z=-5
            MeshVertex(position: SIMD3(-50, -50, -5), normal: SIMD3(0, 0, 1)),
            MeshVertex(position: SIMD3( 50, -50, -5), normal: SIMD3(0, 0, 1)),
            MeshVertex(position: SIMD3(-50,  50, -5), normal: SIMD3(0, 0, 1)),
            MeshVertex(position: SIMD3( 50,  50, -5), normal: SIMD3(0, 0, 1)),
        ]
        let faces = [
            // Front face winding: (tl, tr, bl) and (tr, br, bl) — ShapeInflater convention
            MeshFace(indices: SIMD3(0, 1, 2)),
            MeshFace(indices: SIMD3(1, 3, 2)),
            // Back face winding: (tlB, blB, trB) and (trB, blB, brB) — ShapeInflater convention
            MeshFace(indices: SIMD3(4, 6, 5)),
            MeshFace(indices: SIMD3(5, 6, 7)),
        ]
        let mesh = Mesh(vertices: vertices, faces: faces)

        // Set up projection matching SculptRenderer
        var minP = SIMD3<Float>(repeating: Float.infinity)
        var maxP = SIMD3<Float>(repeating: -Float.infinity)
        for v in mesh.vertices { minP = min(minP, v.position); maxP = max(maxP, v.position) }
        let center = (minP + maxP) / 2
        let extent = maxP - minP
        let r = max(extent.x, max(extent.y, extent.z)) / 2 * 1.3
        let viewSize = CGSize(width: 1024, height: 1024)
        let proj = SculptRenderer.orthographicProjection(
            left: -r, right: r, bottom: -r, top: r, near: -r * 10, far: r * 10)
        func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
            simd_float4x4(columns: (
                SIMD4<Float>(1,0,0,0), SIMD4<Float>(0,1,0,0),
                SIMD4<Float>(0,0,1,0), SIMD4<Float>(x,y,z,1)))
        }
        // Use the actual default rotation from SculptRenderer
        let cameraTilt: Float = 0.8
        let rotation = simd_quatf(angle: -cameraTilt, axis: SIMD3(1, 0, 0))
        let view = simd_float4x4(rotation) * translation(-center.x, -center.y, -center.z)
        let mvp = proj * view
        let invMVP = mvp.inverse

        // Unproject screen center
        let ndcX = Float(2 * 512.0 / viewSize.width - 1)
        let ndcY = Float(1 - 2 * 512.0 / viewSize.height)
        let near4 = invMVP * SIMD4<Float>(ndcX, ndcY, -1, 1)
        let far4  = invMVP * SIMD4<Float>(ndcX, ndcY, 1, 1)
        let nearW = SIMD3<Float>(near4.x, near4.y, near4.z) / near4.w
        let farW  = SIMD3<Float>(far4.x, far4.y, far4.z) / far4.w
        let direction = normalize(farW - nearW)

        let bvh = MeshBVH(mesh: mesh)

        // Default (closest): hits the farthest-from-camera visible surface
        let closest = bvh.raycast(origin: nearW, direction: direction, farthest: false)
        XCTAssertNotNil(closest)
        let closestZ = nearW.z + closest!.t * direction.z
        // Closest t hits surface farthest from camera (ray starts behind camera)

        // Farthest: hits the nearest-to-camera visible surface
        let farthest = bvh.raycast(origin: nearW, direction: direction, farthest: true)
        XCTAssertNotNil(farthest)
        let farthestZ = nearW.z + farthest!.t * direction.z
        // With orthographic ray from behind camera, largest t = nearest to viewer
        XCTAssertLessThan(farthestZ, closestZ,
            "Farthest t should hit surface nearer to camera (more negative z_view). " +
            "farthestZ=\(farthestZ), closestZ=\(closestZ)")
    }

    /// Exhaustive comparison: cast many rays and verify BVH matches brute force.
    func testBVHMatchesBruteForceExhaustive() {
        // Build a mesh with front and back surfaces (like ShapeInflater output)
        var vertices: [MeshVertex] = []
        var faces: [MeshFace] = []
        let gridSize = 10
        // Front surface (z > 0, normals +z)
        for y in 0..<gridSize {
            for x in 0..<gridSize {
                let fx = Float(x) - Float(gridSize)/2
                let fy = Float(y) - Float(gridSize)/2
                let z = 5.0 - 0.1 * (fx*fx + fy*fy) // dome shape
                vertices.append(MeshVertex(position: SIMD3(fx, fy, Float(z)), normal: SIMD3(0, 0, 1)))
            }
        }
        // Back surface (z < 0, normals -z)
        for y in 0..<gridSize {
            for x in 0..<gridSize {
                let fx = Float(x) - Float(gridSize)/2
                let fy = Float(y) - Float(gridSize)/2
                let z = -(5.0 - 0.1 * (fx*fx + fy*fy))
                vertices.append(MeshVertex(position: SIMD3(fx, fy, Float(z)), normal: SIMD3(0, 0, -1)))
            }
        }
        // Front surface faces (CCW from +z)
        let n = gridSize
        for y in 0..<(n-1) {
            for x in 0..<(n-1) {
                let i = UInt32(y * n + x)
                faces.append(MeshFace(indices: SIMD3(i, i+1, i+UInt32(n)+1)))
                faces.append(MeshFace(indices: SIMD3(i, i+UInt32(n)+1, i+UInt32(n))))
            }
        }
        // Back surface faces (CCW from -z, reversed winding)
        let offset = UInt32(n * n)
        for y in 0..<(n-1) {
            for x in 0..<(n-1) {
                let i = offset + UInt32(y * n + x)
                faces.append(MeshFace(indices: SIMD3(i, i+UInt32(n)+1, i+1)))
                faces.append(MeshFace(indices: SIMD3(i, i+UInt32(n), i+UInt32(n)+1)))
            }
        }

        let mesh = Mesh(vertices: vertices, faces: faces)
        let bvh = MeshBVH(mesh: mesh)
        let direction = SIMD3<Float>(0, 0, -1)
        var mismatches = 0

        // Cast rays across a grid
        for sy in stride(from: -4.0, through: 4.0, by: 0.5) {
            for sx in stride(from: -4.0, through: 4.0, by: 0.5) {
                let origin = SIMD3<Float>(Float(sx), Float(sy), 20)
                let bvhResult = bvh.raycast(origin: origin, direction: direction)
                let bruteResult = bruteForceRaycast(mesh: mesh, origin: origin, direction: direction)

                if let bvhR = bvhResult, let bruteR = bruteResult {
                    if abs(bvhR.t - bruteR.t) > 1e-3 {
                        mismatches += 1
                        XCTFail("Mismatch at (\(sx),\(sy)): BVH t=\(bvhR.t) face=\(bvhR.faceIndex), brute t=\(bruteR.t) face=\(bruteR.faceIndex)")
                    }
                } else if (bvhResult == nil) != (bruteResult == nil) {
                    mismatches += 1
                    XCTFail("Hit/miss mismatch at (\(sx),\(sy)): BVH=\(bvhResult != nil), brute=\(bruteResult != nil)")
                }
            }
        }
        XCTAssertEqual(mismatches, 0, "\(mismatches) mismatches between BVH and brute force")
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
