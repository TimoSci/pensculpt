import Foundation

enum DrawingTool: String, CaseIterable {
    case pen
    case eraser
    case pixelEraser

    var isEraser: Bool {
        self == .eraser || self == .pixelEraser
    }

    var iconName: String {
        switch self {
        case .pen: return "pencil.tip"
        case .eraser: return "eraser"
        case .pixelEraser: return "eraser.fill"
        }
    }
}
