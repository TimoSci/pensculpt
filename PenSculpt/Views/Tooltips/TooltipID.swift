import Foundation

struct TooltipContent: Equatable {
    let title: String
    let description: String?
}

enum TooltipID: String, CaseIterable {
    // Drawing — FloatingToolbar
    case colorSwatch
    case undo
    case redo
    case toolPen
    case toolEraser
    case toolPixelEraser
    case clear
    case exportImage

    // Drawing — overlay
    case toolbarCollapse

    // Drawing — nav bar
    case modeToggle
    case autosaveToggle
    case save

    // Shared
    case tooltipsToggle

    // Sculpt — toolbar topLeading
    case sculptClose
    case sculptReinfer
    case sculptReinferMorph
    case sculptAutoProject
    case sculptExport

    // Sculpt — bottom toolbar
    case sculptColorSwatch
    case sculptSurfaceSpace

    // Sculpt — corners
    case sculptRotate
    case sculptEraser
    case sculptDeform

    var content: TooltipContent {
        switch self {
        case .colorSwatch:        return .init(title: "Color", description: "Tap to change the active drawing color")
        case .undo:               return .init(title: "Undo", description: nil)
        case .redo:               return .init(title: "Redo", description: nil)
        case .toolPen:            return .init(title: "Pen", description: "Draw with the pen tool")
        case .toolEraser:         return .init(title: "Eraser", description: "Erase whole strokes")
        case .toolPixelEraser:    return .init(title: "Pixel eraser", description: "Erase parts of strokes pixel by pixel")
        case .clear:              return .init(title: "Clear", description: "Remove all strokes from the canvas")
        case .exportImage:        return .init(title: "Share", description: "Export the drawing as an image")
        case .toolbarCollapse:    return .init(title: "Toolbar", description: "Show or hide the drawing toolbar")
        case .modeToggle:         return .init(title: "Selection mode", description: "Switch between drawing and lasso selection")
        case .autosaveToggle:     return .init(title: "Autosave", description: "Save changes automatically as you draw")
        case .save:               return .init(title: "Save", description: nil)
        case .tooltipsToggle:     return .init(title: "Tooltips", description: "Show or hide button hints on hover")
        case .sculptClose:        return .init(title: "Close", description: "Return to the 2D canvas")
        case .sculptReinfer:      return .init(title: "Re-infer shape", description: "Rebuild the 3D shape from the current strokes")
        case .sculptReinferMorph: return .init(title: "Morph re-infer (beta)", description: "Smoothly morph the current shape into the re-inferred one")
        case .sculptAutoProject:  return .init(title: "Auto-project strokes", description: "Bring surface strokes back to 2D on exit")
        case .sculptExport:       return .init(title: "Share", description: "Export an image or 3D mesh")
        case .sculptColorSwatch:  return .init(title: "Color", description: "Active color for new surface strokes")
        case .sculptSurfaceSpace: return .init(title: "Stroke space", description: "Toggle strokes anchored to the surface or to the screen")
        case .sculptRotate:       return .init(title: "Rotate", description: "Hold and drag to rotate the 3D view")
        case .sculptEraser:       return .init(title: "Eraser / Smoother", description: "Erases strokes; while in deform mode, smooths the surface")
        case .sculptDeform:       return .init(title: "Deform", description: "Push and pull the 3D surface with the Pencil")
        }
    }
}
