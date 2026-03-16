import Foundation
import simd

struct SurfaceStroke: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var points: [SIMD3<Float>]

    init(id: UUID = UUID(), points: [SIMD3<Float>] = []) {
        self.id = id
        self.points = points
    }
}

struct SculptObject: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var mesh: Mesh
    var sourceStrokeIDs: Set<UUID>
    var surfaceStrokes: [SurfaceStroke]

    init(id: UUID = UUID(), mesh: Mesh, sourceStrokeIDs: Set<UUID>, surfaceStrokes: [SurfaceStroke] = []) {
        self.id = id
        self.mesh = mesh
        self.sourceStrokeIDs = sourceStrokeIDs
        self.surfaceStrokes = surfaceStrokes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        mesh = try container.decode(Mesh.self, forKey: .mesh)
        sourceStrokeIDs = try container.decode(Set<UUID>.self, forKey: .sourceStrokeIDs)
        surfaceStrokes = try container.decodeIfPresent([SurfaceStroke].self, forKey: .surfaceStrokes) ?? []
    }
}
