import XCTest
@testable import Quill

final class TextBlockHitTests: XCTestCase {

    func testResizedBoxUsesStoredSizeExactly() {
        let block = TextBlock(text: "hi", x: 100, y: 50, width: 300, height: 90)
        // Stored box + the 8pt grace inset on every side.
        XCTAssertEqual(block.approxRect, CGRect(x: 92, y: 42, width: 316, height: 106))
    }

    func testAutoBlockRectContainsItsOrigin() {
        let block = TextBlock(text: "note", x: 40, y: 40)
        XCTAssertTrue(block.approxRect.contains(CGPoint(x: 40, y: 40)))
    }

    func testLongerTextWidensTheEstimate() {
        let short = TextBlock(text: "hi", x: 0, y: 0)
        let long = TextBlock(text: "a considerably longer line", x: 0, y: 0)
        XCTAssertGreaterThan(long.approxRect.width, short.approxRect.width)
    }

    func testMoreLinesDeepenTheEstimate() {
        let one = TextBlock(text: "one", x: 0, y: 0)
        let three = TextBlock(text: "one\ntwo\nthree", x: 0, y: 0)
        XCTAssertGreaterThan(three.approxRect.height, one.approxRect.height)
    }

    func testEstimateIsCappedAtFieldMaximum() {
        let block = TextBlock(text: String(repeating: "x", count: 500), x: 0, y: 0)
        XCTAssertLessThanOrEqual(block.approxRect.width, 360 + 16) // cap + insets
    }

    func testPointOutsideMisses() {
        let block = TextBlock(text: "hi", x: 100, y: 100)
        XCTAssertFalse(block.approxRect.contains(CGPoint(x: 600, y: 600)))
    }
}
