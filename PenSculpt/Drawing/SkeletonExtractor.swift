import Foundation

enum SkeletonExtractor {

    /// Extracts the medial axis skeleton from a contour polygon.
    /// Samples cross-sections along the principal axis to find midpoints and radii.
    static func extract(from contour: [CGPoint], sampleCount: Int = 20) -> Skeleton {
        guard contour.count >= 3 else {
            return Skeleton(points: [], axis: .zero)
        }

        let centroid = centroid(of: contour)
        let axis = principalAxis(of: contour, centroid: centroid)
        let perp = CGVector(dx: -axis.dy, dy: axis.dx)

        // Project contour points onto the principal axis
        let projections = contour.map { dot(vector(from: centroid, to: $0), axis) }
        guard let minProj = projections.min(),
              let maxProj = projections.max(),
              maxProj - minProj > 0 else {
            return Skeleton(points: [], axis: axis)
        }

        let bandWidth = (maxProj - minProj) / CGFloat(sampleCount)
        var skeletonPoints: [SkeletonPoint] = []

        for i in 0..<sampleCount {
            let t = CGFloat(i) / CGFloat(sampleCount - 1)
            let proj = minProj + t * (maxProj - minProj)

            // Find contour points within this band along the axis
            let nearby = contour.filter {
                abs(dot(vector(from: centroid, to: $0), axis) - proj) < bandWidth
            }
            guard !nearby.isEmpty else { continue }

            // Project onto the perpendicular to find cross-section extent
            let perpProjs = nearby.map { dot(vector(from: centroid, to: $0), perp) }
            guard let minPerp = perpProjs.min(), let maxPerp = perpProjs.max() else { continue }

            let midPerp = (minPerp + maxPerp) / 2
            let radius = (maxPerp - minPerp) / 2

            let position = CGPoint(
                x: centroid.x + proj * axis.dx + midPerp * perp.dx,
                y: centroid.y + proj * axis.dy + midPerp * perp.dy
            )
            skeletonPoints.append(SkeletonPoint(position: position, radius: max(radius, 0.1)))
        }

        return Skeleton(points: skeletonPoints, axis: axis)
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
