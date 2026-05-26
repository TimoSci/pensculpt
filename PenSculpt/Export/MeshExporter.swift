import Foundation
import Metal
import MetalKit
import ModelIO
import simd

enum MeshExporter {

    static func export(_ objects: [SculptObject], format: MeshFormat) throws -> URL {
        let nonEmpty = objects.filter { !$0.mesh.isEmpty }
        guard !nonEmpty.isEmpty else {
            throw ExportError.emptyContent
        }

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ExportError.modelIOFailed(NSError(
                domain: "Export", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Metal device unavailable"]
            ))
        }
        let allocator = MTKMeshBufferAllocator(device: device)
        let asset = MDLAsset(bufferAllocator: allocator)

        for object in nonEmpty {
            let mdlMesh = try buildMDLMesh(from: object, allocator: allocator)
            asset.add(mdlMesh)
        }

        let url = makeTempURL(extension: format.fileExtension)
        do {
            try asset.export(to: url)
        } catch {
            throw ExportError.modelIOFailed(error)
        }
        return url
    }

    private static func buildMDLMesh(from object: SculptObject,
                                     allocator: MTKMeshBufferAllocator) throws -> MDLMesh {
        let vertexCount = object.mesh.vertices.count
        let vertexStride = MemoryLayout<MeshVertex>.stride
        let vertexBuffer = allocator.newBuffer(vertexCount * vertexStride, type: .vertex)
        object.mesh.vertices.withUnsafeBufferPointer { src in
            vertexBuffer.map().bytes.copyMemory(
                from: UnsafeRawPointer(src.baseAddress!),
                byteCount: vertexCount * vertexStride
            )
        }

        let indexCount = object.mesh.faces.count * 3
        let indexBuffer = allocator.newBuffer(indexCount * MemoryLayout<UInt32>.stride, type: .index)
        var indices: [UInt32] = []
        indices.reserveCapacity(indexCount)
        for face in object.mesh.faces {
            indices.append(face.indices.x)
            indices.append(face.indices.y)
            indices.append(face.indices.z)
        }
        indices.withUnsafeBufferPointer { src in
            indexBuffer.map().bytes.copyMemory(
                from: UnsafeRawPointer(src.baseAddress!),
                byteCount: indexCount * MemoryLayout<UInt32>.stride
            )
        }

        let descriptor = MDLVertexDescriptor()
        descriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3, offset: 0, bufferIndex: 0
        )
        descriptor.attributes[1] = MDLVertexAttribute(
            name: MDLVertexAttributeNormal,
            format: .float3, offset: MemoryLayout<SIMD3<Float>>.stride, bufferIndex: 0
        )
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: vertexStride)

        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: indexCount,
            indexType: .uInt32,
            geometryType: .triangles,
            material: nil
        )

        let mesh = MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: vertexCount,
            descriptor: descriptor,
            submeshes: [submesh]
        )
        mesh.name = "object-\(object.id.uuidString)"
        return mesh
    }

    private static func makeTempURL(extension ext: String) -> URL {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let name = "pensculpt-\(ts).\(ext)"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }
}
