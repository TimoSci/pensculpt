import UIKit
import PencilKit
import MetalKit

enum ImageRenderer {

    static func renderPNG(from canvasView: PKCanvasView) throws -> URL {
        let bounds = canvasView.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            throw ExportError.renderFailed
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)

        let image = renderer.image { ctx in
            if let bg = canvasView.backgroundColor, bg.cgColor.alpha > 0 {
                bg.setFill()
                ctx.fill(bounds)
            }
            let drawingImage = canvasView.drawing.image(from: bounds, scale: format.scale)
            drawingImage.draw(in: bounds)
        }

        guard let data = image.pngData() else {
            throw ExportError.renderFailed
        }

        let url = makeTempURL(extension: "png")
        do {
            try data.write(to: url)
        } catch {
            throw ExportError.writeFailed(error)
        }
        return url
    }

    private static func makeTempURL(extension ext: String) -> URL {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let name = "pensculpt-\(ts).\(ext)"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }
}
