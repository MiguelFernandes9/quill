import Foundation

/// What this device should do about one sketch after seeing a peer's manifest.
enum SyncAction: Equatable {
    /// Request the peer's full copy (it's new to me, strictly newer, or a resurrect).
    case pull(UUID)
    /// Tell the peer to delete it — my tombstone covers their copy.
    case pushDelete(UUID)
    /// Delete my copy — the peer's tombstone covers mine.
    case deleteLocal(UUID)
    /// Record the peer's tombstone so I don't resurrect it later.
    case adoptTombstone(UUID, VersionVector)
    /// I deleted it but the peer has newer/independent edits → resurrect: drop my
    /// tombstone and pull their copy.
    case dropTombstoneAndPull(UUID)
    /// Concurrent edits and I'm the resolver → start a conflict fork for this id.
    case fork(UUID)
}

extension SyncAction {
    /// The sketch this action targets.
    var id: UUID {
        switch self {
        case let .pull(id), let .pushDelete(id), let .deleteLocal(id),
             let .adoptTombstone(id, _), let .dropTombstoneAndPull(id), let .fork(id):
            return id
        }
    }
}

/// My local knowledge of a sketch.
enum LocalState: Equatable {
    case live(VersionVector)
    case tombstone(VersionVector)
    case absent
}

struct PeerLive: Equatable {
    let id: UUID
    let versions: VersionVector
}

struct PeerTombstone: Equatable {
    let id: UUID
    let versions: VersionVector
}

/// Pure decision function: given the peer's manifest and a lookup of my own
/// state, return the actions to take. No I/O, fully unit-testable.
///
/// Fork is asymmetric on purpose: only the device with the smaller id forks, so
/// the two peers never both create a conflict copy of the same divergence.
func reconcile(
    local: (UUID) -> LocalState,
    peerLive: [PeerLive],
    peerTombstones: [PeerTombstone],
    myDeviceID: String,
    peerDeviceID: String
) -> [SyncAction] {
    var actions: [SyncAction] = []
    let iAmResolver = myDeviceID < peerDeviceID

    for remote in peerLive {
        switch local(remote.id) {
        case .absent:
            actions.append(.pull(remote.id))

        case .tombstone(let mine):
            if VV.dominatesOrEqual(mine, remote.versions) {
                actions.append(.pushDelete(remote.id))       // my delete covers theirs
            } else {
                actions.append(.dropTombstoneAndPull(remote.id)) // newer/independent edit → resurrect
            }

        case .live(let mine):
            if VV.equal(mine, remote.versions) {
                continue
            } else if VV.strictlyDominates(remote.versions, mine) {
                actions.append(.pull(remote.id))             // fast-forward
            } else if VV.strictlyDominates(mine, remote.versions) {
                continue                                     // I'm newer; peer pulls from me
            } else if iAmResolver {
                actions.append(.fork(remote.id))             // concurrent → resolver forks
            }
        }
    }

    for tomb in peerTombstones {
        switch local(tomb.id) {
        case .live(let mine):
            if VV.dominatesOrEqual(tomb.versions, mine) {
                actions.append(.deleteLocal(tomb.id))        // their delete covers mine
            }
            // else: my newer/independent edit keeps it — peer resurrects via my manifest.

        case .tombstone:
            continue

        case .absent:
            actions.append(.adoptTombstone(tomb.id, tomb.versions))
        }
    }

    return actions
}
