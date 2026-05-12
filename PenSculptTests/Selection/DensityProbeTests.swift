import XCTest
@testable import PenSculpt

final class DensityProbeTests: XCTestCase {

    private func stroke(at points: [CGPoint], id: UUID = UUID()) -> Stroke {
        let sps = points.map {
            StrokePoint(location: $0, pressure: 1, tilt: 0, azimuth: 0, timestamp: 0)
        }
        return Stroke(id: id, points: sps)
    }

    func testReturnsNilWhenNoCandidates() {
        let result = DensityProbe.minimumDeltaR(
            currentRadius: 10,
            frontier: [CGPoint(x: 0, y: 0)],
            candidates: []
        )
        XCTAssertNil(result)
    }

    func testReturnsDistanceMinusRadiusForSingleCandidate() {
        // Frontier at origin; candidate at (50, 0); current radius 10.
        // Distance is 50, so deltaR needed = 50 - 10 = 40.
        let candidate = stroke(at: [CGPoint(x: 50, y: 0)])
        let result = DensityProbe.minimumDeltaR(
            currentRadius: 10,
            frontier: [.zero],
            candidates: [candidate]
        )
        XCTAssertEqual(result ?? 0, 40, accuracy: 0.01)
    }

    func testReturnsZeroWhenCandidateAlreadyWithinRadius() {
        // Candidate distance < current radius → delta is 0 (clamped, not negative).
        let candidate = stroke(at: [CGPoint(x: 5, y: 0)])
        let result = DensityProbe.minimumDeltaR(
            currentRadius: 10,
            frontier: [.zero],
            candidates: [candidate]
        )
        XCTAssertEqual(result ?? -1, 0, accuracy: 0.01)
    }

    func testReturnsNearestCandidateAcrossMany() {
        // Three candidates at distances 80, 30, 200; nearest = 30; radius 10 → delta 20.
        let near = stroke(at: [CGPoint(x: 30, y: 0)])
        let mid  = stroke(at: [CGPoint(x: 80, y: 0)])
        let far  = stroke(at: [CGPoint(x: 200, y: 0)])
        let result = DensityProbe.minimumDeltaR(
            currentRadius: 10,
            frontier: [.zero],
            candidates: [far, near, mid]
        )
        XCTAssertEqual(result ?? 0, 20, accuracy: 0.01)
    }

    func testUsesNearestPointOfMultipointStroke() {
        // Stroke spans (40,0)→(20,0)→(60,0); nearest point is (20,0).
        let s = stroke(at: [CGPoint(x: 40, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 60, y: 0)])
        let result = DensityProbe.minimumDeltaR(
            currentRadius: 0,
            frontier: [.zero],
            candidates: [s]
        )
        XCTAssertEqual(result ?? 0, 20, accuracy: 0.01)
    }
}
