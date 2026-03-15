import Foundation
import simd

enum ShapeInflater {

    /// Inflates a 2D contour into a closed 3D mesh by using edge distance as depth.
    static func inflate(strokes: [Stroke], config: SculptConfig = .default, gridSpacing: CGFloat = 3) -> Mesh {
        let allPoints = strokes.flatMap { $0.points.map(\.location) }
        let contour = ContourAnalyzer.extractContour(from: strokes)
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

        // Edge faces: connect front and back at the boundary (where depth transitions to 0)
        for row in 0..<rows {
            for col in 0..<cols {
                if frontIdx[row][col] < 0 { continue }

                // Check each neighbor — if neighbor has no depth, this is an edge
                let neighbors = [(row - 1, col), (row + 1, col), (row, col - 1), (row, col + 1)]
                for (nr, nc) in neighbors {
                    if nr < 0 || nr >= rows || nc < 0 || nc >= cols || frontIdx[nr][nc] < 0 {
                        // This vertex is on the edge — connect front to back
                        let fi = UInt32(frontIdx[row][col])
                        let bi = UInt32(backIdx[row][col])

                        // Find an adjacent edge vertex to form a quad
                        if let adj = findAdjacentEdge(row: row, col: col, dr: nr - row, dc: nc - col,
                                                       frontIdx: frontIdx, rows: rows, cols: cols) {
                            let fAdj = UInt32(frontIdx[adj.0][adj.1])
                            let bAdj = UInt32(backIdx[adj.0][adj.1])
                            faces.append(MeshFace(indices: SIMD3(fi, fAdj, bi)))
                            faces.append(MeshFace(indices: SIMD3(fAdj, bAdj, bi)))
                        }
                    }
                }
            }
        }

        return Mesh(vertices: vertices, faces: faces)
    }

    private static func findAdjacentEdge(row: Int, col: Int, dr: Int, dc: Int,
                                          frontIdx: [[Int]], rows: Int, cols: Int) -> (Int, Int)? {
        // Look for the next edge vertex along the boundary
        let candidates: [(Int, Int)]
        if dr != 0 { // vertical edge — look left and right
            candidates = [(row, col - 1), (row, col + 1)]
        } else { // horizontal edge — look up and down
            candidates = [(row - 1, col), (row + 1, col)]
        }
        for (cr, cc) in candidates {
            if cr >= 0 && cr < rows && cc >= 0 && cc < cols && frontIdx[cr][cc] >= 0 {
                return (cr, cc)
            }
        }
        return nil
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
