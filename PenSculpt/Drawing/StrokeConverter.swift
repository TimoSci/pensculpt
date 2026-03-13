import PencilKit
import UIKit

enum StrokeConverter {

    static func convert(_ pkStroke: PKStroke) -> Stroke {
        let path = pkStroke.path
        var points: [StrokePoint] = []
        points.reserveCapacity(path.count)

        for i in 0..<path.count {
            let p = path[i]
            points.append(StrokePoint(
                location: p.location,
                pressure: p.force,
                tilt: p.altitude,
                azimuth: p.azimuth,
                timestamp: p.timeOffset
            ))
        }

        let color = colorFromPKInk(pkStroke.ink)
        return Stroke(points: points, color: color)
    }

    static func convertAll(_ drawing: PKDrawing) -> [Stroke] {
        drawing.strokes.map { convert($0) }
    }

    private static func colorFromPKInk(_ ink: PKInk) -> CodableColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ink.color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return CodableColor(red: r, green: g, blue: b, alpha: a)
    }
}
