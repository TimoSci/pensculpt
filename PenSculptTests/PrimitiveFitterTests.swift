import XCTest
@testable import PenSculpt

final class PrimitiveFitterTests: XCTestCase {

    private func makeSegment(radii: [CGFloat]) -> SkeletonSegment {
        let points = radii.enumerated().map { i, r in
            SkeletonPoint(position: CGPoint(x: CGFloat(i) * 10, y: 0), radius: r)
        }
        return SkeletonSegment(points: points)
    }

    // MARK: - Classification

    func testConstantRadiusFitsCylinder() {
        let segment = makeSegment(radii: [10, 10, 10, 10, 10])
        let result = PrimitiveFitter.fit(segment)
        if case .cylinder(let r) = result.type {
            XCTAssertEqual(r, 10, accuracy: 0.5)
        } else {
            XCTFail("Expected cylinder, got \(result.type)")
        }
    }

    func testNearlyConstantRadiusFitsCylinder() {
        let segment = makeSegment(radii: [10, 10.5, 9.8, 10.2, 10.1])
        let result = PrimitiveFitter.fit(segment)
        if case .cylinder = result.type { } else {
            XCTFail("Expected cylinder for near-constant radii, got \(result.type)")
        }
    }

    func testLinearTaperFitsCone() {
        let segment = makeSegment(radii: [20, 17, 14, 11, 8, 5])
        let result = PrimitiveFitter.fit(segment)
        if case .cone(let startR, let endR) = result.type {
            XCTAssertEqual(startR, 20, accuracy: 1)
            XCTAssertEqual(endR, 5, accuracy: 1)
        } else {
            XCTFail("Expected cone, got \(result.type)")
        }
    }

    func testSymmetricPeakFitsSphere() {
        // Radius increases then decreases symmetrically
        let segment = makeSegment(radii: [5, 8, 10, 10, 8, 5])
        let result = PrimitiveFitter.fit(segment)
        if case .sphere(let r) = result.type {
            XCTAssertEqual(r, 10, accuracy: 1)
        } else {
            XCTFail("Expected sphere, got \(result.type)")
        }
    }

    func testIrregularProfileFitsCustom() {
        // Random-looking radii with no clear pattern
        let segment = makeSegment(radii: [5, 20, 3, 18, 7, 15, 2])
        let result = PrimitiveFitter.fit(segment)
        XCTAssertEqual(result.type, .custom)
    }

    func testSinglePointFitsCylinder() {
        let segment = makeSegment(radii: [8])
        let result = PrimitiveFitter.fit(segment)
        if case .cylinder(let r) = result.type {
            XCTAssertEqual(r, 8, accuracy: 0.1)
        } else {
            XCTFail("Single point should fit cylinder")
        }
    }

    // MARK: - Analysis helpers

    func testLinearSlopeFlat() {
        let slope = PrimitiveFitter.linearSlope([5, 5, 5, 5])
        XCTAssertEqual(slope, 0, accuracy: 0.01)
    }

    func testLinearSlopeIncreasing() {
        let slope = PrimitiveFitter.linearSlope([0, 5, 10, 15, 20])
        XCTAssertGreaterThan(slope, 0)
    }

    func testLinearSlopeDecreasing() {
        let slope = PrimitiveFitter.linearSlope([20, 15, 10, 5, 0])
        XCTAssertLessThan(slope, 0)
    }

    func testIsSymmetricPeakTrue() {
        XCTAssertTrue(PrimitiveFitter.isSymmetricPeak([2, 5, 8, 10, 8, 5, 2]))
    }

    func testIsSymmetricPeakFalseAsymmetric() {
        XCTAssertFalse(PrimitiveFitter.isSymmetricPeak([2, 10, 10, 10, 2, 1, 1]))
    }

    func testIsSymmetricPeakFalseTooFewPoints() {
        XCTAssertFalse(PrimitiveFitter.isSymmetricPeak([5, 10]))
    }

    // MARK: - Segment preserved

    func testFittedPrimitivePreservesSegment() {
        let segment = makeSegment(radii: [10, 10, 10])
        let result = PrimitiveFitter.fit(segment)
        XCTAssertEqual(result.segment, segment)
    }
}
