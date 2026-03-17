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
