import Foundation

enum MeshFormat: String, CaseIterable {
    case obj
    case usdz

    var fileExtension: String { rawValue }
}

enum SculptScope {
    case activeOnly
    case all
}
