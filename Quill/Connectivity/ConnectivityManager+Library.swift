import Foundation

/// Library reconciliation: sketches (pull / fork / tombstones, via the pure
/// `reconcile`) and sections (adopt / LWW-merge / tombstones, via the pure
/// `reconcileSections`).
extension ConnectivityManager {

    func reconcileLibrary(peerDeviceID: String,
                          peerSketches: [SketchDigest],
                          peerTombstones: [SketchTombstone],
                          peerSections: [SectionMetadata],
                          peerSectionTombstones: [SketchTombstone]) {
        reconcileSketches(peerDeviceID: peerDeviceID,
                          peerSketches: peerSketches, peerTombstones: peerTombstones)

        let sectionActions = reconcileSections(localSections: store.sections,
                                               localTombstones: store.sectionTombstoneList(),
                                               peerSections: peerSections,
                                               peerTombstones: peerSectionTombstones)
        for action in sectionActions {
            store.applySectionAction(action)
        }
        // An LWW merge produced a new state both sides must see — advertise it
        // so the peer converges immediately (one extra round, then vectors are
        // equal and this goes quiet).
        if sectionActions.contains(where: { if case .adopt = $0 { return true }; return false }) {
            announceLibrary()
        }
    }

    private func reconcileSketches(peerDeviceID: String,
                                   peerSketches: [SketchDigest],
                                   peerTombstones: [SketchTombstone]) {
        let peerLive = peerSketches.map { PeerLive(id: $0.id, versions: $0.versions) }
        let peerTombs = peerTombstones.map { PeerTombstone(id: $0.id, versions: $0.versions) }

        let actions = reconcile(local: { self.store.localState($0) },
                                peerLive: peerLive,
                                peerTombstones: peerTombs,
                                myDeviceID: deviceID,
                                peerDeviceID: peerDeviceID)

        for action in actions {
            // Two pads are off-limits for full-copy churn:
            // - the one I'm editing (live channel owns it),
            // - the one the PEER is editing (mid-edit; final state arrives when
            //   they close — this is the sync-on-close cadence).
            if action.id == openSketchID { continue }
            if action.id == peerOpenSketchID {
                if case .pull = action { continue }
                if case .fork = action { continue }
            }

            switch action {
            case let .pull(id):
                send(.requestSketch(id: id))

            case let .dropTombstoneAndPull(id):
                store.dropTombstone(id)
                send(.requestSketch(id: id))

            case let .pushDelete(id):
                if case let .tombstone(v) = store.localState(id) {
                    send(.deleteSketch(id: id, versions: v))
                }

            case let .deleteLocal(id):
                if let tomb = peerTombs.first(where: { $0.id == id }) {
                    store.applyRemoteDelete(id, versions: tomb.versions)
                }

            case let .adoptTombstone(id, versions):
                store.adoptTombstone(id, versions: versions)

            case let .fork(id):
                pendingFork.insert(id)
                send(.requestSketch(id: id))
            }
        }
    }

    func receiveFullSketch(meta: SketchMetadata, data: Data, texts: [TextBlock]) {
        if pendingFork.remove(meta.id) != nil {
            resolveFork(peerMeta: meta, peerData: data, peerTexts: texts)
            return
        }
        if awaitingRefresh == meta.id {
            awaitingRefresh = nil
            store.applyRemote(meta, drawing: data, texts: texts)
            canvasCommands.send((meta.id, .reloadDrawing(data)))
            canvasCommands.send((meta.id, .setTexts(texts)))
            return
        }
        // Normal pull / fast-forward. Never overwrite the pad I'm editing.
        guard meta.id != openSketchID else { return }
        store.applyRemote(meta, drawing: data, texts: texts)
    }

    /// Resolver side of a fork: keep my copy as canonical (versions raised to
    /// dominate both), preserve the peer's copy under a new id, and push the
    /// result so the peer converges to the same two sketches.
    private func resolveFork(peerMeta: SketchMetadata, peerData: Data, peerTexts: [TextBlock]) {
        guard var canonicalMeta = store.metadata(peerMeta.id) else { return }
        let canonicalData = store.loadDrawing(peerMeta.id)
        let canonicalTexts = store.loadTexts(peerMeta.id)
        canonicalMeta.versions = VV.bumped(VV.merge(canonicalMeta.versions, peerMeta.versions), deviceID)
        canonicalMeta.updatedAt = Date()
        store.applyRemote(canonicalMeta, drawing: canonicalData, texts: canonicalTexts)

        let now = Date()
        let conflictMeta = SketchMetadata(id: UUID(),
                                          title: peerMeta.title + " (conflict)",
                                          createdAt: now, updatedAt: now,
                                          versions: [deviceID: 1],
                                          sectionID: peerMeta.sectionID,
                                          paper: peerMeta.paper)
        store.applyRemote(conflictMeta, drawing: peerData, texts: peerTexts)

        send(.applyResolution(canonicalMeta: canonicalMeta, canonicalData: canonicalData,
                              canonicalTexts: canonicalTexts,
                              conflictMeta: conflictMeta, conflictData: peerData,
                              conflictTexts: peerTexts))
    }

    func applyRemoteSketchTombstone(id: UUID, versions: VersionVector) {
        switch store.localState(id) {
        case let .live(mine):
            if VV.dominatesOrEqual(versions, mine) {
                store.applyRemoteDelete(id, versions: versions)
            }
            // else: my newer/independent edit survives; peer resurrects via my manifest.
        case .tombstone:
            break
        case .absent:
            store.adoptTombstone(id, versions: versions)
        }
    }
}
