import Foundation

enum SkeletonExtractor {

    /// Extracts the skeleton directly from stroke points (preserves drawn profile detail).
    static func extract(from strokes: [Stroke], sampleCount: Int = 40) -> Skeleton {
        let allPoints = strokes.flatMap { $0.points.map(\.location) }
        return extract(fromPoints: allPoints, sampleCount: sampleCount)
    }

    /// Extracts the medial axis skeleton from a set of 2D points.
    /// Samples cross-sections along the principal axis to find midpoints and radii.
    static func extract(fromPoints points: [CGPoint], sampleCount: Int = 40) -> Skeleton {
        guard points.count >= 3 else {
            return Skeleton(points: [], axis: .zero)
        }

        let c = centroid(of: points)
        let axis = principalAxis(of: points, centroid: c)
        let perp = CGVector(dx: -axis.dy, dy: axis.dx)

        // Project all points onto the principal axis
        let projections = points.map { dot(vector(from: c, to: $0), axis) }
        guard let minProj = projections.min(),
              let maxProj = projections.max(),
              maxProj - minProj > 0 else {
            return Skeleton(points: [], axis: axis)
        }

        let bandWidth = (maxProj - minProj) / CGFloat(sampleCount) * 1.5
        var skeletonPoints: [SkeletonPoint] = []

        for i in 0..<sampleCount {
            let t = CGFloat(i) / CGFloat(sampleCount - 1)
            let proj = minProj + t * (maxProj - minProj)

            // Find points within this band along the axis
            let nearby = points.filter {
                abs(dot(vector(from: c, to: $0), axis) - proj) < bandWidth
            }
            guard nearby.count >= 2 else { continue }

            // Project onto the perpendicular to find cross-section extent
            let perpProjs = nearby.map { dot(vector(from: c, to: $0), perp) }
            guard let minPerp = perpProjs.min(), let maxPerp = perpProjs.max() else { continue }

            let midPerp = (minPerp + maxPerp) / 2
            let radius = (maxPerp - minPerp) / 2

            let position = CGPoint(
                x: c.x + proj * axis.dx + midPerp * perp.dx,
                y: c.y + proj * axis.dy + midPerp * perp.dy
            )
            skeletonPoints.append(SkeletonPoint(position: position, radius: max(radius, 0.1)))
        }

        let smoothed = smooth(skeletonPoints, windowSize: 3)
        return Skeleton(points: smoothed, axis: axis)
    }

    /// Moving average smoothing of skeleton radii to reduce jitter.
    static func smooth(_ points: [SkeletonPoint], windowSize: Int) -> [SkeletonPoint] {
        guard points.count >= windowSize else { return points }
        let half = windowSize / 2
        return points.indices.map { i in
            let lo = max(0, i - half)
            let hi = min(points.count - 1, i + half)
            let window = points[lo...hi]
            let avgRadius = window.map(\.radius).reduce(0, +) / CGFloat(window.count)
            return SkeletonPoint(position: points[i].position, radius: avgRadius)
        }
    }

    // MARK: - Geometry helpers

    static func centroid(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    /// Principal axis via 2D PCA (eigenvector of the covariance matrix with largest eigenvalue).
    static func principalAxis(of points: [CGPoint], centroid c: CGPoint) -> CGVector {
        var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
        for p in points {
            let dx = p.x - c.x
            let dy = p.y - c.y
            sxx += dx * dx
            syy += dy * dy
            sxy += dx * dy
        }
        let theta = atan2(2 * sxy, sxx - syy) / 2
        return CGVector(dx: cos(theta), dy: sin(theta))
    }

    static func dot(_ a: CGVector, _ b: CGVector) -> CGFloat {
        a.dx * b.dx + a.dy * b.dy
    }

    static func vector(from a: CGPoint, to b: CGPoint) -> CGVector {
        CGVector(dx: b.x - a.x, dy: b.y - a.y)
    }
}
