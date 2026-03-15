import UIKit
import Vision

enum ContourExtractor {

    /// Uses Apple's Vision framework (ML-powered) to extract clean contours
    /// from rasterized strokes. Returns the largest detected contour.
    static func extract(from strokes: [Stroke], config: SculptConfig = .default) -> [CGPoint] {
        let image = rasterize(strokes: strokes, config: config)
        guard let cgImage = image.cgImage else {
            return fallbackContour(from: strokes)
        }

        let request = VNDetectContoursRequest()
        request.contrastAdjustment = Float(config.contourContrast)
        request.detectsDarkOnLight = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return fallbackContour(from: strokes)
        }

        guard let results = request.results,
              let observation = results.first else {
            return fallbackContour(from: strokes)
        }

        // Find the largest contour by point count
        let topLevel = observation.topLevelContours
        guard let largest = topLevel.max(by: { $0.normalizedPoints.count < $1.normalizedPoints.count }) else {
            return fallbackContour(from: strokes)
        }

        // Convert normalized coordinates (0..1, Y-flipped) to stroke coordinate space
        let allPoints = strokes.flatMap { $0.points.map(\.location) }
        let xs = allPoints.map(\.x), ys = allPoints.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return fallbackContour(from: strokes) }
        let pad = config.contourStrokeWidth * 2
        let extentX = maxX - minX + pad * 2
        let extentY = maxY - minY + pad * 2

        let contour = largest.normalizedPoints.map { np in
            CGPoint(
                x: minX - pad + CGFloat(np.x) * extentX,
                y: minY - pad + CGFloat(1 - np.y) * extentY
            )
        }

        // Simplify if too many points
        if contour.count > Int(config.contourMaxPoints) {
            return simplify(contour, tolerance: 1.0)
        }
        return contour
    }

    // MARK: - Rasterization

    /// Renders strokes as thick white lines on a black background.
    private static func rasterize(strokes: [Stroke], config: SculptConfig) -> UIImage {
        let allPoints = strokes.flatMap { $0.points.map(\.location) }
        let xs = allPoints.map(\.x), ys = allPoints.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else {
            return UIImage()
        }

        let pad = config.contourStrokeWidth * 2
        let w = (maxX - minX + pad * 2) * config.contourRasterScale
        let h = (maxY - minY + pad * 2) * config.contourRasterScale
        let size = CGSize(width: w, height: h)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let gc = ctx.cgContext
            gc.setFillColor(UIColor.black.cgColor)
            gc.fill(CGRect(origin: .zero, size: size))

            gc.setStrokeColor(UIColor.white.cgColor)
            gc.setLineWidth(config.contourStrokeWidth * config.contourRasterScale)
            gc.setLineCap(.round)
            gc.setLineJoin(.round)

            let scale = config.contourRasterScale
            for stroke in strokes {
                guard stroke.points.count > 1 else { continue }
                gc.beginPath()
                let first = stroke.points[0].location
                gc.move(to: CGPoint(x: (first.x - minX + pad) * scale,
                                     y: (first.y - minY + pad) * scale))
                for point in stroke.points.dropFirst() {
                    gc.addLine(to: CGPoint(x: (point.location.x - minX + pad) * scale,
                                            y: (point.location.y - minY + pad) * scale))
                }
                gc.strokePath()
            }
        }
    }

    // MARK: - Fallback

    /// Falls back to stroke-based contour when Vision fails.
    private static func fallbackContour(from strokes: [Stroke]) -> [CGPoint] {
        guard !strokes.isEmpty else { return [] }
        if strokes.count == 1 {
            return strokes[0].points.map(\.location)
        }
        var remaining = strokes.map { $0.points.map(\.location) }
        var contour = remaining.removeFirst()
        while !remaining.isEmpty {
            let last = contour.last!
            var bestIdx = 0
            var bestDist = CGFloat.infinity
            var reverse = false
            for (i, path) in remaining.enumerated() {
                guard let f = path.first, let l = path.last else { continue }
                let df = hypot(last.x - f.x, last.y - f.y)
                let dl = hypot(last.x - l.x, last.y - l.y)
                if df < bestDist { bestDist = df; bestIdx = i; reverse = false }
                if dl < bestDist { bestDist = dl; bestIdx = i; reverse = true }
            }
            var next = remaining.remove(at: bestIdx)
            if reverse { next.reverse() }
            contour.append(contentsOf: next)
        }
        return contour
    }

    // MARK: - Douglas-Peucker simplification

    static func simplify(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var maxDist: CGFloat = 0
        var maxIdx = 0
        let first = points.first!, last = points.last!

        for i in 1..<(points.count - 1) {
            let dist = perpendicularDistance(points[i], lineStart: first, lineEnd: last)
            if dist > maxDist {
                maxDist = dist
                maxIdx = i
            }
        }

        if maxDist > tolerance {
            let left = simplify(Array(points[...maxIdx]), tolerance: tolerance)
            let right = simplify(Array(points[maxIdx...]), tolerance: tolerance)
            return left.dropLast() + right
        } else {
            return [first, last]
        }
    }

    private static func perpendicularDistance(_ point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let len = hypot(dx, dy)
        guard len > 0 else { return hypot(point.x - lineStart.x, point.y - lineStart.y) }
        return abs(dy * point.x - dx * point.y + lineEnd.x * lineStart.y - lineEnd.y * lineStart.x) / len
    }
}
