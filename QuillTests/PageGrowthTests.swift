import XCTest
@testable import Quill

final class PageGrowthTests: XCTestCase {

    func testEmptyPadIsOneViewportInSize() {
        XCTAssertEqual(PageGrowth.extent(current: 0, viewport: 800, contentEdge: 0), 800)
    }

    func testContentClearOfMarginDoesNotGrow() {
        // Edge band starts at 800 − 220 = 580; content before it leaves the page alone.
        XCTAssertEqual(PageGrowth.extent(current: 800, viewport: 800, contentEdge: 579), 800)
    }

    func testContentInMarginBandGrows() {
        let grown = PageGrowth.extent(current: 800, viewport: 800, contentEdge: 700)
        XCTAssertEqual(grown, 700 + PageGrowth.chunk)
    }

    func testContentAtExactMarginEdgeDoesNotGrow() {
        XCTAssertEqual(PageGrowth.extent(current: 800, viewport: 800, contentEdge: 580), 800)
    }

    func testRepeatedWritingKeepsExtending() {
        var extent = PageGrowth.extent(current: 0, viewport: 800, contentEdge: 0)
        for edge in stride(from: CGFloat(700), through: 5000, by: 300) {
            extent = PageGrowth.extent(current: extent, viewport: 800, contentEdge: edge)
            XCTAssertGreaterThanOrEqual(extent - edge, PageGrowth.margin,
                                        "page must always keep at least a margin of fresh space")
        }
    }

    func testNeverShrinks() {
        // Ink erased back to the origin: the session's page size stays.
        XCTAssertEqual(PageGrowth.extent(current: 2000, viewport: 800, contentEdge: 0), 2000)
    }

    func testViewportIsTheFloor() {
        // Rotation to a larger viewport lifts the page to fill it.
        XCTAssertEqual(PageGrowth.extent(current: 700, viewport: 1100, contentEdge: 0), 1100)
    }

    func testGrowthTriggeredByContentBeyondCurrentPage() {
        // Peer content past the page edge (e.g. Mac ink beyond the iPad's
        // narrower width) extends the page past it.
        let grown = PageGrowth.extent(current: 800, viewport: 800, contentEdge: 1200)
        XCTAssertEqual(grown, 1200 + PageGrowth.chunk)
    }

    func testNarrowViewportStillReachesWidePeerContent() {
        // iPad portrait (820 wide) opening a pad with Mac ink out at x=1400:
        // the width must grow past the ink, not clamp to the viewport.
        let width = PageGrowth.extent(current: 0, viewport: 820, contentEdge: 1400)
        XCTAssertGreaterThan(width, 1400)
    }
}
