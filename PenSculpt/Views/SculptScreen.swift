import SwiftUI

struct SculptScreen: View {
    var strokes: [Stroke]
    @Binding var sculptObjects: [SculptObject]
    var config: SculptConfig = .default
    @State private var activeObjectID: UUID?
    @State private var isRotateMode = false
    @State private var isDeformMode = false
    @State private var brushSize: CGFloat = 8
    @State private var brushOpacity: CGFloat = 1
    @State private var deformCursor: (position: CGPoint, radius: CGFloat)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MetalCanvasView(
            sculptObjects: sculptObjects,
            activeObjectID: activeObjectID,
            config: config,
            isRotateMode: isRotateMode,
            isDeformMode: isDeformMode,
            brushSize: Float(brushSize),
            brushOpacity: Float(brushOpacity),
            onObjectTapped: cycleActiveObject,
            onSurfaceStrokeCompleted: handleSurfaceStroke,
            onMeshDeformed: handleMeshDeformed,
            onDeformCursor: { deformCursor = $0 }
        )
        .ignoresSafeArea()
        .overlay {
            if let cursor = deformCursor {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: cursor.radius * 2, height: cursor.radius * 2)
                    .position(cursor.position)
                    .allowsHitTesting(false)
            }
        }
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
        .overlay(alignment: .bottom) {
            VStack(spacing: 12) {
                BrushControls(brushSize: $brushSize, brushOpacity: $brushOpacity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

                HStack(spacing: 12) {
                    Image(systemName: isRotateMode ? "rotate.3d.fill" : "rotate.3d")
                        .font(.title)
                        .foregroundStyle(isRotateMode ? .blue : .secondary)
                        .frame(width: 60, height: 60)
                        .background(.ultraThinMaterial, in: Circle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in isRotateMode = true }
                                .onEnded { _ in isRotateMode = false }
                        )

                    Button {
                        isDeformMode.toggle()
                    } label: {
                        Image(systemName: isDeformMode ? "hand.point.up.fill" : "hand.point.up")
                            .font(.title)
                            .foregroundStyle(isDeformMode ? .orange : .secondary)
                            .frame(width: 60, height: 60)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            let strokeIDs = Set(strokes.map(\.id))
            if let existing = sculptObjects.first(where: { $0.sourceStrokeIDs == strokeIDs }) {
                activeObjectID = existing.id
            } else {
                let obj = ShapeInflater.sculpt(from: strokes, config: config)
                sculptObjects.append(obj)
                activeObjectID = obj.id
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

    private func handleSurfaceStroke(_ stroke: SurfaceStroke) {
        guard activeObjectIndex < sculptObjects.count else { return }
        sculptObjects[activeObjectIndex].surfaceStrokes.append(stroke)
    }

    private func handleMeshDeformed(_ objectID: UUID, _ mesh: Mesh) {
        guard let idx = sculptObjects.firstIndex(where: { $0.id == objectID }) else { return }
        sculptObjects[idx].mesh = mesh
    }
}
