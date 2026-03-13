import PencilKit

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

        return Stroke(points: points, color: .black)
    }

    static func convertAll(_ drawing: PKDrawing) -> [Stroke] {
        drawing.strokes.map { convert($0) }
    }
}
