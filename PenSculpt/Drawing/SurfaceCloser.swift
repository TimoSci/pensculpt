import Foundation

enum SurfaceCloser {

    /// Ensures the skeleton produces a closed surface with smooth caps.
    static func close(_ skeleton: Skeleton, config: SculptConfig = .default) -> Skeleton {
        guard skeleton.points.count >= 2 else { return skeleton }
        var points = skeleton.points

        points = closeEnd(points, atStart: true, config: config)
        points = closeEnd(points, atStart: false, config: config)

        return Skeleton(points: points, axis: skeleton.axis)
    }

    // MARK: - End closing

    /// Adds a hemispherical cap at one end of the skeleton.
    /// Uses the end radius as the cap radius for a proper hemisphere shape.
    private static func closeEnd(_ points: [SkeletonPoint], atStart: Bool, config: SculptConfig) -> [SkeletonPoint] {
        var result = points
        let idx = atStart ? 0 : result.count - 1
        let neighborIdx = atStart ? 1 : result.count - 2
        let endPoint = result[idx]
        let neighbor = result[neighborIdx]

        let endRadius = endPoint.radius
        guard endRadius > 1 else { return result }

        // Hemispherical cap: distance = radius, so the profile traces a quarter circle
        let capRadius = endRadius
        let steps = max(8, Int(capRadius / 5)) // ~1 step per 5 points for smooth curvature

        let dx = endPoint.position.x - neighbor.position.x
        let dy = endPoint.position.y - neighbor.position.y
        let len = hypot(dx, dy)
        guard len > 0 else { return result }
        let ux = dx / len, uy = dy / len

        var capPoints: [SkeletonPoint] = []
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let angle = t * .pi / 2
            let r = endRadius * cos(angle)
            let d = capRadius * sin(angle)
            let pos = CGPoint(
                x: endPoint.position.x + ux * d,
                y: endPoint.position.y + uy * d
            )
            capPoints.append(SkeletonPoint(position: pos, radius: max(r, 0.1)))
        }

        if atStart {
            result.insert(contentsOf: capPoints.reversed(), at: 0)
        } else {
            result.append(contentsOf: capPoints)
        }

        return result
    }

    // MARK: - Curvature enforcement

    /// Smooths the radius profile to enforce minimum curvature radius on the entire surface.
    /// Limits both increases and decreases in radius between adjacent samples.
    static func enforceCurvature(_ points: [SkeletonPoint], config: SculptConfig) -> [SkeletonPoint] {
        guard points.count >= 3 else { return points }
        var result = points

        let totalLength = cumulativeLength(result)
        guard totalLength > 0 else { return result }
        let avgSpacing = totalLength / CGFloat(result.count - 1)
        let maxDelta = avgSpacing / max(config.minCurvatureRadius / avgSpacing, 1)

        // Iterative constrained smoothing — enough passes to propagate across the full profile
        let passes = max(10, result.count / 4)
        for _ in 0..<passes {
            // Forward pass: limit both increase and decrease rate
            for i in 1..<result.count {
                let prevR = result[i - 1].radius
                let currR = result[i].radius
                let clamped = min(max(currR, prevR - maxDelta), prevR + maxDelta)
                if clamped != currR {
                    result[i] = SkeletonPoint(position: result[i].position,
                                               radius: max(clamped, 0.1))
                }
            }
            // Backward pass: same constraint from the other direction
            for i in stride(from: result.count - 2, through: 0, by: -1) {
                let nextR = result[i + 1].radius
                let currR = result[i].radius
                let clamped = min(max(currR, nextR - maxDelta), nextR + maxDelta)
                if clamped != currR {
                    result[i] = SkeletonPoint(position: result[i].position,
                                               radius: max(clamped, 0.1))
                }
            }
        }

        return result
    }

    private static func cumulativeLength(_ points: [SkeletonPoint]) -> CGFloat {
        var length: CGFloat = 0
        for i in 1..<points.count {
            let dx = points[i].position.x - points[i - 1].position.x
            let dy = points[i].position.y - points[i - 1].position.y
            length += hypot(dx, dy)
        }
        return length
    }
}
