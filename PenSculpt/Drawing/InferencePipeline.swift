import Foundation

enum InferencePipeline {

    /// Runs the full inference pipeline: strokes → skeleton → primitives → mesh.
    static func infer(from strokes: [Stroke]) -> SculptObject {
        let skeleton = SkeletonExtractor.extract(from: strokes)
        let segments = Segmenter.segment(skeleton)

        var allVertices: [MeshVertex] = []
        var allFaces: [MeshFace] = []

        for segment in segments {
            let primitive = PrimitiveFitter.fit(segment)
            let mesh = MeshAssembler.assemble(from: primitive)
            let offset = UInt32(allVertices.count)
            allVertices.append(contentsOf: mesh.vertices)
            allFaces.append(contentsOf: mesh.faces.map {
                MeshFace(indices: $0.indices &+ SIMD3(repeating: offset))
            })
        }

        let mesh = Mesh(vertices: allVertices, faces: allFaces)
        let strokeIDs = Set(strokes.map(\.id))
        return SculptObject(mesh: mesh, sourceStrokeIDs: strokeIDs)
    }
}
