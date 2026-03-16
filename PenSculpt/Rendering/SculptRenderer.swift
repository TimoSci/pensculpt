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
    let meshPipeline: MTLRenderPipelineState
    let surfaceStrokePipeline: MTLRenderPipelineState
    let meshDepthState: MTLDepthStencilState
    let surfaceStrokeDepthState: MTLDepthStencilState

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
    var currentStrokePoints: [SIMD3<Float>] = []
    var lastHitT: Float = 0

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

        // Mesh pipeline (3D triangles with lighting)
        let meshDesc = MTLRenderPipelineDescriptor()
        meshDesc.vertexFunction = library.makeFunction(name: "mesh_vertex")
        meshDesc.fragmentFunction = library.makeFunction(name: "mesh_fragment")
        meshDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        meshDesc.depthAttachmentPixelFormat = .depth32Float

        let vertexDesc = MTLVertexDescriptor()
        vertexDesc.attributes[0].format = .float3
        vertexDesc.attributes[0].offset = 0
        vertexDesc.attributes[0].bufferIndex = 0
        vertexDesc.attributes[1].format = .float3
        vertexDesc.attributes[1].offset = MemoryLayout<Float>.stride * 3
        vertexDesc.attributes[1].bufferIndex = 0
        vertexDesc.layouts[0].stride = MemoryLayout<Float>.stride * 6
        meshDesc.vertexDescriptor = vertexDesc

        // Surface stroke pipeline (3D lines on mesh)
        let surfaceStrokeDesc = MTLRenderPipelineDescriptor()
        surfaceStrokeDesc.vertexFunction = library.makeFunction(name: "surface_stroke_vertex")
        surfaceStrokeDesc.fragmentFunction = library.makeFunction(name: "stroke_fragment")
        surfaceStrokeDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        surfaceStrokeDesc.depthAttachmentPixelFormat = .depth32Float

        guard let mp = try? device.makeRenderPipelineState(descriptor: meshDesc),
              let ssp = try? device.makeRenderPipelineState(descriptor: surfaceStrokeDesc) else { return nil }
        self.meshPipeline = mp
        self.surfaceStrokePipeline = ssp

        // Pre-create depth stencil states
        let meshDepthDesc = MTLDepthStencilDescriptor()
        meshDepthDesc.depthCompareFunction = .less
        meshDepthDesc.isDepthWriteEnabled = true

        let strokeDepthDesc = MTLDepthStencilDescriptor()
        strokeDepthDesc.depthCompareFunction = .always
        strokeDepthDesc.isDepthWriteEnabled = false

        guard let mds = device.makeDepthStencilState(descriptor: meshDepthDesc),
              let sds = device.makeDepthStencilState(descriptor: strokeDepthDesc) else { return nil }
        self.meshDepthState = mds
        self.surfaceStrokeDepthState = sds

        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard !sculptObjects.isEmpty,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        let mvp = combinedProjection(viewSize: view.bounds.size)
        drawAllMeshes(mvp: mvp, encoder: encoder)
        drawSurfaceStrokes(mvp: mvp, encoder: encoder)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Mesh rendering

    private func drawAllMeshes(mvp: simd_float4x4, encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(meshPipeline)
        encoder.setDepthStencilState(meshDepthState)
        encoder.setCullMode(.back)
        encoder.setFrontFacing(.counterClockwise)

        if config.displayMode == "wireframe" {
            encoder.setTriangleFillMode(.lines)
        }

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

        guard let vb = makeBuffer(vertexData),
              let ib = makeBuffer(indexData) else { return nil }

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

    // MARK: - Surface stroke rendering

    private func drawSurfaceStrokes(mvp: simd_float4x4, encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(surfaceStrokePipeline)
        encoder.setDepthStencilState(surfaceStrokeDepthState)

        var uniforms = StrokeRenderUniforms(mvpMatrix: mvp)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<StrokeRenderUniforms>.size, index: 2)

        let strokeColor = SIMD4<Float>(0.2, 0.2, 0.8, 1.0)
        for obj in sculptObjects {
            for stroke in obj.surfaceStrokes {
                drawLineStrip(stroke.points, color: strokeColor, encoder: encoder)
            }
        }

        if !currentStrokePoints.isEmpty {
            drawLineStrip(currentStrokePoints, color: SIMD4<Float>(0.2, 0.2, 0.8, 0.6), encoder: encoder)
        }
    }

    private func drawLineStrip(_ points: [SIMD3<Float>], color: SIMD4<Float>, encoder: MTLRenderCommandEncoder) {
        guard points.count > 1 else { return }
        var positions = points
        var colors = [SIMD4<Float>](repeating: color, count: points.count)

        guard let posBuffer = makeBuffer(&positions),
              let colBuffer = makeBuffer(&colors) else { return }

        encoder.setVertexBuffer(posBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(colBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: points.count)
    }

    // MARK: - Ray casting

    func hitTest(screenPoint: CGPoint, viewSize: CGSize) -> (point: SIMD3<Float>, t: Float)? {
        guard let activeID = activeObjectID,
              let obj = sculptObjects.first(where: { $0.id == activeID }),
              !obj.mesh.isEmpty else { return nil }

        let mvp = combinedProjection(viewSize: viewSize)
        let invMVP = mvp.inverse

        let ndcX = Float(2 * screenPoint.x / viewSize.width - 1)
        let ndcY = Float(1 - 2 * screenPoint.y / viewSize.height)

        let near4 = invMVP * SIMD4<Float>(ndcX, ndcY, -1, 1)
        let far4 = invMVP * SIMD4<Float>(ndcX, ndcY, 1, 1)
        let nearW = SIMD3<Float>(near4.x, near4.y, near4.z) / near4.w
        let farW = SIMD3<Float>(far4.x, far4.y, far4.z) / far4.w
        let direction = normalize(farW - nearW)

        var closestT: Float = Float.infinity
        var hitPoint: SIMD3<Float>?

        let mesh = obj.mesh
        for face in mesh.faces {
            let v0 = mesh.vertices[Int(face.indices.x)].position
            let v1 = mesh.vertices[Int(face.indices.y)].position
            let v2 = mesh.vertices[Int(face.indices.z)].position

            if let t = rayTriangleIntersect(origin: nearW, direction: direction, v0: v0, v1: v1, v2: v2),
               t < closestT {
                closestT = t
                hitPoint = nearW + t * direction - direction * config.surfaceStrokeOffset
            }
        }

        guard let hp = hitPoint else { return nil }
        return (hp, closestT)
    }

    func isTContinuous(_ newT: Float) -> Bool {
        currentStrokePoints.isEmpty || abs(newT - lastHitT) < config.surfaceStrokeMaxTJump
    }

    // MARK: - Mesh deformation

    func deformMesh(at screenPoint: CGPoint, viewSize: CGSize) {
        guard let activeID = activeObjectID,
              let idx = sculptObjects.firstIndex(where: { $0.id == activeID }) else { return }
        let mesh = sculptObjects[idx].mesh
        guard !mesh.isEmpty else { return }

        // Ray cast to find the deformation center
        let mvp = combinedProjection(viewSize: viewSize)
        let invMVP = mvp.inverse
        let ndcX = Float(2 * screenPoint.x / viewSize.width - 1)
        let ndcY = Float(1 - 2 * screenPoint.y / viewSize.height)
        let near4 = invMVP * SIMD4<Float>(ndcX, ndcY, -1, 1)
        let far4 = invMVP * SIMD4<Float>(ndcX, ndcY, 1, 1)
        let nearW = SIMD3<Float>(near4.x, near4.y, near4.z) / near4.w
        let farW = SIMD3<Float>(far4.x, far4.y, far4.z) / far4.w
        let direction = normalize(farW - nearW)

        var closestT: Float = Float.infinity
        var center: SIMD3<Float>?
        for face in mesh.faces {
            let v0 = mesh.vertices[Int(face.indices.x)].position
            let v1 = mesh.vertices[Int(face.indices.y)].position
            let v2 = mesh.vertices[Int(face.indices.z)].position
            if let t = rayTriangleIntersect(origin: nearW, direction: direction, v0: v0, v1: v1, v2: v2),
               t < closestT {
                closestT = t
                center = nearW + t * direction
            }
        }
        guard let center else { return }

        // Displace vertices within brush radius using Gaussian falloff.
        // Modify a local copy to avoid triggering didSet per vertex.
        let radius = config.deformBrushRadius
        let radiusSq = radius * radius
        let strength = config.deformStrength
        var vertices = sculptObjects[idx].mesh.vertices
        var modified = false

        for i in 0..<vertices.count {
            let distSq = simd_length_squared(vertices[i].position - center)
            if distSq < radiusSq {
                let falloff = expf(-distSq / (radiusSq * 0.25))
                vertices[i].position = vertices[i].position + vertices[i].normal * strength * falloff
                modified = true
            }
        }

        if modified {
            sculptObjects[idx].mesh.vertices = vertices
            bufferCache.removeValue(forKey: sculptObjects[idx].id)
        }
    }

    private func rayTriangleIntersect(origin: SIMD3<Float>, direction: SIMD3<Float>,
                                       v0: SIMD3<Float>, v1: SIMD3<Float>, v2: SIMD3<Float>) -> Float? {
        let edge1 = v1 - v0
        let edge2 = v2 - v0
        let h = cross(direction, edge2)
        let a = dot(edge1, h)
        // a > 0 means triangle faces toward camera; reject back-facing hits
        guard a > 1e-6 else { return nil }
        let f = 1.0 / a
        let s = origin - v0
        let u = f * dot(s, h)
        guard u >= 0 && u <= 1 else { return nil }
        let q = cross(s, edge1)
        let v = f * dot(direction, q)
        guard v >= 0 && u + v <= 1 else { return nil }
        let t = f * dot(edge2, q)
        return t > 1e-6 ? t : nil
    }

    // MARK: - Helpers

    private func makeBuffer<T>(_ data: [T]) -> MTLBuffer? {
        device.makeBuffer(bytes: data,
                          length: data.count * MemoryLayout<T>.stride,
                          options: .storageModeShared)
    }

    private func makeBuffer<T>(_ data: inout [T]) -> MTLBuffer? {
        device.makeBuffer(bytes: &data,
                          length: data.count * MemoryLayout<T>.stride,
                          options: .storageModeShared)
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
