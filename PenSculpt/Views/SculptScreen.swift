import SwiftUI

struct SculptScreen: View {
    var strokes: [Stroke]
    @Binding var sculptObjects: [SculptObject]
    var config: SculptConfig = .default
    @State private var activeObjectID: UUID?
    @State private var isRotateMode = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MetalCanvasView(
            strokes: strokes,
            sculptObjects: sculptObjects,
            activeObjectID: activeObjectID,
            config: config,
            isRotateMode: isRotateMode,
            onObjectTapped: cycleActiveObject
        )
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
        .overlay(alignment: .top) {
            if sculptObjects.count > 1 {
                Text("\(activeObjectIndex + 1) / \(sculptObjects.count)")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 60)
            }
        }
        .overlay(alignment: .bottomLeading) {
            Image(systemName: isRotateMode ? "rotate.3d.fill" : "rotate.3d")
                .font(.title)
                .foregroundStyle(isRotateMode ? .blue : .secondary)
                .frame(width: 60, height: 60)
                .background(.ultraThinMaterial, in: Circle())
                .padding(20)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isRotateMode = true }
                        .onEnded { _ in isRotateMode = false }
                )
        }
        .onAppear {
            let strokeIDs = Set(strokes.map(\.id))
            if let existing = sculptObjects.first(where: { $0.sourceStrokeIDs == strokeIDs }) {
                activeObjectID = existing.id
                print("[SculptScreen] Loaded saved sculpt object (\(existing.mesh.vertexCount) vertices)")
            } else {
                let obj = ShapeInflater.sculpt(from: strokes, config: config)
                sculptObjects.append(obj)
                activeObjectID = obj.id
                print("[SculptScreen] Created new sculpt object (\(obj.mesh.vertexCount) vertices)")
            }
        }
    }

    private var activeObjectIndex: Int {
        sculptObjects.firstIndex(where: { $0.id == activeObjectID }) ?? 0
    }

    private func cycleActiveObject() {
        guard sculptObjects.count > 1 else { return }
        let nextIdx = (activeObjectIndex + 1) % sculptObjects.count
        activeObjectID = sculptObjects[nextIdx].id
    }
}
