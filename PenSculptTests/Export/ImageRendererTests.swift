import XCTest
import PencilKit
@testable import PenSculpt

@MainActor
final class ImageRendererTests: XCTestCase {

    func testRenderPNGFromEmptyCanvasReturnsValidFile() throws {
        let canvas = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        canvas.backgroundColor = .white

        let url = try ImageRenderer.renderPNG(from: canvas)

        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.pathExtension, "png")
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 0)
        let img = try XCTUnwrap(UIImage(data: data))
        let cg = try XCTUnwrap(img.cgImage)
        // PNG round-trip preserves pixel count (not points). At 1x the PNG is
        // 200×200 px; at 2x/3x it's 400×400 / 600×600. Accept anything from 200 up.
        XCTAssertGreaterThanOrEqual(cg.width, 200)
        XCTAssertGreaterThanOrEqual(cg.height, 200)
    }

    func testRenderPNGRespectsTransparentBackground() throws {
        let canvas = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        canvas.backgroundColor = .clear

        let url = try ImageRenderer.renderPNG(from: canvas)
        defer { try? FileManager.default.removeItem(at: url) }

        let img = try XCTUnwrap(UIImage(data: try Data(contentsOf: url)))
        let cg = try XCTUnwrap(img.cgImage)
        // PNG carries alpha; UIImage(data:) decodes to .last (non-premultiplied),
        // not the .premultipliedLast that UIGraphicsImageRenderer's context uses.
        // Accept any alpha-bearing variant.
        let alphaBearing: Set<CGImageAlphaInfo> = [
            .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly
        ]
        XCTAssertTrue(alphaBearing.contains(cg.alphaInfo),
                      "Expected alpha-bearing PNG, got alphaInfo=\(cg.alphaInfo.rawValue)")
    }

    func testRenderPNGThrowsRenderFailedForZeroSizeCanvas() {
        let canvas = PKCanvasView(frame: .zero)
        XCTAssertThrowsError(try ImageRenderer.renderPNG(from: canvas)) { error in
            guard case ExportError.renderFailed = error else {
                XCTFail("Expected .renderFailed, got \(error)")
                return
            }
        }
    }
}
