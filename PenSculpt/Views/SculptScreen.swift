import SwiftUI

struct SculptScreen: View {
    var strokes: [Stroke]
    @Binding var sculptObjects: [SculptObject]
    var config: SculptConfig = .default
    @State private var sculptObject: SculptObject?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MetalCanvasView(strokes: strokes, sculptObject: sculptObject, config: config)
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
                let strokeIDs = Set(strokes.map(\.id))
                if let existing = sculptObjects.first(where: { $0.sourceStrokeIDs == strokeIDs }) {
                    sculptObject = existing
                    print("[SculptScreen] Loaded saved sculpt object (\(existing.mesh.vertexCount) vertices)")
                } else {
                    let obj = ShapeInflater.sculpt(from: strokes, config: config)
                    sculptObject = obj
                    sculptObjects.append(obj)
                    print("[SculptScreen] Created new sculpt object (\(obj.mesh.vertexCount) vertices)")
                }
            }
    }
}
