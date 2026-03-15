import SwiftUI

struct SculptScreen: View {
    var strokes: [Stroke]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MetalCanvasView(strokes: strokes)
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
    }
}
