import SwiftUI
import PencilKit

struct DrawingScreen: View {
    @Binding var canvas: Canvas
    @State private var pkDrawing = PKDrawing()
    @State private var selectedTool: DrawingTool = .pen
    @State private var showToolbar = false
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        ZStack(alignment: .bottom) {
            CanvasView(
                drawing: $pkDrawing,
                selectedTool: selectedTool,
                onStrokeCompleted: { pkStroke in
                    let stroke = StrokeConverter.convert(pkStroke)
                    addStrokeWithUndo(stroke)
                },
                onStrokeErased: { oldDrawing in
                    // PencilKit handled the visual erase; sync our model
                    let currentIDs = Set(StrokeConverter.convertAll(pkDrawing).map(\.id))
                    let removedStrokes = canvas.strokes.filter { !currentIDs.contains($0.id) }
                    for removed in removedStrokes {
                        removeStrokeWithUndo(removed)
                    }
                }
            )
            .ignoresSafeArea()
            .onReceive(NotificationCenter.default.publisher(for: .pencilDoubleTap)) { _ in
                selectedTool = selectedTool == .pen ? .eraser : .pen
            }

            if showToolbar {
                FloatingToolbar(
                    selectedTool: $selectedTool,
                    onUndo: { undoManager?.undo() },
                    onRedo: { undoManager?.redo() },
                    onClear: { clearWithUndo() }
                )
                .padding(.bottom, 60)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Toggle button — always visible
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showToolbar.toggle()
                }
            } label: {
                Image(systemName: showToolbar ? "chevron.down.circle.fill" : "ellipsis.circle")
                    .font(.title2)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Undo-aware actions

    private func addStrokeWithUndo(_ stroke: Stroke) {
        canvas.addStroke(stroke)
        undoManager?.registerUndo(withTarget: UndoProxy.shared) { _ in
            canvas.removeStroke(id: stroke.id)
            // Remove from PencilKit too
            pkDrawing = PKDrawing(strokes: pkDrawing.strokes.dropLast())
        }
    }

    private func removeStrokeWithUndo(_ stroke: Stroke) {
        canvas.removeStroke(id: stroke.id)
        undoManager?.registerUndo(withTarget: UndoProxy.shared) { _ in
            canvas.addStroke(stroke)
        }
    }

    private func clearWithUndo() {
        let previousStrokes = canvas.strokes
        let previousDrawing = pkDrawing
        canvas.clearStrokes()
        pkDrawing = PKDrawing()
        undoManager?.registerUndo(withTarget: UndoProxy.shared) { _ in
            canvas.strokes = previousStrokes
            pkDrawing = previousDrawing
        }
    }

}

/// A reference type target for UndoManager registration (UndoManager requires AnyObject).
private final class UndoProxy {
    static let shared = UndoProxy()
}
