import Foundation

enum InferencePipeline {

    /// Runs the full inference pipeline: strokes → skeleton → closed surface → mesh.
    static func infer(from strokes: [Stroke], config: SculptConfig = .default) -> SculptObject {
        let skeleton = SkeletonExtractor.extract(from: strokes)
        let closed = SurfaceCloser.close(skeleton, config: config)

        // Use the full closed skeleton as one segment (no splitting)
        let segment = SkeletonSegment(points: closed.points)
        let primitive = PrimitiveFitter.fit(segment)
        let mesh = MeshAssembler.assemble(from: primitive)

        let strokeIDs = Set(strokes.map(\.id))
        return SculptObject(mesh: mesh, sourceStrokeIDs: strokeIDs)
    }
}
