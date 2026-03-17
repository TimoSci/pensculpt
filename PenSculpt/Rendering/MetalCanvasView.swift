import SwiftUI
import MetalKit

/// MTKView subclass that captures Apple Pencil force from touch events.
class ForceMTKView: MTKView {
    var currentForce: CGFloat = 0
    var maximumForce: CGFloat = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        updateForce(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        updateForce(touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        currentForce = 0
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        currentForce = 0
    }

    private func updateForce(_ touches: Set<UITouch>) {
        guard let touch = touches.first, touch.maximumPossibleForce > 0 else { return }
        currentForce = touch.force
        maximumForce = touch.maximumPossibleForce
    }
}

struct MetalCanvasView: UIViewRepresentable {
    var sculptObjects: [SculptObject]
    var activeObjectID: UUID?
    var config: SculptConfig = .default
    var isRotateMode: Bool = false
    var isDeformMode: Bool = false
    var brushSize: Float = 8
    var brushOpacity: Float = 1
    var onObjectTapped: (() -> Void)?
    var onSurfaceStrokeCompleted: ((SurfaceStroke) -> Void)?
    var onMeshDeformed: ((UUID, Mesh, [SurfaceStroke]) -> Void)?
    var onDeformCursor: (((position: CGPoint, radius: CGFloat)?) -> Void)?
    var onRendererReady: ((@escaping (UUID, Mesh, [SurfaceStroke]?) -> Void) -> Void)?

    func makeUIView(context: Context) -> ForceMTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        let view = ForceMTKView(frame: .zero, device: device)
        view.clearColor = MTLClearColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1)
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.depthStencilPixelFormat = .depth32Float
        view.isMultipleTouchEnabled = true

        let renderer = SculptRenderer(device: device)
        context.coordinator.renderer = renderer
        view.delegate = renderer

        onRendererReady? { [weak renderer] objectID, newMesh, newStrokes in
            renderer?.replaceMesh(objectID: objectID, mesh: newMesh, surfaceStrokes: newStrokes)
        }

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
        singlePan.cancelsTouchesInView = false
        view.addGestureRecognizer(singlePan)

        return view
    }

    func updateUIView(_ uiView: ForceMTKView, context: Context) {
        if !context.coordinator.isCurrentlyDeforming {
            context.coordinator.renderer?.sculptObjects = sculptObjects
        }
        context.coordinator.renderer?.activeObjectID = activeObjectID
        context.coordinator.renderer?.config = config
        context.coordinator.isRotateMode = isRotateMode
        context.coordinator.isDeformMode = isDeformMode
        context.coordinator.brushSize = brushSize
        context.coordinator.brushOpacity = brushOpacity
        context.coordinator.renderer?.brushOpacity = brushOpacity
        context.coordinator.onObjectTapped = onObjectTapped
        context.coordinator.onSurfaceStrokeCompleted = onSurfaceStrokeCompleted
        context.coordinator.onMeshDeformed = onMeshDeformed
        context.coordinator.onDeformCursor = onDeformCursor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {
        var renderer: SculptRenderer?
        var isRotateMode = false
        var isDeformMode = false
        var brushSize: Float = 8
        var brushOpacity: Float = 1
        var onObjectTapped: (() -> Void)?
        var onSurfaceStrokeCompleted: ((SurfaceStroke) -> Void)?
        var onMeshDeformed: ((UUID, Mesh, [SurfaceStroke]) -> Void)?
        var onDeformCursor: (((position: CGPoint, radius: CGFloat)?) -> Void)?
        var isCurrentlyDeforming = false

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            applyRotation(gesture)
        }

        @objc func handleSinglePan(_ gesture: UIPanGestureRecognizer) {
            if isRotateMode {
                applyRotation(gesture)
            } else if isDeformMode {
                handleDeform(gesture)
            } else {
                handleDraw(gesture)
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            onObjectTapped?()
        }

        private func applyRotation(_ gesture: UIPanGestureRecognizer) {
            guard let renderer = renderer else { return }
            let translation = gesture.translation(in: gesture.view)
            renderer.rotate(dx: Float(translation.x), dy: Float(translation.y))
            gesture.setTranslation(.zero, in: gesture.view)
        }

        private func handleDeform(_ gesture: UIPanGestureRecognizer) {
            guard let renderer = renderer else { return }
            let location = gesture.location(in: gesture.view)
            let viewSize = gesture.view?.bounds.size ?? .zero
            let sliderT = (brushSize - 1) / 19  // normalize 1...20 to 0...1
            let worldRadius = renderer.config.deformRadiusMin + sliderT * (renderer.config.deformRadiusMax - renderer.config.deformRadiusMin)

            if gesture.state == .began || gesture.state == .changed {
                isCurrentlyDeforming = true
                let velocity = gesture.velocity(in: gesture.view)
                let speed = Float(hypot(velocity.x, velocity.y))
                let config = renderer.config
                let t = min(speed / config.deformMaxSpeed, 1.0)
                let strength = config.deformMinStrength + t * (config.deformMaxStrength - config.deformMinStrength)
                renderer.deformMesh(at: location, viewSize: viewSize, strength: strength,
                                     radius: worldRadius, screenVelocity: velocity)

                let screenRadius = CGFloat(worldRadius) * viewSize.height / CGFloat(2 * renderer.combinedRadius)
                onDeformCursor?((position: location, radius: screenRadius))
            } else if gesture.state == .ended || gesture.state == .cancelled {
                isCurrentlyDeforming = false
                onDeformCursor?(nil)
                if let activeID = renderer.activeObjectID,
                   let idx = renderer.sculptObjects.firstIndex(where: { $0.id == activeID }) {
                    let obj = renderer.sculptObjects[idx]
                    onMeshDeformed?(activeID, obj.mesh, obj.surfaceStrokes)
                }
            }
        }

        private func handleDraw(_ gesture: UIPanGestureRecognizer) {
            guard let renderer = renderer else { return }
            let location = gesture.location(in: gesture.view)
            let viewSize = gesture.view?.bounds.size ?? .zero

            if gesture.state == .began || gesture.state == .changed {
                if let result = renderer.hitTest(screenPoint: location, viewSize: viewSize),
                   renderer.isTContinuous(result.t) {
                    renderer.currentStrokePoints.append(result.point)
                    renderer.currentStrokeWidths.append(pressureWidth(from: gesture))
                    renderer.lastHitT = result.t
                }
            } else if gesture.state == .ended || gesture.state == .cancelled {
                if renderer.currentStrokePoints.count > 1 {
                    let stroke = SurfaceStroke(points: renderer.currentStrokePoints,
                                                widths: renderer.currentStrokeWidths)
                    if let activeID = renderer.activeObjectID,
                       let idx = renderer.sculptObjects.firstIndex(where: { $0.id == activeID }) {
                        renderer.sculptObjects[idx].surfaceStrokes.append(stroke)
                    }
                    onSurfaceStrokeCompleted?(stroke)
                }
                renderer.currentStrokePoints.removeAll()
                renderer.currentStrokeWidths.removeAll()
                renderer.lastHitT = 0
            }
        }

        private func pressureWidth(from gesture: UIPanGestureRecognizer) -> Float {
            guard let forceView = gesture.view as? ForceMTKView,
                  forceView.maximumForce > 0 else {
                return brushSize
            }
            let normalized = Float(forceView.currentForce / forceView.maximumForce)
            return brushSize * (0.05 + 0.95 * normalized)
        }
    }
}
