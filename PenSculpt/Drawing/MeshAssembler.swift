import Foundation
import simd

enum MeshAssembler {

    /// Generates a 3D mesh by revolving the skeleton segment's radius profile around its axis.
    static func assemble(from primitive: FittedPrimitive, radialSegments: Int = 16) -> Mesh {
        let points = primitive.segment.points
        guard points.count >= 2 else { return Mesh() }

        // Compute cumulative distance along the skeleton → Y axis in 3D
        var distances: [Float] = [0]
        for i in 1..<points.count {
            let prev = points[i - 1].position
            let curr = points[i].position
            let dist = hypot(Float(curr.x - prev.x), Float(curr.y - prev.y))
            distances.append(distances[i - 1] + dist)
        }

        // Center vertically
        let totalLength = distances.last!
        let yOffset = totalLength / 2

        var vertices: [MeshVertex] = []
        var faces: [MeshFace] = []

        let n = radialSegments

        for (ringIdx, skelPoint) in points.enumerated() {
            let y = distances[ringIdx] - yOffset
            let radius = Float(skelPoint.radius)

            // Compute profile slope for normals
            let slope = profileSlope(at: ringIdx, points: points, distances: distances)

            for seg in 0..<n {
                let angle = Float(seg) / Float(n) * 2 * .pi
                let cosA = cos(angle)
                let sinA = sin(angle)
                let position = SIMD3<Float>(radius * cosA, y, radius * sinA)
                let normal = normalize(SIMD3<Float>(cosA, -slope, sinA))
                vertices.append(MeshVertex(position: position, normal: normal))
            }

            // Connect to previous ring with triangle strip
            if ringIdx > 0 {
                let prev = UInt32((ringIdx - 1) * n)
                let curr = UInt32(ringIdx * n)
                for seg in 0..<UInt32(n) {
                    let next = (seg + 1) % UInt32(n)
                    faces.append(MeshFace(indices: SIMD3(prev + seg, curr + seg, curr + next)))
                    faces.append(MeshFace(indices: SIMD3(prev + seg, curr + next, prev + next)))
                }
            }
        }

        return Mesh(vertices: vertices, faces: faces)
    }

    /// Profile slope (dRadius/dDistance) for computing surface normals.
    private static func profileSlope(
        at index: Int,
        points: [SkeletonPoint],
        distances: [Float]
    ) -> Float {
        if index == 0 && points.count > 1 {
            let dr = Float(points[1].radius - points[0].radius)
            let dd = distances[1] - distances[0]
            return dd > 0 ? dr / dd : 0
        } else if index == points.count - 1 && points.count > 1 {
            let dr = Float(points[index].radius - points[index - 1].radius)
            let dd = distances[index] - distances[index - 1]
            return dd > 0 ? dr / dd : 0
        } else if index > 0 && index < points.count - 1 {
            let dr = Float(points[index + 1].radius - points[index - 1].radius)
            let dd = distances[index + 1] - distances[index - 1]
            return dd > 0 ? dr / dd : 0
        }
        return 0
    }
}
