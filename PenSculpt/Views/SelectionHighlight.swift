import SwiftUI
import UIKit

struct SelectionHighlight: UIViewRepresentable {
    var strokes: [Stroke]
    var selectedIDs: Set<UUID>
    var viewBridge: ViewBridge?

    func makeUIView(context: Context) -> SelectionHighlightView {
        let view = SelectionHighlightView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: SelectionHighlightView, context: Context) {
        uiView.selectedStrokes = strokes.filter { selectedIDs.contains($0.id) }
        uiView.canvasView = viewBridge?.canvasView
        uiView.setNeedsDisplay()
    }
}

class SelectionHighlightView: UIView {
    var selectedStrokes: [Stroke] = []
    weak var canvasView: UIView?

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(6)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for stroke in selectedStrokes {
            guard stroke.points.count > 1 else { continue }
            ctx.beginPath()
            ctx.move(to: convertFromCanvas(stroke.points[0].location))
            for point in stroke.points.dropFirst() {
                ctx.addLine(to: convertFromCanvas(point.location))
            }
            ctx.strokePath()
        }
    }

    /// Converts a point from PKCanvasView coordinates to this view's coordinates.
    private func convertFromCanvas(_ point: CGPoint) -> CGPoint {
        guard let canvas = canvasView else { return point }
        return canvas.convert(point, to: self)
    }
}
