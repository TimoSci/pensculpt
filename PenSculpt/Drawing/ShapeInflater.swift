import Foundation
import simd

enum ShapeInflater {

    /// Inflates a 2D contour into a closed 3D mesh by using edge distance as depth.
    static func inflate(strokes: [Stroke], config: SculptConfig = .default) -> Mesh {
        let gridSpacing = config.gridSpacing
        let allPoints = strokes.flatMap { $0.points.map(\.location) }
        let contour = ContourExtractor.extract(from: strokes, config: config)
        guard contour.count >= 3 else { return Mesh() }

        // Bounding box with padding
        let xs = allPoints.map(\.x), ys = allPoints.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return Mesh() }
        let pad = gridSpacing * 2
        let x0 = minX - pad, y0 = minY - pad
        let x1 = maxX + pad, y1 = maxY + pad

        let cols = max(2, Int((x1 - x0) / gridSpacing))
        let rows = max(2, Int((y1 - y0) / gridSpacing))

        // Compute distance field: distance to nearest contour edge for interior points
        var depths = [[Float]](repeating: [Float](repeating: 0, count: cols), count: rows)
        var maxDist: Float = 0

        for row in 0..<rows {
            for col in 0..<cols {
                let p = CGPoint(x: x0 + CGFloat(col) * gridSpacing, y: y0 + CGFloat(row) * gridSpacing)
                if LassoSelection.contains(p, in: contour) {
                    let dist = Float(distanceToEdge(p, contour: contour))
                    depths[row][col] = dist
                    maxDist = max(maxDist, dist)
                }
            }
        }

        guard maxDist > 0 else { return Mesh() }

        // Convert distance to depth using a sphere-like profile:
        // depth = sqrt(d * (2*maxDist - d)) gives a semicircular cross-section.
        // A circle becomes a sphere, a square becomes a smooth pillow.
        for row in 0..<rows {
            for col in 0..<cols {
                let d = depths[row][col]
                if d > 0 {
                    depths[row][col] = sqrt(d * (2 * maxDist - d))
                }
            }
        }

        // Build mesh: front face (z > 0) + back face (z < 0)
        return buildMesh(depths: depths, rows: rows, cols: cols,
                          x0: Float(x0), y0: Float(y0), spacing: Float(gridSpacing))
    }

    // MARK: - Contour from strokes

    /// Builds a closed contour polygon from strokes, preserving concavities.
    /// For a single stroke, uses the points directly (already a closed path).
    /// For multiple strokes, connects them end-to-end into a closed polygon.
    private static func buildContour(from strokes: [Stroke]) -> [CGPoint] {
        guard !strokes.isEmpty else { return [] }

        if strokes.count == 1 {
            return strokes[0].points.map(\.location)
        }

        // Multiple strokes: connect them into a single closed polygon.
        // Start with the first stroke, then append each subsequent stroke
        // connecting to whichever end is nearest.
        var remaining = strokes.map { $0.points.map(\.location) }
        var contour = remaining.removeFirst()

        while !remaining.isEmpty {
            let lastPoint = contour.last!

            // Find the nearest stroke endpoint
            var bestIdx = 0
            var bestDist = CGFloat.infinity
            var shouldReverse = false

            for (i, path) in remaining.enumerated() {
                guard let first = path.first, let last = path.last else { continue }
                let distToFirst = hypot(lastPoint.x - first.x, lastPoint.y - first.y)
                let distToLast = hypot(lastPoint.x - last.x, lastPoint.y - last.y)
                if distToFirst < bestDist {
                    bestDist = distToFirst
                    bestIdx = i
                    shouldReverse = false
                }
                if distToLast < bestDist {
                    bestDist = distToLast
                    bestIdx = i
                    shouldReverse = true
                }
            }

            var next = remaining.remove(at: bestIdx)
            if shouldReverse { next.reverse() }
            contour.append(contentsOf: next)
        }

        return contour
    }

    // MARK: - Distance computation

    private static func distanceToEdge(_ point: CGPoint, contour: [CGPoint]) -> CGFloat {
        var minDist = CGFloat.infinity
        for i in 0..<contour.count {
            let a = contour[i]
            let b = contour[(i + 1) % contour.count]
            let dist = pointToSegmentDistance(point, a: a, b: b)
            minDist = min(minDist, dist)
        }
        return minDist
    }

    private static func pointToSegmentDistance(_ p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        let projX = a.x + t * dx, projY = a.y + t * dy
        return hypot(p.x - projX, p.y - projY)
    }

    // MARK: - Mesh generation

    private static func buildMesh(depths: [[Float]], rows: Int, cols: Int,
                                   x0: Float, y0: Float, spacing: Float) -> Mesh {
        var vertices: [MeshVertex] = []
        var faces: [MeshFace] = []

        // Vertex index map: [row][col] → vertex index for front face
        var frontIdx = [[Int]](repeating: [Int](repeating: -1, count: cols), count: rows)
        var backIdx = [[Int]](repeating: [Int](repeating: -1, count: cols), count: rows)

        // Create front and back vertices
        for row in 0..<rows {
            for col in 0..<cols {
                let d = depths[row][col]
                if d > 0 {
                    let x = x0 + Float(col) * spacing
                    let y = -(y0 + Float(row) * spacing) // negate Y for correct orientation
                    let normal = computeNormal(depths: depths, row: row, col: col, spacing: spacing, front: true)

                    frontIdx[row][col] = vertices.count
                    vertices.append(MeshVertex(position: SIMD3(x, y, d), normal: normal))

                    backIdx[row][col] = vertices.count
                    vertices.append(MeshVertex(position: SIMD3(x, y, -d), normal: SIMD3(-normal.x, -normal.y, -normal.z)))
                }
            }
        }

        // Create front and back faces (triangulated grid)
        for row in 0..<(rows - 1) {
            for col in 0..<(cols - 1) {
                let tl = frontIdx[row][col]
                let tr = frontIdx[row][col + 1]
                let bl = frontIdx[row + 1][col]
                let br = frontIdx[row + 1][col + 1]

                // Front face (winding reversed to compensate for Y negation)
                if tl >= 0 && tr >= 0 && bl >= 0 {
                    faces.append(MeshFace(indices: SIMD3(UInt32(tl), UInt32(tr), UInt32(bl))))
                }
                if tr >= 0 && bl >= 0 && br >= 0 {
                    faces.append(MeshFace(indices: SIMD3(UInt32(tr), UInt32(br), UInt32(bl))))
                }

                // Back face
                let tlB = backIdx[row][col]
                let trB = backIdx[row][col + 1]
                let blB = backIdx[row + 1][col]
                let brB = backIdx[row + 1][col + 1]

                if tlB >= 0 && trB >= 0 && blB >= 0 {
                    faces.append(MeshFace(indices: SIMD3(UInt32(tlB), UInt32(blB), UInt32(trB))))
                }
                if trB >= 0 && blB >= 0 && brB >= 0 {
                    faces.append(MeshFace(indices: SIMD3(UInt32(trB), UInt32(blB), UInt32(brB))))
                }
            }
        }

        // Edge faces: stitch front and back along the boundary
        stitchEdges(frontIdx: frontIdx, backIdx: backIdx, rows: rows, cols: cols, faces: &faces)

        return Mesh(vertices: vertices, faces: faces)
    }

    /// Connects front and back faces along all boundary edges.
    /// For each interior point with an exterior neighbor, creates a triangle
    /// connecting its front and back vertices to the next boundary point.
    private static func stitchEdges(frontIdx: [[Int]], backIdx: [[Int]],
                                     rows: Int, cols: Int, faces: inout [MeshFace]) {
        for row in 0..<rows {
            for col in 0..<cols {
                guard frontIdx[row][col] >= 0 else { continue }
                let f = UInt32(frontIdx[row][col])
                let b = UInt32(backIdx[row][col])

                let hasRight = col + 1 < cols && frontIdx[row][col + 1] >= 0
                let hasLeft = col - 1 >= 0 && frontIdx[row][col - 1] >= 0
                let hasBelow = row + 1 < rows && frontIdx[row + 1][col] >= 0
                let hasAbove = row - 1 >= 0 && frontIdx[row - 1][col] >= 0

                // Right neighbor is exterior → stitch along vertical edge
                if !hasRight {
                    // Connect to the interior neighbor below (if any) along this edge
                    if hasBelow {
                        let f2 = UInt32(frontIdx[row + 1][col]), b2 = UInt32(backIdx[row + 1][col])
                        faces.append(MeshFace(indices: SIMD3(f, b, f2)))
                        faces.append(MeshFace(indices: SIMD3(f2, b, b2)))
                    }
                }

                // Left neighbor is exterior → stitch along vertical edge
                if !hasLeft {
                    if hasBelow {
                        let f2 = UInt32(frontIdx[row + 1][col]), b2 = UInt32(backIdx[row + 1][col])
                        faces.append(MeshFace(indices: SIMD3(f, f2, b)))
                        faces.append(MeshFace(indices: SIMD3(f2, b2, b)))
                    }
                }

                // Below neighbor is exterior → stitch along horizontal edge
                if !hasBelow {
                    if hasRight {
                        let f2 = UInt32(frontIdx[row][col + 1]), b2 = UInt32(backIdx[row][col + 1])
                        faces.append(MeshFace(indices: SIMD3(f, f2, b)))
                        faces.append(MeshFace(indices: SIMD3(f2, b2, b)))
                    }
                }

                // Above neighbor is exterior → stitch along horizontal edge
                if !hasAbove {
                    if hasRight {
                        let f2 = UInt32(frontIdx[row][col + 1]), b2 = UInt32(backIdx[row][col + 1])
                        faces.append(MeshFace(indices: SIMD3(f, b, f2)))
                        faces.append(MeshFace(indices: SIMD3(f2, b, b2)))
                    }
                }

                // Corner cases: isolated boundary point with no adjacent interior neighbor
                // in the stitching direction → close with a single triangle
                if !hasRight && !hasBelow && !hasLeft && !hasAbove {
                    // Fully isolated point — just a degenerate triangle front→back
                    // (shouldn't happen in practice with grid spacing < shape size)
                } else if !hasRight && !hasBelow {
                    // Bottom-right corner: close with triangle
                    faces.append(MeshFace(indices: SIMD3(f, b, f))) // degenerate, skip
                }
            }
        }
    }

    private static func computeNormal(depths: [[Float]], row: Int, col: Int,
                                       spacing: Float, front: Bool) -> SIMD3<Float> {
        let rows = depths.count, cols = depths[0].count

        let left = col > 0 ? depths[row][col - 1] : 0
        let right = col < cols - 1 ? depths[row][col + 1] : 0
        let up = row > 0 ? depths[row - 1][col] : 0
        let down = row < rows - 1 ? depths[row + 1][col] : 0

        let dx = (right - left) / (2 * spacing)
        let dy = (down - up) / (2 * spacing)

        var normal = normalize(SIMD3<Float>(-dx, -dy, 1))
        if !front { normal.z = -normal.z }
        return normal
    }
}
