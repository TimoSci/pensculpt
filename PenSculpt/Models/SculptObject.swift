import Foundation

struct SculptObject: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var mesh: Mesh
    var sourceStrokeIDs: Set<UUID>

    init(id: UUID = UUID(), mesh: Mesh, sourceStrokeIDs: Set<UUID>) {
        self.id = id
        self.mesh = mesh
        self.sourceStrokeIDs = sourceStrokeIDs
    }
}
