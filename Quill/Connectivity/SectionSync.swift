import Foundation

/// What this device should do about sections after seeing a peer's manifest.
/// Pure decisions — no I/O — so the tricky convergence rules are unit-testable.
enum SectionAction: Equatable {
    /// Write this section locally (adopt the peer's, or the merged LWW winner).
    case adopt(SectionMetadata)
    /// Delete my copy (peer's tombstone covers it); pads inside move to unfiled.
    case deleteLocal(id: UUID, versions: VersionVector)
    /// Remember the peer's tombstone so the section doesn't resurrect.
    case adoptTombstone(id: UUID, versions: VersionVector)
}

/// Merge two concurrent copies of the same section deterministically: both
/// devices run this on (theirs, mine) and MUST produce the same result.
/// Winner = newer `updatedAt`; ties break by name, then device-independent id.
/// The result carries the merged version vector so it dominates both inputs.
func mergeSections(_ a: SectionMetadata, _ b: SectionMetadata) -> SectionMetadata {
    let winner: SectionMetadata
    if a.updatedAt != b.updatedAt {
        winner = a.updatedAt > b.updatedAt ? a : b
    } else if a.name != b.name {
        winner = a.name > b.name ? a : b
    } else {
        winner = a.id.uuidString > b.id.uuidString ? a : b
    }
    var merged = winner
    merged.versions = VV.merge(a.versions, b.versions)
    return merged
}

/// Decide section actions from a peer's manifest.
func reconcileSections(
    localSections: [SectionMetadata],
    localTombstones: [SketchTombstone],
    peerSections: [SectionMetadata],
    peerTombstones: [SketchTombstone]
) -> [SectionAction] {
    var actions: [SectionAction] = []
    let localByID = Dictionary(uniqueKeysWithValues: localSections.map { ($0.id, $0) })
    let localTombByID = Dictionary(uniqueKeysWithValues: localTombstones.map { ($0.id, $0) })

    for remote in peerSections {
        if let tomb = localTombByID[remote.id] {
            // My delete vs their copy: covering delete stays dead; a newer or
            // independent edit resurrects (matches the sketch policy).
            if !VV.dominatesOrEqual(tomb.versions, remote.versions) {
                actions.append(.adopt(remote))
            }
            continue
        }
        guard let mine = localByID[remote.id] else {
            actions.append(.adopt(remote))
            continue
        }
        if VV.equal(mine.versions, remote.versions) {
            continue
        } else if VV.strictlyDominates(remote.versions, mine.versions) {
            actions.append(.adopt(remote))
        } else if VV.strictlyDominates(mine.versions, remote.versions) {
            continue // I'm newer; peer adopts from my manifest.
        } else {
            // Concurrent rename → deterministic LWW; both sides converge.
            let merged = mergeSections(mine, remote)
            if merged != mine { actions.append(.adopt(merged)) }
        }
    }

    for tomb in peerTombstones {
        if let mine = localByID[tomb.id] {
            if VV.dominatesOrEqual(tomb.versions, mine.versions) {
                actions.append(.deleteLocal(id: tomb.id, versions: tomb.versions))
            }
            // else: my newer edit survives; peer resurrects from my manifest.
        } else if localTombByID[tomb.id] == nil {
            actions.append(.adoptTombstone(id: tomb.id, versions: tomb.versions))
        }
    }

    return actions
}
