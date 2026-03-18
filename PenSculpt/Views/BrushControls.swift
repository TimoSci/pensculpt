import SwiftUI

struct BrushControls: View {
    @Binding var brushSize: CGFloat
    @Binding var brushOpacity: CGFloat
    var isDeformMode: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "lineweight")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $brushSize, in: 1...20, step: 0.5)
                .frame(width: 120)

            Image(systemName: isDeformMode ? "bolt.fill" : "circle.lefthalf.filled")
                .font(.caption)
                .foregroundStyle(isDeformMode ? .orange : .secondary)
            Slider(value: $brushOpacity, in: 0.05...1, step: 0.05)
                .tint(isDeformMode ? .orange : nil)
                .frame(width: 120)
        }
    }
}
