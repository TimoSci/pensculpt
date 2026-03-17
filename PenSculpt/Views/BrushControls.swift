import SwiftUI

struct BrushControls: View {
    @Binding var brushSize: CGFloat
    @Binding var brushOpacity: CGFloat

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "lineweight")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $brushSize, in: 1...20, step: 0.5)
                .frame(width: 120)

            Image(systemName: "circle.lefthalf.filled")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $brushOpacity, in: 0.05...1, step: 0.05)
                .frame(width: 120)
        }
    }
}
