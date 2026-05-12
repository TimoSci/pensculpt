import Foundation

enum LassoStrategy: SelectionStrategy {
    typealias Input = [CGPoint]  // polygon

    /// Ray-casting point-in-polygon test.
    static func contains(_ point: CGPoint, in polygon: [CGPoint]) -> Bool {
        guard polygon.count > 2 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]
            if (pi.y > point.y) != (pj.y > point.y),
               point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Returns true if any point of the stroke is inside the polygon.
    /// Matches the inclusive behavior of Apple Notes and Procreate, where any
    /// overlap admits the stroke (a 50% threshold previously dropped strokes
    /// the user clearly meant to select).
    static func isStrokeSelected(_ stroke: Stroke, by polygon: [CGPoint]) -> Bool {
        guard !stroke.points.isEmpty else { return false }
        let lassoBounds = boundingBox(of: polygon)
        guard stroke.boundingBox.intersects(lassoBounds) else { return false }
        return stroke.points.contains { contains($0.location, in: polygon) }
    }

    /// Returns IDs of all strokes with at least one point inside the polygon.
    static func selectedStrokeIDs(strokes: [Stroke], polygon: [CGPoint]) -> Set<UUID> {
        var ids = Set<UUID>()
        for stroke in strokes where isStrokeSelected(stroke, by: polygon) {
            ids.insert(stroke.id)
        }
        return ids
    }

    private static func boundingBox(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
