import XCTest
import simd
@testable import PenSculpt

final class SurfaceStrokeColorTests: XCTestCase {

    func testCodableRoundTripPreservesColor() throws {
        let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        let stroke = SurfaceStroke(
            points: [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 1, 1)],
            widths: [3, 3],
            opacity: 0.8,
            color: red
        )
        let data = try JSONEncoder().encode(stroke)
        let decoded = try JSONDecoder().decode(SurfaceStroke.self, from: data)
        XCTAssertEqual(decoded.color, red)
    }

    func testLegacyDecodeFallsBackToHistoricBlue() throws {
        // JSON without `color` field — represents docs saved before this feature.
        // SIMD3<Float> serializes as a flat [x, y, z] array.
        let legacyJSON = """
        {
            "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            "points": [[0, 0, 0], [1, 1, 1]],
            "widths": [3, 3],
            "opacity": 1
        }
        """.data(using: .utf8)!

        let historicBlue = CodableColor(red: 0.2, green: 0.2, blue: 0.8, alpha: 1)
        let decoded = try JSONDecoder().decode(SurfaceStroke.self, from: legacyJSON)
        XCTAssertEqual(decoded.color, historicBlue)
    }
}
