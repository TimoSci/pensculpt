import XCTest
@testable import PenSculpt

final class GrowOriginTests: XCTestCase {

    func testStrokeOriginExposesAnchorPoint() {
        let id = UUID()
        let origin = GrowOrigin.stroke(strokeID: id, anchor: CGPoint(x: 50, y: 50))
        XCTAssertEqual(origin.anchor, CGPoint(x: 50, y: 50))
    }

    func testPointOriginExposesAnchorPoint() {
        let origin = GrowOrigin.point(CGPoint(x: 100, y: 200))
        XCTAssertEqual(origin.anchor, CGPoint(x: 100, y: 200))
    }

    func testInitialStrokeIDForStrokeOrigin() {
        let id = UUID()
        let origin = GrowOrigin.stroke(strokeID: id, anchor: .zero)
        XCTAssertEqual(origin.initialStrokeID, id)
    }

    func testInitialStrokeIDNilForPointOrigin() {
        XCTAssertNil(GrowOrigin.point(.zero).initialStrokeID)
    }
}
