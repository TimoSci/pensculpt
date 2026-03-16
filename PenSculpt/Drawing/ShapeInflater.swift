import Foundation
import simd

enum ShapeInflater {

    /// Runs the full inference pipeline: strokes → inflated 3D mesh → SculptObject.
    static func sculpt(from strokes: [Stroke], config: SculptConfig = .default) -> SculptObject {
        let mesh = inflate(strokes: strokes, config: config)
        return SculptObject(mesh: mesh, sourceStrokeIDs: Set(strokes.map(\.id)))
    }

    /// Inflates a 2D contour into a closed 3D mesh by using edge distance as depth.
    static func inflate(strokes: [Stroke], config: SculptConfig = .default) -> Mesh {
        let allPoints = strokes.flatMap { $0.points.map(\.location) }
        let contour = ContourExtractor.extract(from: strokes, config: config)
        guard contour.count >= 3 else { return Mesh() }

        // Bounding box with padding
        let xs = allPoints.map(\.x), ys = allPoints.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return Mesh() }

        // Adaptive grid spacing: cap grid to ~150 cells per axis to prevent freezing
        let shapeSize = max(maxX - minX, maxY - minY)
        let gridSpacing = max(config.gridSpacing, shapeSize / 150)
        let pad = gridSpacing * 2
        let x0 = minX - pad, y0 = minY - pad
        let x1 = maxX + pad, y1 = maxY + pad

        let cols = max(2, Int((x1 - x0) / gridSpacing))
        let rows = max(2, Int((y1 - y0) / gridSpacing))

        // Compute distance field in parallel: each row processed on a separate core.
        // containsAndDistance merges point-in-polygon + nearest-edge into one loop.
        var depthBuffer = [Float](repeating: 0, count: rows * cols)
        depthBuffer.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: rows) { row in
                let rowOffset = row * cols
                for col in 0..<cols {
                    let p = CGPoint(x: x0 + CGFloat(col) * gridSpacing, y: y0 + CGFloat(row) * gridSpacing)
                    let (inside, dist) = containsAndDistance(p, contour: contour)
                    if inside {
                        buffer[rowOffset + col] = Float(dist)
                    }
                }
            }
        }

        let maxDist = depthBuffer.max() ?? 0
        guard maxDist > 0 else { return Mesh() }

        // Convert distance to depth using a sphere-like profile:
        // depth = sqrt(d * (2*maxDist - d)) gives a semicircular cross-section.
        var depths = [[Float]](repeating: [Float](repeating: 0, count: cols), count: rows)
        for row in 0..<rows {
            for col in 0..<cols {
                let d = depthBuffer[row * cols + col]
                if d > 0 {
                    depths[row][col] = sqrt(d * (2 * maxDist - d))
                }
            }
        }

        // Build mesh: front face (z > 0) + back face (z < 0)
        return buildMesh(depths: depths, rows: rows, cols: cols,
                          x0: Float(x0), y0: Float(y0), spacing: Float(gridSpacing))
    }

    // MARK: - Combined containment + distance (single pass over contour edges)

    /// Performs point-in-polygon test and nearest-edge distance in one loop.
    private static func containsAndDistance(_ point: CGPoint, contour: [CGPoint]) -> (inside: Bool, distance: CGFloat) {
        var inside = false
        var minDist = CGFloat.infinity
        var j = contour.count - 1
        for i in 0..<contour.count {
            let pi = contour[i]
            let pj = contour[j]

            // Ray-casting containment test
            if (pi.y > point.y) != (pj.y > point.y),
               point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x {
                inside.toggle()
            }

            // Distance to segment (pi, pj)
            let dx = pj.x - pi.x, dy = pj.y - pi.y
            let lenSq = dx * dx + dy * dy
            if lenSq <= 0 {
                minDist = min(minDist, hypot(point.x - pi.x, point.y - pi.y))
            } else {
                let t = max(0, min(1, ((point.x - pi.x) * dx + (point.y - pi.y) * dy) / lenSq))
                let projX = pi.x + t * dx, projY = pi.y + t * dy
                minDist = min(minDist, hypot(point.x - projX, point.y - projY))
            }

            j = i
        }
        return (inside, minDist)
    }

    // MARK: - Mesh generation

    private static func buildMesh(depths: [[Float]], rows: Int, cols: Int,
                                   x0: Float, y0: Float, spacing: Float) -> Mesh {
        var vertices: [MeshVertex] = []
        var faces: [MeshFace] = []

        // Vertex index map: [row][col] → vertex index for front/back face
        var frontIdx = [[Int]](repeating: [Int](repeating: -1, count: cols), count: rows)
        var backIdx = [[Int]](repeating: [Int](repeating: -1, count: cols), count: rows)

        // Create vertices. Boundary points get a single shared vertex at z=0.
        // Interior points get separate front (z>0) and back (z<0) vertices.
        for row in 0..<rows {
            for col in 0..<cols {
                let d = depths[row][col]
                if d > 0 {
                    let x = x0 + Float(col) * spacing
                    let y = -(y0 + Float(row) * spacing)
                    let boundary = isBoundary(row: row, col: col, depths: depths, rows: rows, cols: cols)

                    if boundary {
                        // Shared vertex at z=0 — closes the mesh naturally
                        let idx = vertices.count
                        vertices.append(MeshVertex(position: SIMD3(x, y, 0), normal: SIMD3(0, 0, 1)))
                        frontIdx[row][col] = idx
                        backIdx[row][col] = idx
                    } else {
                        let normal = computeNormal(depths: depths, row: row, col: col, spacing: spacing, front: true)
                        frontIdx[row][col] = vertices.count
                        vertices.append(MeshVertex(position: SIMD3(x, y, d), normal: normal))
                        backIdx[row][col] = vertices.count
                        vertices.append(MeshVertex(position: SIMD3(x, y, -d), normal: SIMD3(-normal.x, -normal.y, -normal.z)))
                    }
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

        return Mesh(vertices: vertices, faces: faces)
    }

    private static func isBoundary(row: Int, col: Int, depths: [[Float]],
                                    rows: Int, cols: Int) -> Bool {
        let neighbors = [(row - 1, col), (row + 1, col), (row, col - 1), (row, col + 1)]
        for (nr, nc) in neighbors {
            if nr < 0 || nr >= rows || nc < 0 || nc >= cols || depths[nr][nc] <= 0 {
                return true
            }
        }
        return false
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
