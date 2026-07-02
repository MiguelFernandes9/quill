import XCTest
import PencilKit
@testable import Quill

final class HomeModelsTests: XCTestCase {

    private func digest(_ title: String, section: UUID? = nil) -> SketchDigest {
        SketchDigest(id: UUID(), title: title, updatedAt: Date(timeIntervalSince1970: 0),
                     versions: [:], sectionID: section)
    }

    // MARK: - Snippets

    func testSnippetWindowsAroundMatch() throws {
        let text = String(repeating: "a", count: 100) + "garage fuse box" + String(repeating: "b", count: 100)
        let (snippet, range) = try XCTUnwrap(SearchEngine.snippet(for: "garage", in: text))
        XCTAssertTrue(snippet.hasPrefix("…"))
        XCTAssertTrue(snippet.hasSuffix("…"))
        XCTAssertTrue(snippet.localizedCaseInsensitiveContains("garage fuse box"))
        XCTAssertLessThan(snippet.count, 70)
        XCTAssertNotNil(range)
        XCTAssertEqual(snippet[try XCTUnwrap(range)].lowercased(), "garage")
    }

    func testSnippetShortTextNoEllipses() throws {
        let (snippet, _) = try XCTUnwrap(SearchEngine.snippet(for: "fuse", in: "check fuse box"))
        XCTAssertEqual(snippet, "check fuse box")
    }

    func testSnippetCaseInsensitive() {
        XCTAssertNotNil(SearchEngine.snippet(for: "GARAGE", in: "the garage door"))
        XCTAssertNil(SearchEngine.snippet(for: "attic", in: "the garage door"))
    }

    // MARK: - Conflict pairing

    func testPairsForkWithOriginal() {
        let original = digest("Garden layout")
        let fork = digest("Garden layout (conflict)")
        let other = digest("Kitchen reno")
        let result = pairConflicts([original, fork, other])
        XCTAssertEqual(result.plain.map(\.id), [other.id])
        XCTAssertEqual(result.pairs.count, 1)
        XCTAssertEqual(result.pairs[0].original?.id, original.id)
        XCTAssertEqual(result.pairs[0].fork.id, fork.id)
    }

    func testPrefersSameSectionOriginal() {
        let section = UUID()
        let elsewhere = digest("Plan")
        let sameSection = digest("Plan", section: section)
        let fork = digest("Plan (conflict)", section: section)
        let result = pairConflicts([elsewhere, sameSection, fork])
        XCTAssertEqual(result.pairs[0].original?.id, sameSection.id)
        XCTAssertEqual(result.plain.map(\.id), [elsewhere.id]) // other original stays plain
    }

    func testOrphanForkSurvivesWithoutOriginal() {
        let fork = digest("Ghost (conflict)")
        let result = pairConflicts([fork])
        XCTAssertTrue(result.plain.isEmpty)
        XCTAssertEqual(result.pairs.count, 1)
        XCTAssertNil(result.pairs[0].original)
    }

    // MARK: - Peer labels

    func testPeerLabelStripsSuffixAndDetectsDevice() {
        XCTAssertEqual(PeerLabel.clean("Miguel's iPad-3F2A"), "Miguel's iPad")
        XCTAssertEqual(PeerLabel.short("Miguel's iPad-3F2A"), "iPad")
        XCTAssertEqual(PeerLabel.short("Miguel's MacBook Air-01ab"), "Mac")
        XCTAssertEqual(PeerLabel.clean("PlainName"), "PlainName")
        XCTAssertEqual(PeerLabel.short(nil), "Device")
    }

    // MARK: - Thumbnails

    func testThumbnailFreshness() {
        let d = SketchDigest(id: UUID(), title: "T", updatedAt: Date(timeIntervalSince1970: 50))
        XCTAssertTrue(ThumbnailStore.isFresh(cachedStamp: Date(timeIntervalSince1970: 50), digest: d))
        XCTAssertFalse(ThumbnailStore.isFresh(cachedStamp: Date(timeIntervalSince1970: 49), digest: d))
        XCTAssertFalse(ThumbnailStore.isFresh(cachedStamp: nil, digest: d))
    }

    func testRenderProducesImageForDrawingAndEmpty() {
        // Empty drawing → still an image (blank thumbnail), no crash.
        let empty = ThumbnailStore.render(drawingData: Data(), size: CGSize(width: 160, height: 110))
        XCTAssertNotNil(empty)
        XCTAssertNil(ThumbnailStore.render(drawingData: Data(), size: .zero))
    }

    func testRenderIncludesTextBlocks() throws {
        // Text-only pad: bounds derive from the block, and the rendered image
        // differs from the blank render (the text was actually drawn).
        let blocks = [TextBlock(text: "hello thumbnail", x: 40, y: 40, size: 20)]
        let size = CGSize(width: 160, height: 110)
        let withText = try XCTUnwrap(ThumbnailStore.render(drawingData: Data(),
                                                           texts: blocks, size: size))
        let blank = try XCTUnwrap(ThumbnailStore.render(drawingData: Data(), size: size))
        XCTAssertNotEqual(withText.pngData(), blank.pngData())
    }
}
