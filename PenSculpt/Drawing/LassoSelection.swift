import Foundation

enum LassoSelection {

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

    /// Returns true if at least `threshold` fraction of the stroke's points
    /// are inside the polygon (default 50%).
    static func isStrokeSelected(
        _ stroke: Stroke,
        by polygon: [CGPoint],
        threshold: CGFloat = 0.5
    ) -> Bool {
        guard !stroke.points.isEmpty else { return false }
        // Quick reject: if bounding boxes don't overlap, skip
        let lassoBounds = boundingBox(of: polygon)
        guard stroke.boundingBox.intersects(lassoBounds) else { return false }

        let insideCount = stroke.points.filter { contains($0.location, in: polygon) }.count
        return CGFloat(insideCount) / CGFloat(stroke.points.count) >= threshold
    }

    /// Returns IDs of all strokes where ≥ threshold of points are inside the polygon.
    static func selectedStrokeIDs(
        strokes: [Stroke],
        polygon: [CGPoint],
        threshold: CGFloat = 0.5
    ) -> Set<UUID> {
        var ids = Set<UUID>()
        for stroke in strokes {
            if isStrokeSelected(stroke, by: polygon, threshold: threshold) {
                ids.insert(stroke.id)
            }
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
