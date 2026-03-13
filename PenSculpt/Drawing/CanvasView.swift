import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var tool: PKTool
    var onStrokeCompleted: ((PKStroke) -> Void)?

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawing = drawing
        canvasView.tool = tool
        canvasView.drawingPolicy = .pencilOnly
        canvasView.backgroundColor = .white
        canvasView.isOpaque = true
        canvasView.delegate = context.coordinator
        canvasView.overrideUserInterfaceStyle = .light
        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        if canvasView.tool.description != tool.description {
            canvasView.tool = tool
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: CanvasView
        private var previousStrokeCount = 0

        init(_ parent: CanvasView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
            let currentCount = canvasView.drawing.strokes.count
            if currentCount > previousStrokeCount,
               let lastStroke = canvasView.drawing.strokes.last {
                parent.onStrokeCompleted?(lastStroke)
            }
            previousStrokeCount = currentCount
        }
    }
}
