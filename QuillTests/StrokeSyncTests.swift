import XCTest
@testable import Quill

final class StrokeSyncTests: XCTestCase {

    func testNewPenStrokesAppendFromBaseline() {
        XCTAssertEqual(StrokeSync.action(erasing: false, count: 5, lastSynced: 3),
                       .appendDelta(from: 3))
    }

    func testUnchangedCountIsNoop() {
        XCTAssertEqual(StrokeSync.action(erasing: false, count: 3, lastSynced: 3), .none)
    }

    func testUndoResyncs() {
        // Count dropped without the eraser active (undo, programmatic removal).
        XCTAssertEqual(StrokeSync.action(erasing: false, count: 2, lastSynced: 3), .resync)
    }

    func testVectorEraseResyncs() {
        XCTAssertEqual(StrokeSync.action(erasing: true, count: 2, lastSynced: 3), .resync)
    }

    func testBitmapEraseSplitResyncsDespiteCountRise() {
        // The bitmap eraser can SPLIT a stroke: count goes UP while content
        // shrank. Treating that as an append would ship garbage fragments.
        XCTAssertEqual(StrokeSync.action(erasing: true, count: 4, lastSynced: 3), .resync)
    }

    func testBitmapEraseShorteningResyncsDespiteEqualCount() {
        XCTAssertEqual(StrokeSync.action(erasing: true, count: 3, lastSynced: 3), .resync)
    }
}
