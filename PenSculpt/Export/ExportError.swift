import Foundation

enum ExportError: LocalizedError {
    case emptyContent
    case renderFailed
    case modelIOFailed(Error)
    case writeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "Nothing to export."
        case .renderFailed:
            return "Couldn't render the image."
        case .modelIOFailed(let err):
            return "Failed to export 3D mesh: \(err.localizedDescription)"
        case .writeFailed(let err):
            return "Failed to save file: \(err.localizedDescription)"
        }
    }
}
