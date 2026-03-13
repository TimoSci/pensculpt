import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var tool: PKTool
    var undoManager: UndoManager?
    var onStrokeCompleted: ((PKStroke) -> Void)?
    var onStrokeErased: ((_ oldDrawing: PKDrawing) -> Void)?

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawing = drawing
        canvasView.tool = tool
        canvasView.drawingPolicy = .pencilOnly
        canvasView.backgroundColor = .white
        canvasView.isOpaque = true
        canvasView.delegate = context.coordinator
        canvasView.overrideUserInterfaceStyle = .light

        // Wire PencilKit's built-in undo to our UndoManager
        if let undoManager {
            canvasView.undoManager?.removeAllActions()
        }

        // Apple Pencil double-tap interaction
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = context.coordinator
        canvasView.addInteraction(pencilInteraction)

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

    class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        let parent: CanvasView
        private var previousStrokeCount = 0
        private var previousDrawing = PKDrawing()

        init(_ parent: CanvasView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let currentDrawing = canvasView.drawing
            let currentCount = currentDrawing.strokes.count

            if currentCount > previousStrokeCount,
               let lastStroke = currentDrawing.strokes.last {
                parent.onStrokeCompleted?(lastStroke)
            } else if currentCount < previousStrokeCount {
                parent.onStrokeErased?(previousDrawing)
            }

            parent.drawing = currentDrawing
            previousDrawing = currentDrawing
            previousStrokeCount = currentCount
        }

        // MARK: - UIPencilInteractionDelegate

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            // Toggle between pen and eraser on Apple Pencil double-tap
            NotificationCenter.default.post(name: .pencilDoubleTap, object: nil)
        }
    }
}

extension Notification.Name {
    static let pencilDoubleTap = Notification.Name("PenSculptPencilDoubleTap")
}
