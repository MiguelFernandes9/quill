import XCTest
@testable import Quill

final class PageGrowthTests: XCTestCase {

    func testEmptyPadIsOneViewportTall() {
        XCTAssertEqual(PageGrowth.height(current: 0, viewport: 800, contentBottom: 0), 800)
    }

    func testContentClearOfMarginDoesNotGrow() {
        // Bottom band starts at 800 − 220 = 580; content above it leaves the page alone.
        XCTAssertEqual(PageGrowth.height(current: 800, viewport: 800, contentBottom: 579), 800)
    }

    func testContentInMarginBandGrows() {
        let grown = PageGrowth.height(current: 800, viewport: 800, contentBottom: 700)
        XCTAssertEqual(grown, 700 + PageGrowth.chunk)
    }

    func testContentAtExactMarginEdgeDoesNotGrow() {
        XCTAssertEqual(PageGrowth.height(current: 800, viewport: 800, contentBottom: 580), 800)
    }

    func testRepeatedWritingKeepsExtending() {
        var height = PageGrowth.height(current: 0, viewport: 800, contentBottom: 0)
        for bottom in stride(from: CGFloat(700), through: 5000, by: 300) {
            height = PageGrowth.height(current: height, viewport: 800, contentBottom: bottom)
            XCTAssertGreaterThanOrEqual(height - bottom, PageGrowth.margin,
                                        "page must always keep at least a margin of fresh space")
        }
    }

    func testNeverShrinks() {
        // Ink erased back to the top: the session's page height stays.
        XCTAssertEqual(PageGrowth.height(current: 2000, viewport: 800, contentBottom: 0), 2000)
    }

    func testViewportIsTheFloor() {
        // Rotation to a taller viewport lifts the page to fill it.
        XCTAssertEqual(PageGrowth.height(current: 700, viewport: 1100, contentBottom: 0), 1100)
    }

    func testGrowthTriggeredByHintBeyondCurrentPage() {
        // A text block dragged below the page bottom extends past it.
        let grown = PageGrowth.height(current: 800, viewport: 800, contentBottom: 1200)
        XCTAssertEqual(grown, 1200 + PageGrowth.chunk)
    }
}
