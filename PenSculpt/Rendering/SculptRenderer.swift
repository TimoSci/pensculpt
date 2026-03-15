import MetalKit
import simd

struct MetalUniforms {
    var mvpMatrix: simd_float4x4
}

class SculptRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLRenderPipelineState
    var strokes: [Stroke] = []

    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue

        guard let library = device.makeDefaultLibrary(),
              let vertexFunc = library.makeFunction(name: "vertex_main"),
              let fragmentFunc = library.makeFunction(name: "fragment_main") else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunc
        descriptor.fragmentFunction = fragmentFunc
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.pipelineState = pipeline

        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        encoder.setRenderPipelineState(pipelineState)

        let viewSize = view.bounds.size
        var uniforms = MetalUniforms(mvpMatrix: fittedProjection(viewSize: viewSize))
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<MetalUniforms>.size, index: 2)

        for stroke in strokes {
            guard stroke.points.count > 1 else { continue }
            drawStroke(stroke, encoder: encoder)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func drawStroke(_ stroke: Stroke, encoder: MTLRenderCommandEncoder) {
        var positions = stroke.points.map {
            SIMD2<Float>(Float($0.location.x), Float($0.location.y))
        }
        var colors = [SIMD4<Float>](repeating: SIMD4<Float>(
            Float(stroke.color.red),
            Float(stroke.color.green),
            Float(stroke.color.blue),
            Float(stroke.color.alpha)
        ), count: positions.count)

        encoder.setVertexBytes(&positions,
                               length: positions.count * MemoryLayout<SIMD2<Float>>.stride,
                               index: 0)
        encoder.setVertexBytes(&colors,
                               length: colors.count * MemoryLayout<SIMD4<Float>>.stride,
                               index: 1)
        encoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: positions.count)
    }

    // MARK: - Projection

    private func fittedProjection(viewSize: CGSize) -> simd_float4x4 {
        Self.fittedProjection(strokes: strokes, viewSize: viewSize)
    }

    /// 1:1 projection — strokes appear at their original canvas position.
    static func fittedProjection(strokes: [Stroke], viewSize: CGSize) -> simd_float4x4 {
        orthographic(left: 0, right: Float(viewSize.width),
                     top: 0, bottom: Float(viewSize.height))
    }

    /// Standard orthographic projection (y-down screen coords → clip space).
    static func orthographic(left: Float, right: Float, top: Float, bottom: Float) -> simd_float4x4 {
        let sx = 2.0 / (right - left)
        let sy = -2.0 / (bottom - top)
        let tx = -(right + left) / (right - left)
        let ty = (bottom + top) / (bottom - top)
        return simd_float4x4(columns: (
            SIMD4<Float>(sx, 0, 0, 0),
            SIMD4<Float>(0, sy, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(tx, ty, 0, 1)
        ))
    }
}
