import XCTest
import simd
@testable import PenSculpt

/// Step-by-step diagnostic for the inference pipeline.
/// Run each test individually to inspect intermediate outputs.
final class PipelineDiagnosticTests: XCTestCase {

    // Simulate a simple vase outline: left profile + right profile
    private var sampleStrokes: [Stroke] {
        let leftProfile = Stroke(points: [
            StrokePoint(location: CGPoint(x: 200, y: 100), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0),
            StrokePoint(location: CGPoint(x: 180, y: 200), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.1),
            StrokePoint(location: CGPoint(x: 170, y: 300), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.2),
            StrokePoint(location: CGPoint(x: 180, y: 400), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.3),
            StrokePoint(location: CGPoint(x: 200, y: 500), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.4),
        ])
        let rightProfile = Stroke(points: [
            StrokePoint(location: CGPoint(x: 400, y: 100), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0),
            StrokePoint(location: CGPoint(x: 420, y: 200), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.1),
            StrokePoint(location: CGPoint(x: 430, y: 300), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.2),
            StrokePoint(location: CGPoint(x: 420, y: 400), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.3),
            StrokePoint(location: CGPoint(x: 400, y: 500), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.4),
        ])
        return [leftProfile, rightProfile]
    }

    // MARK: - Step 1: ContourAnalyzer

    func testStep1_ContourAnalyzer() {
        let strokes = sampleStrokes
        let allPoints = strokes.flatMap { $0.points.map(\.location) }
        print("📍 Input: \(allPoints.count) stroke points")
        print("📍 X range: \(allPoints.map(\.x).min()!) – \(allPoints.map(\.x).max()!)")
        print("📍 Y range: \(allPoints.map(\.y).min()!) – \(allPoints.map(\.y).max()!)")

        let contour = ContourAnalyzer.extractContour(from: strokes)
        print("📐 Contour: \(contour.count) hull points")
        for (i, p) in contour.enumerated() {
            print("   [\(i)] (\(p.x), \(p.y))")
        }

        XCTAssertGreaterThan(contour.count, 2, "Contour should have at least 3 points")
    }

    // MARK: - Step 2: SkeletonExtractor

    func testStep2_SkeletonExtractor() {
        let skeleton = SkeletonExtractor.extract(from: sampleStrokes, sampleCount: 10)

        print("🦴 Skeleton: \(skeleton.points.count) points")
        print("🦴 Axis: (\(skeleton.axis.dx), \(skeleton.axis.dy))")
        for (i, p) in skeleton.points.enumerated() {
            print("   [\(i)] pos=(\(p.position.x), \(p.position.y)) radius=\(p.radius)")
        }

        XCTAssertFalse(skeleton.isEmpty, "Skeleton should not be empty")
        for p in skeleton.points {
            XCTAssertGreaterThan(p.radius, 0, "Radius should be positive")
            XCTAssertFalse(p.position.x.isNaN, "Position should not be NaN")
            XCTAssertFalse(p.position.y.isNaN, "Position should not be NaN")
            XCTAssertFalse(p.radius.isNaN, "Radius should not be NaN")
        }
    }

    // MARK: - Step 3: Segmenter

    func testStep3_Segmenter() {
        let skeleton = SkeletonExtractor.extract(from: sampleStrokes, sampleCount: 10)
        let segments = Segmenter.segment(skeleton)

        print("✂️ Segments: \(segments.count)")
        for (i, seg) in segments.enumerated() {
            let radii = seg.points.map { $0.radius }
            print("   Segment \(i): \(seg.points.count) points, radii: \(radii.map { String(format: "%.1f", $0) })")
        }

        XCTAssertGreaterThan(segments.count, 0)
    }

    // MARK: - Step 4: PrimitiveFitter

    func testStep4_PrimitiveFitter() {
        let skeleton = SkeletonExtractor.extract(from: sampleStrokes, sampleCount: 10)
        let segments = Segmenter.segment(skeleton)

        print("🔧 Primitives:")
        for (i, seg) in segments.enumerated() {
            let primitive = PrimitiveFitter.fit(seg)
            print("   Segment \(i) → \(primitive.type)")
        }
    }

    // MARK: - Step 5: MeshAssembler

    func testStep5_MeshAssembler() {
        let skeleton = SkeletonExtractor.extract(from: sampleStrokes, sampleCount: 10)
        let segments = Segmenter.segment(skeleton)

        print("🧊 Meshes:")
        for (i, seg) in segments.enumerated() {
            let primitive = PrimitiveFitter.fit(seg)
            let mesh = MeshAssembler.assemble(from: primitive, radialSegments: 8)
            print("   Segment \(i): \(mesh.vertexCount) vertices, \(mesh.faceCount) faces")

            if !mesh.isEmpty {
                let positions = mesh.vertices.map { $0.position }
                let xs = positions.map(\.x), ys = positions.map(\.y), zs = positions.map(\.z)
                print("   X: \(xs.min()!) – \(xs.max()!)")
                print("   Y: \(ys.min()!) – \(ys.max()!)")
                print("   Z: \(zs.min()!) – \(zs.max()!)")

                // Check for NaN/Inf
                for v in mesh.vertices {
                    XCTAssertFalse(v.position.x.isNaN || v.position.y.isNaN || v.position.z.isNaN,
                                   "Vertex position contains NaN")
                    XCTAssertFalse(v.position.x.isInfinite || v.position.y.isInfinite || v.position.z.isInfinite,
                                   "Vertex position contains Infinity")
                }
            }
        }
    }

    // MARK: - Step 6: Full pipeline

    func testStep6_FullPipeline() {
        let result = InferencePipeline.infer(from: sampleStrokes)
        print("🏗️ Final mesh: \(result.mesh.vertexCount) vertices, \(result.mesh.faceCount) faces")
        print("🏗️ Source strokes: \(result.sourceStrokeIDs.count)")

        if !result.mesh.isEmpty {
            let positions = result.mesh.vertices.map { $0.position }
            let xs = positions.map(\.x), ys = positions.map(\.y), zs = positions.map(\.z)
            print("   X range: \(xs.min()!) – \(xs.max()!)")
            print("   Y range: \(ys.min()!) – \(ys.max()!)")
            print("   Z range: \(zs.min()!) – \(zs.max()!)")

            // Check mesh validity
            let maxIdx = UInt32(result.mesh.vertexCount)
            for face in result.mesh.faces {
                XCTAssertLessThan(face.indices.x, maxIdx, "Face index out of range")
                XCTAssertLessThan(face.indices.y, maxIdx, "Face index out of range")
                XCTAssertLessThan(face.indices.z, maxIdx, "Face index out of range")
            }
        }

        XCTAssertFalse(result.mesh.isEmpty, "Pipeline should produce a non-empty mesh")
    }
}
