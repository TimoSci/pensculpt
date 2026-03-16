import Foundation
import simd

struct MeshVertex: Codable, Equatable, Sendable {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
}

struct MeshFace: Codable, Equatable, Sendable {
    let indices: SIMD3<UInt32>
}

struct Mesh: Codable, Equatable, Sendable {
    var vertices: [MeshVertex]
    var faces: [MeshFace]

    init(vertices: [MeshVertex] = [], faces: [MeshFace] = []) {
        self.vertices = vertices
        self.faces = faces
    }

    var isEmpty: Bool { vertices.isEmpty || faces.isEmpty }
    var vertexCount: Int { vertices.count }
    var faceCount: Int { faces.count }
}
