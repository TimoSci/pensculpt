import Foundation
import simd

enum MeshAssembler {

    /// Generates a 3D mesh by revolving the skeleton segment's radius profile around its axis.
    static func assemble(from primitive: FittedPrimitive, radialSegments: Int = 24) -> Mesh {
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

        let totalLength = distances.last!
        let yOffset = totalLength / 2

        var vertices: [MeshVertex] = []
        var faces: [MeshFace] = []

        let n = radialSegments

        // Bottom cap vertex (center point at the bottom)
        let bottomY = -(distances[0] - yOffset)
        vertices.append(MeshVertex(position: SIMD3(0, bottomY, 0), normal: SIMD3(0, -1, 0)))
        let bottomCapIdx = UInt32(0)

        // Generate rings
        for (ringIdx, skelPoint) in points.enumerated() {
            // Negate Y so the shape matches screen orientation (top=top)
            let y = -(distances[ringIdx] - yOffset)
            let radius = Float(skelPoint.radius)
            let slope = profileSlope(at: ringIdx, points: points, distances: distances)

            for seg in 0..<n {
                let angle = Float(seg) / Float(n) * 2 * .pi
                let cosA = cos(angle)
                let sinA = sin(angle)
                let position = SIMD3<Float>(radius * cosA, y, radius * sinA)
                let normal = normalize(SIMD3<Float>(cosA, slope, sinA))
                vertices.append(MeshVertex(position: position, normal: normal))
            }

            // Connect to previous ring
            if ringIdx > 0 {
                let prevRing = UInt32(1 + (ringIdx - 1) * n) // +1 for bottom cap vertex
                let currRing = UInt32(1 + ringIdx * n)
                for seg in 0..<UInt32(n) {
                    let next = (seg + 1) % UInt32(n)
                    faces.append(MeshFace(indices: SIMD3(prevRing + seg, currRing + next, currRing + seg)))
                    faces.append(MeshFace(indices: SIMD3(prevRing + seg, prevRing + next, currRing + next)))
                }
            }
        }

        // Top cap vertex (center point at the top)
        let topY = -(distances[points.count - 1] - yOffset)
        vertices.append(MeshVertex(position: SIMD3(0, topY, 0), normal: SIMD3(0, 1, 0)))
        let topCapIdx = UInt32(vertices.count - 1)

        // Bottom cap faces (fan from center to first ring)
        let firstRing = UInt32(1)
        for seg in 0..<UInt32(n) {
            let next = (seg + 1) % UInt32(n)
            faces.append(MeshFace(indices: SIMD3(bottomCapIdx, firstRing + seg, firstRing + next)))
        }

        // Top cap faces (fan from center to last ring)
        let lastRing = UInt32(1 + (points.count - 1) * n)
        for seg in 0..<UInt32(n) {
            let next = (seg + 1) % UInt32(n)
            faces.append(MeshFace(indices: SIMD3(topCapIdx, lastRing + next, lastRing + seg)))
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
