import XCTest
@testable import PenSculpt

final class TooltipIDTests: XCTestCase {
    func testEveryCaseHasNonEmptyTitle() {
        for id in TooltipID.allCases {
            XCTAssertFalse(id.content.title.isEmpty, "TooltipID.\(id) has empty title")
        }
    }

    func testTitlesAreNotPlaceholders() {
        for id in TooltipID.allCases {
            let title = id.content.title
            XCTAssertFalse(title.uppercased().contains("TODO"), "TooltipID.\(id) title is a placeholder: \(title)")
            XCTAssertFalse(title.uppercased().contains("TBD"), "TooltipID.\(id) title is a placeholder: \(title)")
        }
    }

    func testSubtitlesWhenPresentAreNonEmpty() {
        for id in TooltipID.allCases {
            if let subtitle = id.content.subtitle {
                XCTAssertFalse(subtitle.isEmpty, "TooltipID.\(id) subtitle is empty string (use nil instead)")
            }
        }
    }

    func testCasesAreUnique() {
        let raws = TooltipID.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count, "Duplicate raw values in TooltipID")
    }
}
