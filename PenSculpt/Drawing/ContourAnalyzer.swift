import Foundation

enum ContourAnalyzer {

    /// Extracts the convex hull contour from a set of strokes.
    static func extractContour(from strokes: [Stroke]) -> [CGPoint] {
        let points = strokes.flatMap { $0.points.map(\.location) }
        return convexHull(points)
    }

    /// Graham scan convex hull — returns points in counter-clockwise order.
    static func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 3 else { return points }

        // Find the bottom-most point (leftmost if tied)
        guard let pivot = points.min(by: {
            $0.y < $1.y || ($0.y == $1.y && $0.x < $1.x)
        }) else { return points }

        // Sort by polar angle relative to pivot
        let sorted = points.sorted { a, b in
            let angleA = atan2(a.y - pivot.y, a.x - pivot.x)
            let angleB = atan2(b.y - pivot.y, b.x - pivot.x)
            if abs(angleA - angleB) > 1e-10 { return angleA < angleB }
            return distSq(pivot, a) < distSq(pivot, b)
        }

        // Build hull using a stack
        var hull: [CGPoint] = []
        for point in sorted {
            while hull.count >= 2 && cross(hull[hull.count - 2], hull[hull.count - 1], point) <= 0 {
                hull.removeLast()
            }
            hull.append(point)
        }
        return hull
    }

    /// Cross product of vectors (o→a) × (o→b). Positive = counter-clockwise turn.
    static func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }

    private static func distSq(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }
}
