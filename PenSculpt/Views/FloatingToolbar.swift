import SwiftUI

struct FloatingToolbar: View {
    @Binding var selectedTool: DrawingTool
    @Binding var strokeWidth: CGFloat
    @Binding var strokeOpacity: CGFloat
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onClear: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Sliders row
            HStack(spacing: 16) {
                Image(systemName: "lineweight")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $strokeWidth, in: 1...20, step: 0.5)
                    .frame(width: 120)

                Image(systemName: "circle.lefthalf.filled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $strokeOpacity, in: 0.05...1, step: 0.05)
                    .frame(width: 120)
            }
            .padding(.horizontal, 16)

            // Tools row
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
                        Image(systemName: tool.iconName)
                            .foregroundStyle(selectedTool == tool ? .primary : .secondary)
                    }
                }

                Divider().frame(height: 24)

                Button(action: onClear) {
                    Image(systemName: "trash")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
