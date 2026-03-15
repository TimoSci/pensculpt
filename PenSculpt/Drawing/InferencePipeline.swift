import Foundation

enum InferencePipeline {

    /// Runs the inference pipeline: strokes → inflated 3D mesh.
    static func infer(from strokes: [Stroke], config: SculptConfig = .default) -> SculptObject {
        let mesh = ShapeInflater.inflate(strokes: strokes, config: config)
        let strokeIDs = Set(strokes.map(\.id))
        return SculptObject(mesh: mesh, sourceStrokeIDs: strokeIDs)
    }
}
