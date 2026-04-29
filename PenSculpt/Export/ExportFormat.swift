import Foundation

enum MeshFormat: String, CaseIterable {
    case obj

    var fileExtension: String { rawValue }
}

enum SculptScope {
    case activeOnly
    case all
}
