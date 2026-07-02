import XCTest
@testable import Quill

final class SyncReconcilerTests: XCTestCase {

    private let a = UUID()
    // "dev-a" < "dev-b", so dev-a is the resolver.
    private let me = "dev-a"
    private let peer = "dev-b"

    private func run(local: @escaping (UUID) -> LocalState,
                     peerLive: [PeerLive] = [],
                     peerTombstones: [PeerTombstone] = [],
                     resolver: Bool = true) -> [SyncAction] {
        reconcile(local: local,
                  peerLive: peerLive,
                  peerTombstones: peerTombstones,
                  myDeviceID: resolver ? me : peer,
                  peerDeviceID: resolver ? peer : me)
    }

    // MARK: peer live pads

    func testPullWhenAbsentLocally() {
        let actions = run(local: { _ in .absent },
                          peerLive: [PeerLive(id: a, versions: ["dev-b": 1])])
        XCTAssertEqual(actions, [.pull(a)])
    }

    func testFastForwardWhenPeerNewer() {
        let actions = run(local: { _ in .live(["dev-a": 1]) },
                          peerLive: [PeerLive(id: a, versions: ["dev-a": 1, "dev-b": 1])])
        XCTAssertEqual(actions, [.pull(a)])
    }

    func testNothingWhenIAmNewer() {
        let actions = run(local: { _ in .live(["dev-a": 2]) },
                          peerLive: [PeerLive(id: a, versions: ["dev-a": 1])])
        XCTAssertEqual(actions, [])
    }

    func testNothingWhenEqual() {
        let actions = run(local: { _ in .live(["dev-a": 1]) },
                          peerLive: [PeerLive(id: a, versions: ["dev-a": 1])])
        XCTAssertEqual(actions, [])
    }

    func testConcurrentResolverForks() {
        let actions = run(local: { _ in .live(["dev-a": 1]) },
                          peerLive: [PeerLive(id: a, versions: ["dev-b": 1])],
                          resolver: true)
        XCTAssertEqual(actions, [.fork(a)])
    }

    func testConcurrentNonResolverWaits() {
        let actions = run(local: { _ in .live(["dev-b": 1]) },   // note: local is my-own state
                          peerLive: [PeerLive(id: a, versions: ["dev-a": 1])],
                          resolver: false)
        XCTAssertEqual(actions, [])   // non-resolver defers to the resolver
    }

    // MARK: tombstone interactions

    func testMyTombstoneCoversPeerCopy() {
        let actions = run(local: { _ in .tombstone(["dev-a": 1]) },
                          peerLive: [PeerLive(id: a, versions: ["dev-a": 1])])
        XCTAssertEqual(actions, [.pushDelete(a)])
    }

    func testPeerEditNewerThanMyDeleteResurrects() {
        let actions = run(local: { _ in .tombstone(["dev-a": 1]) },
                          peerLive: [PeerLive(id: a, versions: ["dev-a": 1, "dev-b": 1])])
        XCTAssertEqual(actions, [.dropTombstoneAndPull(a)])
    }

    func testPeerTombstoneDeletesMyOlderCopy() {
        let actions = run(local: { _ in .live(["dev-b": 1]) },
                          peerTombstones: [PeerTombstone(id: a, versions: ["dev-b": 1])])
        XCTAssertEqual(actions, [.deleteLocal(a)])
    }

    func testPeerTombstoneButMyEditIsNewerKeepsIt() {
        let actions = run(local: { _ in .live(["dev-b": 1, "dev-a": 1]) },
                          peerTombstones: [PeerTombstone(id: a, versions: ["dev-b": 1])])
        XCTAssertEqual(actions, [])   // my newer edit survives; peer will resurrect
    }

    func testAdoptPeerTombstoneWhenIHaveNothing() {
        let actions = run(local: { _ in .absent },
                          peerTombstones: [PeerTombstone(id: a, versions: ["dev-b": 2])])
        XCTAssertEqual(actions, [.adoptTombstone(a, ["dev-b": 2])])
    }
}
