import SwiftUI

struct SculptScreen: View {
    var strokes: [Stroke]
    @State private var sculptObject: SculptObject?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MetalCanvasView(strokes: strokes, sculptObject: sculptObject)
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
            .onAppear {
                sculptObject = InferencePipeline.infer(from: strokes)
            }
    }
}
