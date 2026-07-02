import XCTest
@testable import Quill

final class SyncMessageTests: XCTestCase {

    func testOpenAndCloseRoundTrip() throws {
        let open = SyncMessage.openSketch(id: UUID())
        XCTAssertEqual(try SyncMessage.decode(open.encoded()), open)
        let close = SyncMessage.closeSketch(id: UUID())
        XCTAssertEqual(try SyncMessage.decode(close.encoded()), close)
    }

    func testStrokesRoundTrip() throws {
        let message = SyncMessage.strokes(sketchID: UUID(), data: Data([0, 1, 2, 255, 128]))
        XCTAssertEqual(try SyncMessage.decode(message.encoded()), message)
    }

    func testCursorRoundTrip() throws {
        let message = SyncMessage.cursor(sketchID: UUID(), x: 12.5, y: -3.0, down: true)
        XCTAssertEqual(try SyncMessage.decode(message.encoded()), message)
    }

    func testManifestRoundTrip() throws {
        let digests = [
            SketchDigest(id: UUID(), title: "One", updatedAt: Date(timeIntervalSince1970: 100),
                         versions: ["a": 1], sectionID: UUID(), paper: .grid),
        ]
        let tombs = [SketchTombstone(id: UUID(), versions: ["b": 2])]
        let sections = [SectionMetadata(id: UUID(), name: "School",
                                        createdAt: Date(timeIntervalSince1970: 1),
                                        updatedAt: Date(timeIntervalSince1970: 2),
                                        versions: ["a": 1])]
        let secTombs = [SketchTombstone(id: UUID(), versions: ["a": 4])]
        let message = SyncMessage.manifest(deviceID: "dev-a", sketches: digests, tombstones: tombs,
                                           sections: sections, sectionTombstones: secTombs)
        XCTAssertEqual(try SyncMessage.decode(message.encoded()), message)
    }

    func testDeleteSketchRoundTrip() throws {
        let message = SyncMessage.deleteSketch(id: UUID(), versions: ["a": 3])
        XCTAssertEqual(try SyncMessage.decode(message.encoded()), message)
    }

    func testDeleteSectionRoundTrip() throws {
        let message = SyncMessage.deleteSection(id: UUID(), versions: ["b": 1])
        XCTAssertEqual(try SyncMessage.decode(message.encoded()), message)
    }

    func testSetPaperRoundTrip() throws {
        let message = SyncMessage.setPaper(sketchID: UUID(), paper: .dots)
        XCTAssertEqual(try SyncMessage.decode(message.encoded()), message)
    }

    func testFullSketchRoundTrip() throws {
        let meta = SketchMetadata(id: UUID(), title: "Doodle",
                                  createdAt: Date(timeIntervalSince1970: 1),
                                  updatedAt: Date(timeIntervalSince1970: 2),
                                  versions: ["a": 1])
        let blocks = [TextBlock(text: "hello", x: 10, y: 20)]
        let message = SyncMessage.fullSketch(meta: meta, data: Data([9, 8, 7]), texts: blocks)
        XCTAssertEqual(try SyncMessage.decode(message.encoded()), message)
    }

    func testTextsRoundTrip() throws {
        let blocks = [
            TextBlock(text: "note", x: 1.5, y: -2),
            TextBlock(text: "", x: 0, y: 0),
        ]
        let message = SyncMessage.texts(sketchID: UUID(), texts: blocks)
        XCTAssertEqual(try SyncMessage.decode(message.encoded()), message)
    }

    func testApplyResolutionRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 5)
        let canonical = SketchMetadata(id: UUID(), title: "A", createdAt: now, updatedAt: now,
                                       versions: ["a": 2, "b": 1])
        let conflict = SketchMetadata(id: UUID(), title: "A (conflict)", createdAt: now, updatedAt: now,
                                      versions: ["a": 1])
        let message = SyncMessage.applyResolution(canonicalMeta: canonical, canonicalData: Data([1]),
                                                  canonicalTexts: [TextBlock(text: "c", x: 1, y: 2)],
                                                  conflictMeta: conflict, conflictData: Data([2]),
                                                  conflictTexts: [])
        XCTAssertEqual(try SyncMessage.decode(message.encoded()), message)
    }
}
