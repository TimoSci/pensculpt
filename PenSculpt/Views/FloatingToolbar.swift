import SwiftUI

struct FloatingToolbar: View {
    @Binding var selectedTool: DrawingTool
    @Binding var strokeWidth: CGFloat
    @Binding var strokeOpacity: CGFloat
    let activeColor: CodableColor
    let recentColors: [CodableColor]
    var onSelectPresetColor: (CodableColor) -> Void
    var onSelectCustomColor: (CodableColor) -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onClear: () -> Void

    @State private var showColorPopover = false

    var body: some View {
        VStack(spacing: 8) {
            BrushControls(brushSize: $strokeWidth, brushOpacity: $strokeOpacity)
                .padding(.horizontal, 16)

            HStack(spacing: 12) {
                Button { showColorPopover = true } label: {
                    Circle()
                        .fill(Color(activeColor))
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Color.primary.opacity(0.4), lineWidth: 1))
                }
                .popover(isPresented: $showColorPopover) {
                    ColorPickerPopover(
                        activeColor: activeColor,
                        recentColors: recentColors,
                        onSelectPreset: onSelectPresetColor,
                        onSelectCustom: onSelectCustomColor
                    )
                }

                Divider().frame(height: 24)

                Button(action: onUndo) { Image(systemName: "arrow.uturn.backward") }
                Button(action: onRedo) { Image(systemName: "arrow.uturn.forward") }

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

                Button(action: onClear) { Image(systemName: "trash") }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
