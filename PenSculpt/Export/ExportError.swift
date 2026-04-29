import Foundation

enum ExportError: LocalizedError {
    case emptyContent
    case renderFailed
    case modelIOFailed(Error)
    case writeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "Nada para exportar."
        case .renderFailed:
            return "Não foi possível gerar a imagem."
        case .modelIOFailed(let err):
            return "Falha ao exportar a malha 3D: \(err.localizedDescription)"
        case .writeFailed(let err):
            return "Falha ao salvar o arquivo: \(err.localizedDescription)"
        }
    }
}
