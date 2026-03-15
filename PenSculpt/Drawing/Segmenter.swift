import Foundation

enum Segmenter {

    /// Splits a skeleton into segments at points where curvature exceeds the threshold.
    static func segment(_ skeleton: Skeleton, curvatureThreshold: CGFloat = 0.3) -> [SkeletonSegment] {
        guard skeleton.points.count >= 3 else {
            return skeleton.points.isEmpty ? [] : [SkeletonSegment(points: skeleton.points)]
        }

        var segments: [SkeletonSegment] = []
        var current: [SkeletonPoint] = [skeleton.points[0]]

        for i in 1..<(skeleton.points.count - 1) {
            let prev = skeleton.points[i - 1].position
            let curr = skeleton.points[i].position
            let next = skeleton.points[i + 1].position

            current.append(skeleton.points[i])

            if abs(curvature(prev, curr, next)) > curvatureThreshold {
                segments.append(SkeletonSegment(points: current))
                current = [skeleton.points[i]]
            }
        }

        current.append(skeleton.points[skeleton.points.count - 1])
        segments.append(SkeletonSegment(points: current))

        return segments
    }

    /// Signed angle between vectors (prev→curr) and (curr→next).
    static func curvature(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        let v1 = CGVector(dx: b.x - a.x, dy: b.y - a.y)
        let v2 = CGVector(dx: c.x - b.x, dy: c.y - b.y)
        let cross = v1.dx * v2.dy - v1.dy * v2.dx
        let dot = v1.dx * v2.dx + v1.dy * v2.dy
        return atan2(cross, dot)
    }
}
