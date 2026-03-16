import MetalKit
import simd

struct StrokeRenderUniforms {
    var mvpMatrix: simd_float4x4
}

struct MeshRenderUniforms {
    var mvpMatrix: simd_float4x4
    var lightDirection: SIMD3<Float>
    var baseColor: SIMD3<Float>
}

class SculptRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let strokePipeline: MTLRenderPipelineState
    let meshPipeline: MTLRenderPipelineState

    var strokes: [Stroke] = []
    var sculptObjects: [SculptObject] = [] {
        didSet {
            let currentIDs = Set(sculptObjects.map(\.id))
            bufferCache = bufferCache.filter { currentIDs.contains($0.key) }
            recomputeCombinedBounds()
        }
    }
    var activeObjectID: UUID?
    var config: SculptConfig = .default
    var rotation = simd_quatf(angle: -SculptConfig.default.cameraTilt, axis: SIMD3(1, 0, 0))

    private struct MeshBuffers {
        let vertex: MTLBuffer
        let index: MTLBuffer
        let indexCount: Int
    }
    private var bufferCache: [UUID: MeshBuffers] = [:]
    private var combinedCenter = SIMD3<Float>(0, 0, 0)
    private var combinedRadius: Float = 1

    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue

        guard let library = device.makeDefaultLibrary() else { return nil }

        // Stroke pipeline (2D lines)
        let strokeDesc = MTLRenderPipelineDescriptor()
        strokeDesc.vertexFunction = library.makeFunction(name: "stroke_vertex")
        strokeDesc.fragmentFunction = library.makeFunction(name: "stroke_fragment")
        strokeDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        strokeDesc.depthAttachmentPixelFormat = .depth32Float

        // Mesh pipeline (3D triangles with lighting)
        let meshDesc = MTLRenderPipelineDescriptor()
        meshDesc.vertexFunction = library.makeFunction(name: "mesh_vertex")
        meshDesc.fragmentFunction = library.makeFunction(name: "mesh_fragment")
        meshDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        meshDesc.depthAttachmentPixelFormat = .depth32Float

        // Vertex descriptor for mesh
        let vertexDesc = MTLVertexDescriptor()
        vertexDesc.attributes[0].format = .float3
        vertexDesc.attributes[0].offset = 0
        vertexDesc.attributes[0].bufferIndex = 0
        vertexDesc.attributes[1].format = .float3
        vertexDesc.attributes[1].offset = MemoryLayout<Float>.stride * 3 // 12 bytes
        vertexDesc.attributes[1].bufferIndex = 0
        vertexDesc.layouts[0].stride = MemoryLayout<Float>.stride * 6 // 24 bytes
        meshDesc.vertexDescriptor = vertexDesc

        guard let sp = try? device.makeRenderPipelineState(descriptor: strokeDesc),
              let mp = try? device.makeRenderPipelineState(descriptor: meshDesc) else { return nil }
        self.strokePipeline = sp
        self.meshPipeline = mp

        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        if !sculptObjects.isEmpty {
            drawAllMeshes(in: view, encoder: encoder)
        } else {
            drawStrokes(in: view, encoder: encoder)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Mesh rendering

    private func drawAllMeshes(in view: MTKView, encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(meshPipeline)

        if let depthState = makeDepthState() {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setCullMode(.back)
        encoder.setFrontFacing(.counterClockwise)

        if config.displayMode == "wireframe" {
            encoder.setTriangleFillMode(.lines)
        }

        let mvp = combinedProjection(viewSize: view.bounds.size)

        for obj in sculptObjects where !obj.mesh.isEmpty {
            guard let b = getOrCreateBuffers(for: obj), b.indexCount > 0 else { continue }

            let isActive = obj.id == activeObjectID
            var uniforms = MeshRenderUniforms(
                mvpMatrix: mvp,
                lightDirection: normalize(SIMD3<Float>(0.3, 0.6, 1.0)),
                baseColor: isActive ? SIMD3(0.85, 0.85, 0.9) : SIMD3(0.5, 0.5, 0.55)
            )

            encoder.setVertexBuffer(b.vertex, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<MeshRenderUniforms>.size, index: 2)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MeshRenderUniforms>.size, index: 2)

            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: b.indexCount,
                indexType: .uint32,
                indexBuffer: b.index,
                indexBufferOffset: 0
            )
        }
    }

    private func getOrCreateBuffers(for obj: SculptObject) -> MeshBuffers? {
        if let cached = bufferCache[obj.id] { return cached }

        let mesh = obj.mesh
        var vertexData: [Float] = []
        vertexData.reserveCapacity(mesh.vertices.count * 6)
        for v in mesh.vertices {
            vertexData.append(contentsOf: [v.position.x, v.position.y, v.position.z])
            vertexData.append(contentsOf: [v.normal.x, v.normal.y, v.normal.z])
        }

        var indexData: [UInt32] = []
        indexData.reserveCapacity(mesh.faces.count * 3)
        for f in mesh.faces {
            indexData.append(contentsOf: [f.indices.x, f.indices.y, f.indices.z])
        }

        guard let vb = device.makeBuffer(bytes: vertexData,
                                           length: vertexData.count * MemoryLayout<Float>.stride,
                                           options: .storageModeShared),
              let ib = device.makeBuffer(bytes: indexData,
                                          length: indexData.count * MemoryLayout<UInt32>.stride,
                                          options: .storageModeShared)
        else { return nil }

        let buffers = MeshBuffers(vertex: vb, index: ib, indexCount: indexData.count)
        bufferCache[obj.id] = buffers
        return buffers
    }

    func rotate(dx: Float, dy: Float) {
        let sensitivity: Float = 0.005
        let qx = simd_quatf(angle: -dy * sensitivity, axis: SIMD3(1, 0, 0))
        let qy = simd_quatf(angle: dx * sensitivity, axis: SIMD3(0, 1, 0))
        rotation = (qx * qy * rotation).normalized
    }

    private func combinedProjection(viewSize: CGSize) -> simd_float4x4 {
        let r = combinedRadius
        let aspect = Float(viewSize.width) / Float(viewSize.height)
        let proj = Self.orthographicProjection(
            left: -r * aspect, right: r * aspect,
            bottom: -r, top: r,
            near: -r * 10, far: r * 10
        )
        let view = simd_float4x4(rotation) * translationMatrix(-combinedCenter.x, -combinedCenter.y, -combinedCenter.z)
        return proj * view
    }

    private func recomputeCombinedBounds() {
        var minP = SIMD3<Float>(Float.infinity, Float.infinity, Float.infinity)
        var maxP = SIMD3<Float>(-Float.infinity, -Float.infinity, -Float.infinity)
        for obj in sculptObjects {
            for v in obj.mesh.vertices {
                minP = min(minP, v.position)
                maxP = max(maxP, v.position)
            }
        }
        if minP.x < Float.infinity {
            combinedCenter = (minP + maxP) / 2
            let extent = maxP - minP
            combinedRadius = max(extent.x, max(extent.y, extent.z)) / 2 * 1.3
        }
    }

    private func makeDepthState() -> MTLDepthStencilState? {
        let desc = MTLDepthStencilDescriptor()
        desc.depthCompareFunction = .less
        desc.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: desc)
    }

    // MARK: - Stroke rendering (fallback)

    private func drawStrokes(in view: MTKView, encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(strokePipeline)

        let viewSize = view.bounds.size
        var uniforms = StrokeRenderUniforms(mvpMatrix: Self.fittedProjection(strokes: strokes, viewSize: viewSize))
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<StrokeRenderUniforms>.size, index: 2)

        for stroke in strokes {
            guard stroke.points.count > 1 else { continue }
            var positions = stroke.points.map {
                SIMD2<Float>(Float($0.location.x), Float($0.location.y))
            }
            var colors = [SIMD4<Float>](repeating: SIMD4<Float>(
                Float(stroke.color.red), Float(stroke.color.green),
                Float(stroke.color.blue), Float(stroke.color.alpha)
            ), count: positions.count)

            encoder.setVertexBytes(&positions, length: positions.count * MemoryLayout<SIMD2<Float>>.stride, index: 0)
            encoder.setVertexBytes(&colors, length: colors.count * MemoryLayout<SIMD4<Float>>.stride, index: 1)
            encoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: positions.count)
        }
    }

    // MARK: - Projections

    static func fittedProjection(strokes: [Stroke], viewSize: CGSize) -> simd_float4x4 {
        SculptRenderer.orthographicProjection(
            left: 0, right: Float(viewSize.width),
            bottom: Float(viewSize.height), top: 0,
            near: -1, far: 1
        )
    }

    static func orthographicProjection(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> simd_float4x4 {
        let sx = 2.0 / (right - left)
        let sy = 2.0 / (top - bottom)
        let sz = -2.0 / (far - near)
        let tx = -(right + left) / (right - left)
        let ty = -(top + bottom) / (top - bottom)
        let tz = -(far + near) / (far - near)
        return simd_float4x4(columns: (
            SIMD4<Float>(sx, 0, 0, 0),
            SIMD4<Float>(0, sy, 0, 0),
            SIMD4<Float>(0, 0, sz, 0),
            SIMD4<Float>(tx, ty, tz, 1)
        ))
    }

    private func translationMatrix(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(x, y, z, 1)
        ))
    }
}
