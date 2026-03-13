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
                tool: pkToolBinding,
                onStrokeCompleted: { pkStroke in
                    let stroke = StrokeConverter.convert(pkStroke)
                    canvas.addStroke(stroke)
                }
            )
            .ignoresSafeArea()
            .gesture(
                DragGesture(minimumDistance: 50)
                    .onEnded { value in
                        if value.startLocation.x < 20 {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showToolbar.toggle()
                            }
                        }
                    }
            )

            if showToolbar {
                FloatingToolbar(
                    selectedTool: $selectedTool,
                    onUndo: { undoManager?.undo() },
                    onRedo: { undoManager?.redo() },
                    onClear: {
                        pkDrawing = PKDrawing()
                        canvas.clearStrokes()
                    }
                )
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var pkToolBinding: Binding<PKTool> {
        Binding(
            get: {
                switch selectedTool {
                case .pen:
                    return PKInkingTool(.pen, color: .black, width: 3)
                case .eraser:
                    return PKEraserTool(.vector)
                }
            },
            set: { _ in }
        )
    }
}
