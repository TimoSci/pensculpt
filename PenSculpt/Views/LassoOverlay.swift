import SwiftUI
import UIKit

struct LassoOverlay: UIViewRepresentable {
    @Binding var lassoPoints: [CGPoint]
    var onLassoCompleted: ([CGPoint]) -> Void
    var viewBridge: ViewBridge?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> LassoView {
        let view = LassoView()
        view.backgroundColor = .clear
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: LassoView, context: Context) {
        context.coordinator.parent = self
        // Keep the target reference up to date
        uiView.targetView = viewBridge?.canvasView
        if lassoPoints.isEmpty && !uiView.displayPoints.isEmpty {
            uiView.clearLasso()
        }
    }

    class Coordinator {
        var parent: LassoOverlay
        init(_ parent: LassoOverlay) { self.parent = parent }
    }
}

class LassoView: UIView {
    var coordinator: LassoOverlay.Coordinator?
    /// Points in this view's coordinates — used for rendering the lasso path.
    var displayPoints: [CGPoint] = []
    /// Points in the target view's coordinates — used for hit-testing.
    private var hitTestPoints: [CGPoint] = []
    /// The PKCanvasView to convert touch coordinates into.
    weak var targetView: UIView?
    private var isClosed = false

    func clearLasso() {
        displayPoints = []
        hitTestPoints = []
        isClosed = false
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        if isClosed {
            displayPoints = []
            hitTestPoints = []
            isClosed = false
        }
        let selfPoint = touch.location(in: self)
        let targetPoint = targetView.map { touch.location(in: $0) } ?? selfPoint
        displayPoints = [selfPoint]
        hitTestPoints = [targetPoint]
        coordinator?.parent.lassoPoints = displayPoints
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let selfPoint = touch.location(in: self)
        let targetPoint = targetView.map { touch.location(in: $0) } ?? selfPoint
        displayPoints.append(selfPoint)
        hitTestPoints.append(targetPoint)
        coordinator?.parent.lassoPoints = displayPoints
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if displayPoints.count > 2 {
            displayPoints.append(displayPoints[0])
            hitTestPoints.append(hitTestPoints[0])
            isClosed = true
            coordinator?.parent.lassoPoints = displayPoints
            // Pass canvas-coordinate points for hit-testing
            coordinator?.parent.onLassoCompleted(hitTestPoints)
        } else {
            displayPoints = []
            hitTestPoints = []
            coordinator?.parent.lassoPoints = displayPoints
        }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard displayPoints.count > 1, let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(2)
        ctx.setLineDash(phase: 0, lengths: [8, 4])
        ctx.beginPath()
        ctx.move(to: displayPoints[0])
        for point in displayPoints.dropFirst() {
            ctx.addLine(to: point)
        }
        ctx.strokePath()
    }
}
