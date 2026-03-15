import PencilKit

/// Holds a weak reference to the PKCanvasView for coordinate conversion
/// between UIViewRepresentable views in the SwiftUI layout.
class ViewBridge {
    weak var canvasView: PKCanvasView?
}
