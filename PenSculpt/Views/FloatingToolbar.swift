import SwiftUI

enum DrawingTool: String, CaseIterable {
    case pen
    case eraser
}

struct FloatingToolbar: View {
    @Binding var selectedTool: DrawingTool
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onClear: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
            }
            Button(action: onRedo) {
                Image(systemName: "arrow.uturn.forward")
            }

            Divider().frame(height: 24)

            ForEach(DrawingTool.allCases, id: \.self) { tool in
                Button {
                    selectedTool = tool
                } label: {
                    Image(systemName: tool == .pen ? "pencil.tip" : "eraser")
                        .foregroundStyle(selectedTool == tool ? .primary : .secondary)
                }
            }

            Divider().frame(height: 24)

            Button(action: onClear) {
                Image(systemName: "trash")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
