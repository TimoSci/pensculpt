import SwiftUI
import MetalKit

struct MetalCanvasView: UIViewRepresentable {
    var strokes: [Stroke]
    var sculptObjects: [SculptObject]
    var activeObjectID: UUID?
    var config: SculptConfig = .default
    var isRotateMode: Bool = false
    var onObjectTapped: (() -> Void)?
    var onSurfaceStrokeCompleted: ((SurfaceStroke) -> Void)?

    func makeUIView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        let view = MTKView(frame: .zero, device: device)
        view.clearColor = MTLClearColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1)
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.depthStencilPixelFormat = .depth32Float

        let renderer = SculptRenderer(device: device)
        context.coordinator.renderer = renderer
        view.delegate = renderer

        let panGesture = UIPanGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.handlePan(_:)))
        panGesture.minimumNumberOfTouches = 2
        panGesture.maximumNumberOfTouches = 2
        view.addGestureRecognizer(panGesture)

        let tapGesture = UITapGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tapGesture)

        let singlePan = UIPanGestureRecognizer(target: context.coordinator,
                                                action: #selector(Coordinator.handleSinglePan(_:)))
        singlePan.minimumNumberOfTouches = 1
        singlePan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(singlePan)

        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.renderer?.strokes = strokes
        context.coordinator.renderer?.sculptObjects = sculptObjects
        context.coordinator.renderer?.activeObjectID = activeObjectID
        context.coordinator.renderer?.config = config
        context.coordinator.isRotateMode = isRotateMode
        context.coordinator.onObjectTapped = onObjectTapped
        context.coordinator.onSurfaceStrokeCompleted = onSurfaceStrokeCompleted
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {
        var renderer: SculptRenderer?
        var isRotateMode = false
        var onObjectTapped: (() -> Void)?
        var onSurfaceStrokeCompleted: ((SurfaceStroke) -> Void)?

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let renderer = renderer else { return }
            let translation = gesture.translation(in: gesture.view)
            renderer.rotate(dx: Float(translation.x), dy: Float(translation.y))
            gesture.setTranslation(.zero, in: gesture.view)
        }

        @objc func handleSinglePan(_ gesture: UIPanGestureRecognizer) {
            guard let renderer = renderer else { return }

            if isRotateMode {
                let translation = gesture.translation(in: gesture.view)
                renderer.rotate(dx: Float(translation.x), dy: Float(translation.y))
                gesture.setTranslation(.zero, in: gesture.view)
            } else {
                let location = gesture.location(in: gesture.view)
                let viewSize = gesture.view?.bounds.size ?? .zero

                switch gesture.state {
                case .began, .changed:
                    if let result = renderer.hitTest(screenPoint: location, viewSize: viewSize) {
                        // Reject points that jump to a different surface (t discontinuity)
                        let isFirst = renderer.currentStrokePoints.isEmpty
                        let tContinuous = isFirst || abs(result.t - renderer.lastHitT) < renderer.config.surfaceStrokeMaxTJump
                        if tContinuous {
                            renderer.currentStrokePoints.append(result.point)
                            renderer.currentStrokeDiag.append((screen: location, t: result.t, hit: result.point))
                            renderer.lastHitT = result.t
                        } else {
                            renderer.rejectedCount += 1
                        }
                    } else {
                        renderer.missCount += 1
                    }
                case .ended, .cancelled:
                    if renderer.currentStrokePoints.count > 1 {
                        // Diagnostic: dump first 10 points
                        let diag = renderer.currentStrokeDiag
                        print("[Draw] --- Stroke \(diag.count) pts ---")
                        for i in 0..<min(10, diag.count) {
                            let d = diag[i]
                            let jump = i > 0 ? simd_length(diag[i].hit - diag[i-1].hit) : Float(0)
                            print("  [\(i)] screen(\(String(format: "%.0f", d.screen.x)),\(String(format: "%.0f", d.screen.y))) t=\(String(format: "%.1f", d.t)) hit(\(String(format: "%.1f", d.hit.x)),\(String(format: "%.1f", d.hit.y)),\(String(format: "%.1f", d.hit.z)) jump=\(String(format: "%.1f", jump))")
                        }
                        if diag.count > 10 { print("  ... (\(diag.count - 10) more)") }
                        print("[Draw] rejected: \(renderer.rejectedCount), missed: \(renderer.missCount)")

                        let stroke = SurfaceStroke(points: renderer.currentStrokePoints)
                        // Update renderer directly for immediate rendering
                        if let activeID = renderer.activeObjectID,
                           let idx = renderer.sculptObjects.firstIndex(where: { $0.id == activeID }) {
                            renderer.sculptObjects[idx].surfaceStrokes.append(stroke)
                        }
                        // Save to document via SwiftUI binding
                        onSurfaceStrokeCompleted?(stroke)
                    }
                    renderer.currentStrokePoints.removeAll()
                    renderer.currentStrokeDiag.removeAll()
                    renderer.lastHitT = 0
                    renderer.rejectedCount = 0
                    renderer.missCount = 0
                default:
                    break
                }
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            onObjectTapped?()
        }
    }
}
