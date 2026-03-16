import SwiftUI
import MetalKit

struct MetalCanvasView: UIViewRepresentable {
    var strokes: [Stroke]
    var sculptObjects: [SculptObject]
    var activeObjectID: UUID?
    var config: SculptConfig = .default
    var isRotateMode: Bool = false
    var onObjectTapped: (() -> Void)?

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
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {
        var renderer: SculptRenderer?
        var isRotateMode = false
        var onObjectTapped: (() -> Void)?

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let renderer = renderer else { return }
            let translation = gesture.translation(in: gesture.view)
            renderer.rotate(dx: Float(translation.x), dy: Float(translation.y))
            gesture.setTranslation(.zero, in: gesture.view)
        }

        @objc func handleSinglePan(_ gesture: UIPanGestureRecognizer) {
            guard isRotateMode, let renderer = renderer else { return }
            let translation = gesture.translation(in: gesture.view)
            renderer.rotate(dx: Float(translation.x), dy: Float(translation.y))
            gesture.setTranslation(.zero, in: gesture.view)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            onObjectTapped?()
        }
    }
}
