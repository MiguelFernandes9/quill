import Foundation
import CoreGraphics
import Combine
import MultipeerConnectivity

/// A peer's live pointer/pencil position, in canvas coordinates.
struct RemoteCursor: Equatable {
    var point: CGPoint
    var down: Bool
    var peerName: String
}

/// Instructions for the open canvas, delivered by the connectivity layer.
enum CanvasCommand {
    /// Append these strokes (live drawing from the peer).
    case appendStrokes(Data)
    /// Replace the whole drawing (open-refresh caught us up).
    case reloadDrawing(Data)
    /// Persist now — a peer is about to request this pad's current state.
    case flush
    /// The pad's paper style changed remotely.
    case setPaper(PaperStyle)
    /// The pad's text blocks changed remotely (whole-array replace).
    case setTexts([TextBlock])
}

/// Owns the `MultipeerSession`, encodes/decodes `SyncMessage`, and bridges the
/// live link to SwiftUI. Catch-up sync runs on a *sync-on-close* cadence: while
/// a pad is being drawn nobody re-pulls it; the final state propagates when it
/// closes (or live, if both are viewing it).
final class ConnectivityManager: ObservableObject {

    @Published private(set) var connectedPeers: Int = 0
    /// The pad the peer currently has open (presence indicator).
    @Published private(set) var peerOpenSketchID: UUID?
    /// Display name of the connected peer, for badges/cursor labels.
    @Published private(set) var peerName: String?

    /// The peer's cursor (or nil). A subject, not `@Published`, so its ~30 Hz
    /// updates don't re-render the canvas screen.
    let remoteCursor = PassthroughSubject<RemoteCursor?, Never>()

    /// Commands for whichever canvas is open, tagged by sketch id.
    let canvasCommands = PassthroughSubject<(UUID, CanvasCommand), Never>()

    private let session = MultipeerSession()
    let store: SketchStore
    let deviceID: String
    private var cancellables = Set<AnyCancellable>()

    private(set) var openSketchID: UUID?
    /// Sketches we're forking as resolver, awaiting the peer's full copy.
    var pendingFork = Set<UUID>()
    /// Pad we just opened while the peer had it open — its next fullSketch
    /// reloads the canvas instead of being ignored.
    var awaitingRefresh: UUID?

    init(store: SketchStore) {
        self.store = store
        self.deviceID = store.deviceID
        session.delegate = self
        session.start()

        // Re-advertise the library on local changes (debounced) — but not while
        // actively drawing (sync-on-close). Structural ops announce explicitly.
        store.$sketches
            .dropFirst()
            .debounce(for: .seconds(1.0), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.connectedPeers > 0, self.openSketchID == nil else { return }
                self.sendManifest()
            }
            .store(in: &cancellables)
    }

    // MARK: - Viewing state

    func setOpenSketch(_ id: UUID?) {
        let previous = openSketchID
        openSketchID = id
        remoteCursor.send(nil)
        if let previous, previous != id { send(.closeSketch(id: previous)) }
        if let id {
            send(.openSketch(id: id))
            // Joining a pad the peer is already drawing: our copy may be stale
            // (no periodic pulls anymore) — ask for their current state.
            if peerOpenSketchID == id, connectedPeers > 0 {
                awaitingRefresh = id
                send(.requestSketch(id: id))
            }
        } else if previous != nil {
            awaitingRefresh = nil
            // Sync-on-close: this is the moment the peer catches up.
            announceLibrary()
        }
    }

    /// Bump the version on a local edit unless the peer is live co-editing this
    /// same sketch (then the content is already shared — not a divergence).
    func shouldBumpVersion(for id: UUID) -> Bool {
        !(connectedPeers > 0 && peerOpenSketchID == id)
    }

    /// Live traffic is only worth sending when the peer is watching this pad.
    private var peerIsWatching: Bool {
        connectedPeers > 0 && openSketchID != nil && peerOpenSketchID == openSketchID
    }

    // MARK: - Outgoing (live)

    func sendStrokes(_ delta: Data) {
        guard peerIsWatching, let id = openSketchID else { return }
        send(.strokes(sketchID: id, data: delta))
    }

    func sendCursor(_ point: CGPoint, down: Bool) {
        guard peerIsWatching, let id = openSketchID else { return }
        send(.cursor(sketchID: id, x: Double(point.x), y: Double(point.y), down: down), reliable: false)
    }

    func sendPaper(_ paper: PaperStyle) {
        guard peerIsWatching, let id = openSketchID else { return }
        send(.setPaper(sketchID: id, paper: paper))
    }

    func sendTexts(_ texts: [TextBlock]) {
        guard peerIsWatching, let id = openSketchID else { return }
        send(.texts(sketchID: id, texts: texts))
    }

    // MARK: - Outgoing (library)

    func sendDelete(_ id: UUID) {
        let versions: VersionVector
        if case let .tombstone(v) = store.localState(id) { versions = v } else { versions = [:] }
        send(.deleteSketch(id: id, versions: versions))
    }

    func sendDeleteSection(_ id: UUID, versions: VersionVector) {
        send(.deleteSection(id: id, versions: versions))
    }

    /// Push the manifest now — call after a structural change (create/rename/
    /// move/section edits).
    func announceLibrary() {
        guard connectedPeers > 0 else { return }
        sendManifest()
    }

    func sendManifest() {
        send(.manifest(deviceID: deviceID,
                       sketches: store.digests(),
                       tombstones: store.tombstones(),
                       sections: store.sections,
                       sectionTombstones: store.sectionTombstoneList()))
    }

    func send(_ message: SyncMessage, reliable: Bool = true) {
        guard let data = try? message.encoded() else { return }
        session.send(data, reliable: reliable)
    }

    // MARK: - Incoming

    private func handle(_ message: SyncMessage, from peerDisplayName: String) {
        switch message {
        case let .openSketch(id):
            peerOpenSketchID = id
            // Peer is about to request this pad — make sure disk matches canvas.
            if id == openSketchID {
                canvasCommands.send((id, .flush))
            }

        case let .closeSketch(id):
            if peerOpenSketchID == id { peerOpenSketchID = nil }

        case let .strokes(sketchID, data):
            guard sketchID == openSketchID else { return }
            canvasCommands.send((sketchID, .appendStrokes(data)))

        case let .cursor(sketchID, x, y, down):
            guard sketchID == openSketchID else { remoteCursor.send(nil); return }
            remoteCursor.send(RemoteCursor(point: CGPoint(x: x, y: y), down: down,
                                           peerName: peerDisplayName))

        case let .setPaper(sketchID, paper):
            store.setPaper(sketchID, paper, bumpVersion: false)
            if sketchID == openSketchID {
                canvasCommands.send((sketchID, .setPaper(paper)))
            }

        case let .texts(sketchID, texts):
            store.saveTexts(sketchID, texts, bumpVersion: false)
            if sketchID == openSketchID {
                canvasCommands.send((sketchID, .setTexts(texts)))
            }

        case let .manifest(peerDeviceID, sketches, tombstones, sections, sectionTombstones):
            reconcileLibrary(peerDeviceID: peerDeviceID,
                             peerSketches: sketches, peerTombstones: tombstones,
                             peerSections: sections, peerSectionTombstones: sectionTombstones)

        case let .requestSketch(id):
            guard let meta = store.metadata(id) else { return }
            send(.fullSketch(meta: meta, data: store.loadDrawing(id), texts: store.loadTexts(id)))

        case let .fullSketch(meta, data, texts):
            receiveFullSketch(meta: meta, data: data, texts: texts)

        case let .deleteSketch(id, versions):
            applyRemoteSketchTombstone(id: id, versions: versions)

        case let .deleteSection(id, versions):
            store.applySectionAction(.deleteLocal(id: id, versions: versions))

        case let .applyResolution(canonicalMeta, canonicalData, canonicalTexts,
                                  conflictMeta, conflictData, conflictTexts):
            store.applyRemote(canonicalMeta, drawing: canonicalData, texts: canonicalTexts)
            store.applyRemote(conflictMeta, drawing: conflictData, texts: conflictTexts)
        }
    }
}

// MARK: - MultipeerSessionDelegate

extension ConnectivityManager: MultipeerSessionDelegate {
    func multipeer(_ session: MultipeerSession, peersChanged connected: [MCPeerID]) {
        connectedPeers = connected.count
        peerName = connected.first?.displayName
        if connected.isEmpty {
            remoteCursor.send(nil)
            peerOpenSketchID = nil
            pendingFork.removeAll()
            awaitingRefresh = nil
        } else {
            sendManifest()
            if let id = openSketchID { send(.openSketch(id: id)) }
        }
    }

    func multipeer(_ session: MultipeerSession, didReceive data: Data, from peer: MCPeerID) {
        guard let message = try? SyncMessage.decode(data) else { return }
        handle(message, from: peer.displayName)
    }
}
