import XCTest
@testable import Quill

final class SketchStoreTests: XCTestCase {

    private var root: URL!
    private var store: SketchStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillTests-\(UUID().uuidString)", isDirectory: true)
        store = SketchStore(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testCreateSetsVersionForThisDevice() {
        let meta = store.create(title: "Hello")
        XCTAssertEqual(store.sketches.count, 1)
        XCTAssertEqual(meta.versions[store.deviceID], 1)
    }

    func testSaveBumpsVersionWhenAsked() {
        let meta = store.create()
        store.saveDrawing(meta.id, data: Data([1, 2]), bumpVersion: true)
        XCTAssertEqual(store.metadata(meta.id)?.versions[store.deviceID], 2)
        XCTAssertEqual(store.loadDrawing(meta.id), Data([1, 2]))
    }

    func testSaveDoesNotBumpWhenLiveCoEditing() {
        let meta = store.create()
        store.saveDrawing(meta.id, data: Data([9]), bumpVersion: false)
        XCTAssertEqual(store.metadata(meta.id)?.versions[store.deviceID], 1)
    }

    func testRenameBumpsVersion() {
        let meta = store.create(title: "Old")
        store.rename(meta.id, to: "New")
        XCTAssertEqual(store.metadata(meta.id)?.title, "New")
        XCTAssertEqual(store.metadata(meta.id)?.versions[store.deviceID], 2)
    }

    func testDeleteLeavesTombstone() {
        let meta = store.create()
        store.delete(meta.id)
        XCTAssertNil(store.metadata(meta.id))
        XCTAssertTrue(store.sketches.isEmpty)
        if case let .tombstone(v) = store.localState(meta.id) {
            XCTAssertEqual(v[store.deviceID], 1)
        } else {
            XCTFail("expected a tombstone after delete")
        }
    }

    func testApplyRemoteWritesAndClearsTombstone() {
        let id = UUID()
        store.adoptTombstone(id, versions: ["peer": 1])
        if case .tombstone = store.localState(id) {} else { XCTFail("expected tombstone") }

        let meta = SketchMetadata(id: id, title: "Resurrected",
                                  createdAt: Date(), updatedAt: Date(),
                                  versions: ["peer": 2])
        store.applyRemote(meta, drawing: Data([7]))
        XCTAssertEqual(store.metadata(id)?.title, "Resurrected")
        XCTAssertEqual(store.loadDrawing(id), Data([7]))
        if case .live = store.localState(id) {} else { XCTFail("expected live after applyRemote") }
    }

    func testLocalStateAbsentForUnknownID() {
        if case .absent = store.localState(UUID()) {} else { XCTFail("expected absent") }
    }

    // MARK: - Sections

    func testSectionCRUDAndMove() {
        let section = store.createSection(name: "School")
        XCTAssertEqual(store.sections.map(\.name), ["School"])

        let pad = store.create(title: "Notes", in: section.id)
        XCTAssertEqual(store.metadata(pad.id)?.sectionID, section.id)

        store.renameSection(section.id, to: "Uni")
        XCTAssertEqual(store.section(section.id)?.name, "Uni")
        XCTAssertEqual(store.section(section.id)?.versions[store.deviceID], 2)

        store.moveSketch(pad.id, to: nil)
        XCTAssertNil(store.metadata(pad.id)?.sectionID)
        XCTAssertEqual(store.metadata(pad.id)?.versions[store.deviceID], 2) // move bumps

        store.deleteSection(section.id)
        XCTAssertTrue(store.sections.isEmpty)
        XCTAssertNotNil(store.sectionTombstones[section.id])
    }

    func testDeleteSectionMovesPadsToUnfiled() {
        let section = store.createSection(name: "Temp")
        let pad = store.create(title: "Inside", in: section.id)
        store.deleteSection(section.id)
        XCTAssertNil(store.metadata(pad.id)?.sectionID)   // pad survives, unfiled
        XCTAssertNotNil(store.metadata(pad.id))
    }

    func testSectionsSurviveReload() {
        let section = store.createSection(name: "Persist")
        let fresh = SketchStore(root: root)
        XCTAssertEqual(fresh.sections.map(\.id), [section.id])
    }

    // MARK: - Paper

    func testSetPaperPersistsAndBumps() {
        let pad = store.create()
        store.setPaper(pad.id, .grid)
        XCTAssertEqual(store.metadata(pad.id)?.paper, .grid)
        XCTAssertEqual(store.metadata(pad.id)?.versions[store.deviceID], 2)
        store.setPaper(pad.id, .dots, bumpVersion: false)
        XCTAssertEqual(store.metadata(pad.id)?.paper, .dots)
        XCTAssertEqual(store.metadata(pad.id)?.versions[store.deviceID], 2)
    }

    // MARK: - Text blocks

    func testTextsSaveLoadAndBump() {
        let pad = store.create()
        XCTAssertEqual(store.loadTexts(pad.id), [])

        let blocks = [TextBlock(text: "hi", x: 5, y: 6)]
        store.saveTexts(pad.id, blocks)
        XCTAssertEqual(store.loadTexts(pad.id), blocks)
        XCTAssertEqual(store.metadata(pad.id)?.versions[store.deviceID], 2)

        store.saveTexts(pad.id, [], bumpVersion: false)
        XCTAssertEqual(store.loadTexts(pad.id), [])
        XCTAssertEqual(store.metadata(pad.id)?.versions[store.deviceID], 2)
    }

    func testApplyRemoteCarriesTexts() {
        let id = UUID()
        let meta = SketchMetadata(id: id, title: "T", createdAt: Date(), updatedAt: Date(),
                                  versions: ["peer": 1])
        let blocks = [TextBlock(text: "from peer", x: 1, y: 2)]
        store.applyRemote(meta, drawing: Data([1]), texts: blocks)
        XCTAssertEqual(store.loadTexts(id), blocks)
    }

    func testDeleteRemovesTexts() {
        let pad = store.create()
        store.saveTexts(pad.id, [TextBlock(text: "x", x: 0, y: 0)])
        store.delete(pad.id)
        XCTAssertEqual(store.loadTexts(pad.id), [])
    }

    func testTextBlockWithoutSizeDecodesFromStyleOrBody() throws {
        // Pre-size block with a legacy style → style's size.
        let styled = """
        {"id":"\(UUID().uuidString)","text":"old","x":1,"y":2,"style":"title"}
        """
        XCTAssertEqual(try JSONDecoder().decode(TextBlock.self,
                                                from: styled.data(using: .utf8)!).size, 28)
        // Pre-style block → body size.
        let bare = """
        {"id":"\(UUID().uuidString)","text":"old","x":1,"y":2}
        """
        XCTAssertEqual(try JSONDecoder().decode(TextBlock.self,
                                                from: bare.data(using: .utf8)!).size, 17)
    }

    func testTextBlockSizeRoundTrips() throws {
        let block = TextBlock(text: "t", x: 0, y: 0, size: 31)
        let decoded = try JSONDecoder().decode(TextBlock.self, from: JSONEncoder().encode(block))
        XCTAssertEqual(decoded, block)
    }

    // MARK: - Search

    func testSearchMatchesTitleAndTextContent() {
        let alpha = store.create(title: "Groceries")
        let beta = store.create(title: "Physics")
        store.saveTexts(beta.id, [TextBlock(text: "quantum entanglement", x: 0, y: 0)])

        XCTAssertEqual(store.search("groc").map(\.id), [alpha.id])   // title, case-insensitive
        XCTAssertEqual(store.search("entangle").map(\.id), [beta.id]) // block content
        XCTAssertTrue(store.search("zzz").isEmpty)
        XCTAssertEqual(store.search("  ").count, 2)                   // blank → everything
    }

    // MARK: - Back-compat

    func testOldMetadataWithoutNewFieldsStillLoads() throws {
        // JSON as written by the pre-sections/pre-paper build (Date = seconds
        // since reference date, JSONEncoder default).
        let id = UUID()
        let old = """
        {"id":"\(id.uuidString)","title":"Legacy","createdAt":700000000,
         "updatedAt":700000001,"versions":{"x":3}}
        """
        try old.data(using: .utf8)!.write(
            to: root.appendingPathComponent("\(id.uuidString).meta.json"))
        store.reload()

        let meta = store.metadata(id)
        XCTAssertEqual(meta?.title, "Legacy")
        XCTAssertEqual(meta?.versions, ["x": 3])
        XCTAssertNil(meta?.sectionID)
        XCTAssertEqual(meta?.paper, .blank)
    }
}
