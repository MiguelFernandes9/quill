import XCTest
@testable import Quill

final class SectionSyncTests: XCTestCase {

    private func section(_ id: UUID, _ name: String, at t: TimeInterval,
                         _ versions: VersionVector) -> SectionMetadata {
        SectionMetadata(id: id, name: name,
                        createdAt: Date(timeIntervalSince1970: 0),
                        updatedAt: Date(timeIntervalSince1970: t),
                        versions: versions)
    }

    // MARK: mergeSections — determinism is what makes resolver-less LWW safe

    func testMergeIsSymmetric() {
        let id = UUID()
        let a = section(id, "Alpha", at: 100, ["a": 2, "b": 1])
        let b = section(id, "Beta", at: 200, ["a": 1, "b": 2])
        let ab = mergeSections(a, b)
        let ba = mergeSections(b, a)
        XCTAssertEqual(ab, ba)                       // both orders converge
        XCTAssertEqual(ab.name, "Beta")              // newer updatedAt wins
        XCTAssertEqual(ab.versions, ["a": 2, "b": 2]) // merged vector dominates both
    }

    func testMergeTieBreaksByName() {
        let id = UUID()
        let a = section(id, "Alpha", at: 100, ["a": 2])
        let b = section(id, "Beta", at: 100, ["b": 2])
        XCTAssertEqual(mergeSections(a, b).name, "Beta")   // lexicographically larger
        XCTAssertEqual(mergeSections(b, a).name, "Beta")
    }

    func testMergedResultDominatesBothInputs() {
        let id = UUID()
        let a = section(id, "A", at: 100, ["a": 3])
        let b = section(id, "B", at: 50, ["b": 4])
        let merged = mergeSections(a, b)
        XCTAssertTrue(VV.strictlyDominates(merged.versions, VersionVector()) )
        XCTAssertTrue(VV.dominatesOrEqual(merged.versions, a.versions))
        XCTAssertTrue(VV.dominatesOrEqual(merged.versions, b.versions))
    }

    // MARK: reconcileSections

    func testAdoptUnknownSection() {
        let remote = section(UUID(), "New", at: 10, ["b": 1])
        let actions = reconcileSections(localSections: [], localTombstones: [],
                                        peerSections: [remote], peerTombstones: [])
        XCTAssertEqual(actions, [.adopt(remote)])
    }

    func testAdoptWhenPeerStrictlyNewer() {
        let id = UUID()
        let mine = section(id, "Old", at: 10, ["a": 1])
        let theirs = section(id, "New", at: 20, ["a": 1, "b": 1])
        let actions = reconcileSections(localSections: [mine], localTombstones: [],
                                        peerSections: [theirs], peerTombstones: [])
        XCTAssertEqual(actions, [.adopt(theirs)])
    }

    func testNoActionWhenIAmNewerOrEqual() {
        let id = UUID()
        let mine = section(id, "Mine", at: 20, ["a": 2])
        let theirs = section(id, "Theirs", at: 10, ["a": 1])
        XCTAssertEqual(reconcileSections(localSections: [mine], localTombstones: [],
                                         peerSections: [theirs], peerTombstones: []), [])
        XCTAssertEqual(reconcileSections(localSections: [mine], localTombstones: [],
                                         peerSections: [mine], peerTombstones: []), [])
    }

    func testConcurrentRenameConvergesToSameResultOnBothSides() {
        let id = UUID()
        let mine = section(id, "Kitchen", at: 100, ["a": 2, "b": 1])
        let theirs = section(id, "Cooking", at: 200, ["a": 1, "b": 2])

        // My side: local=mine, remote=theirs.
        let myActions = reconcileSections(localSections: [mine], localTombstones: [],
                                          peerSections: [theirs], peerTombstones: [])
        // Peer side: local=theirs, remote=mine.
        let theirActions = reconcileSections(localSections: [theirs], localTombstones: [],
                                             peerSections: [mine], peerTombstones: [])

        guard case let .adopt(myResult) = myActions.first else {
            return XCTFail("expected my side to adopt the merged section")
        }
        // The peer already holds the winner's name; it must still adopt the
        // merged vector (or no-op if merge equals its state) — either way both
        // end states must be identical.
        let theirResult: SectionMetadata
        if case let .adopt(adopted)? = theirActions.first {
            theirResult = adopted
        } else {
            theirResult = theirs
        }
        XCTAssertEqual(myResult.name, theirResult.name)
        XCTAssertEqual(myResult.versions, VV.merge(mine.versions, theirs.versions))
    }

    func testTombstoneCoversLiveCopy() {
        let id = UUID()
        let mine = section(id, "Doomed", at: 10, ["a": 1])
        let tomb = SketchTombstone(id: id, versions: ["a": 1])
        let actions = reconcileSections(localSections: [mine], localTombstones: [],
                                        peerSections: [], peerTombstones: [tomb])
        XCTAssertEqual(actions, [.deleteLocal(id: id, versions: ["a": 1])])
    }

    func testNewerEditSurvivesTombstone() {
        let id = UUID()
        let mine = section(id, "Renamed since", at: 20, ["a": 1, "b": 1])
        let tomb = SketchTombstone(id: id, versions: ["a": 1])
        let actions = reconcileSections(localSections: [mine], localTombstones: [],
                                        peerSections: [], peerTombstones: [tomb])
        XCTAssertEqual(actions, [])
    }

    func testMyTombstoneBeatsPeerCopyButNewerEditResurrects() {
        let id = UUID()
        let tomb = SketchTombstone(id: id, versions: ["a": 2])
        // Covered copy → no adopt.
        let covered = section(id, "Old", at: 10, ["a": 2])
        XCTAssertEqual(reconcileSections(localSections: [], localTombstones: [tomb],
                                         peerSections: [covered], peerTombstones: []), [])
        // Independently edited copy → resurrect.
        let edited = section(id, "Edited offline", at: 30, ["a": 2, "b": 1])
        XCTAssertEqual(reconcileSections(localSections: [], localTombstones: [tomb],
                                         peerSections: [edited], peerTombstones: []),
                       [.adopt(edited)])
    }

    func testAdoptUnknownTombstone() {
        let id = UUID()
        let tomb = SketchTombstone(id: id, versions: ["b": 1])
        let actions = reconcileSections(localSections: [], localTombstones: [],
                                        peerSections: [], peerTombstones: [tomb])
        XCTAssertEqual(actions, [.adoptTombstone(id: id, versions: ["b": 1])])
    }
}
