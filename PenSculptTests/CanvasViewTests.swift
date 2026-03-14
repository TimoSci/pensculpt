import XCTest
import PencilKit
@testable import PenSculpt

final class CanvasViewTests: XCTestCase {

    private func makePKStroke(at point: CGPoint) -> PKStroke {
        let points = [
            PKStrokePoint(location: point, timeOffset: 0,
                          size: CGSize(width: 5, height: 5), opacity: 1,
                          force: 1, azimuth: 0, altitude: .pi / 4)
        ]
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        return PKStroke(ink: PKInk(.pen, color: .black), path: path)
    }

    func testRemovedIndicesNoneRemoved() {
        let strokes = [
            makePKStroke(at: CGPoint(x: 0, y: 0)),
            makePKStroke(at: CGPoint(x: 100, y: 100)),
            makePKStroke(at: CGPoint(x: 200, y: 200))
        ]
        let result = CanvasView.removedStrokeIndices(previous: strokes, current: strokes)
        XCTAssertTrue(result.isEmpty)
    }

    func testRemovedIndicesSingleRemoved() {
        let s0 = makePKStroke(at: CGPoint(x: 0, y: 0))
        let s1 = makePKStroke(at: CGPoint(x: 100, y: 100))
        let s2 = makePKStroke(at: CGPoint(x: 200, y: 200))
        let result = CanvasView.removedStrokeIndices(
            previous: [s0, s1, s2],
            current: [s0, s2]
        )
        XCTAssertEqual(result, [1])
    }

    func testRemovedIndicesFirstRemoved() {
        let s0 = makePKStroke(at: CGPoint(x: 0, y: 0))
        let s1 = makePKStroke(at: CGPoint(x: 100, y: 100))
        let s2 = makePKStroke(at: CGPoint(x: 200, y: 200))
        let result = CanvasView.removedStrokeIndices(
            previous: [s0, s1, s2],
            current: [s1, s2]
        )
        XCTAssertEqual(result, [0])
    }

    func testRemovedIndicesLastRemoved() {
        let s0 = makePKStroke(at: CGPoint(x: 0, y: 0))
        let s1 = makePKStroke(at: CGPoint(x: 100, y: 100))
        let s2 = makePKStroke(at: CGPoint(x: 200, y: 200))
        let result = CanvasView.removedStrokeIndices(
            previous: [s0, s1, s2],
            current: [s0, s1]
        )
        XCTAssertEqual(result, [2])
    }

    func testRemovedIndicesMultipleRemoved() {
        let s0 = makePKStroke(at: CGPoint(x: 0, y: 0))
        let s1 = makePKStroke(at: CGPoint(x: 100, y: 100))
        let s2 = makePKStroke(at: CGPoint(x: 200, y: 200))
        let s3 = makePKStroke(at: CGPoint(x: 300, y: 300))
        let result = CanvasView.removedStrokeIndices(
            previous: [s0, s1, s2, s3],
            current: [s0, s3]
        )
        XCTAssertEqual(result, [1, 2])
    }

    func testRemovedIndicesAllRemoved() {
        let strokes = [
            makePKStroke(at: CGPoint(x: 0, y: 0)),
            makePKStroke(at: CGPoint(x: 100, y: 100))
        ]
        let result = CanvasView.removedStrokeIndices(previous: strokes, current: [])
        XCTAssertEqual(result, [0, 1])
    }

    func testRemovedIndicesBothEmpty() {
        let result = CanvasView.removedStrokeIndices(previous: [], current: [])
        XCTAssertTrue(result.isEmpty)
    }
}
