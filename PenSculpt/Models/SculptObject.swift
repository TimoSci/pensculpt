import Foundation
import simd

struct SurfaceStroke: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var points: [SIMD3<Float>]
    var widths: [Float]

    init(id: UUID = UUID(), points: [SIMD3<Float>] = [], widths: [Float] = []) {
        self.id = id
        self.points = points
        self.widths = widths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        points = try container.decode([SIMD3<Float>].self, forKey: .points)
        widths = try container.decodeIfPresent([Float].self, forKey: .widths)
            ?? Array(repeating: 3.0, count: points.count)
    }
}

extension SurfaceStroke {
    /// Re-projects stroke points onto a new mesh by casting rays along `rayDir`.
    /// Points that miss the mesh are dropped. Returns nil if no points survive.
    func reprojected(onto mesh: Mesh, rayDir: SIMD3<Float>, offset: Float) -> SurfaceStroke? {
        var newPoints: [SIMD3<Float>] = []
        var newWidths: [Float] = []

        for i in 0..<points.count {
            // Cast ray from the point along both directions to find the new surface
            if let hit = Self.castOntoMesh(from: points[i], direction: rayDir, mesh: mesh, offset: offset)
                ?? Self.castOntoMesh(from: points[i], direction: -rayDir, mesh: mesh, offset: offset) {
                newPoints.append(hit)
                newWidths.append(i < widths.count ? widths[i] : 3)
            }
        }

        guard newPoints.count > 1 else { return nil }
        return SurfaceStroke(id: id, points: newPoints, widths: newWidths)
    }

    private static func castOntoMesh(from origin: SIMD3<Float>, direction: SIMD3<Float>,
                                      mesh: Mesh, offset: Float) -> SIMD3<Float>? {
        var closestT: Float = Float.infinity
        var hitPoint: SIMD3<Float>?

        for face in mesh.faces {
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
            if t > 1e-6 && abs(t) < abs(closestT) {
                closestT = t
                hitPoint = origin + t * direction - direction * offset
            }
        }
        return hitPoint
    }
}

struct SculptObject: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var mesh: Mesh
    var sourceStrokeIDs: Set<UUID>
    var surfaceStrokes: [SurfaceStroke]
    /// The 2D bounding rect of the source strokes in canvas coordinates.
    /// Used to map the 3D mesh back to its original position on the drawing canvas.
    var originRect: CGRect

    init(id: UUID = UUID(), mesh: Mesh, sourceStrokeIDs: Set<UUID>,
         surfaceStrokes: [SurfaceStroke] = [], originRect: CGRect = .zero) {
        self.id = id
        self.mesh = mesh
        self.sourceStrokeIDs = sourceStrokeIDs
        self.surfaceStrokes = surfaceStrokes
        self.originRect = originRect
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        mesh = try container.decode(Mesh.self, forKey: .mesh)
        sourceStrokeIDs = try container.decode(Set<UUID>.self, forKey: .sourceStrokeIDs)
        surfaceStrokes = try container.decodeIfPresent([SurfaceStroke].self, forKey: .surfaceStrokes) ?? []
        originRect = try container.decodeIfPresent(CGRect.self, forKey: .originRect) ?? .zero
    }
}
