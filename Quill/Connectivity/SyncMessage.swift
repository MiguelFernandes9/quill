import Foundation

/// Messages exchanged over the live MultipeerConnectivity link.
///
/// Foundation-only (no PencilKit): it carries the *encoded* drawing bytes, not
/// `PKDrawing` values.
///
/// Jobs:
/// - **Live** while both peers view the same sketch: `.strokes` + `.cursor`,
///   with `.openSketch`/`.closeSketch` announcing what each is viewing.
/// - **Catch-up + conflict sync**: `.manifest` advertises the library (live
///   digests with version vectors + tombstones); `.requestSketch`/`.fullSketch`
///   move copies; `.deleteSketch` propagates a deletion; `.applyResolution`
///   delivers a resolver's conflict fork.
enum SyncMessage: Codable, Equatable {

    // MARK: Live

    case openSketch(id: UUID)
    case closeSketch(id: UUID)
    case strokes(sketchID: UUID, data: Data)
    case cursor(sketchID: UUID, x: Double, y: Double, down: Bool)

    // MARK: Catch-up + conflict sync

    /// Whole-library advertisement: my device id, my live sketches (with version
    /// vectors), my tombstones, and my sections (sent whole — they're tiny, so
    /// no request round-trip) with their tombstones.
    case manifest(deviceID: String, sketches: [SketchDigest], tombstones: [SketchTombstone],
                  sections: [SectionMetadata], sectionTombstones: [SketchTombstone])

    case requestSketch(id: UUID)
    case fullSketch(meta: SketchMetadata, data: Data, texts: [TextBlock])

    /// The pad's full text-block set, replacing the receiver's copy. Sent on
    /// text edits while co-viewing (blocks are few — whole-array LWW is fine).
    case texts(sketchID: UUID, texts: [TextBlock])

    /// The pad's whole drawing, replacing the receiver's copy. Sent after an
    /// erase or undo while co-viewing — those aren't expressible as an
    /// append delta (`.strokes`).
    case drawing(sketchID: UUID, data: Data)

    /// A section deletion, for live propagation (offline peers get it via the
    /// manifest's sectionTombstones instead).
    case deleteSection(id: UUID, versions: VersionVector)

    /// Live paper-style change, applied by a peer viewing the same pad
    /// (persistence rides on the sketch metadata otherwise).
    case setPaper(sketchID: UUID, paper: PaperStyle)

    /// A deletion, carrying the version vector at delete time so the receiver
    /// can tell a covering delete from one a newer edit should resurrect.
    case deleteSketch(id: UUID, versions: VersionVector)

    /// A resolver's conflict result: `canonical` overwrites the shared id,
    /// `conflict` is the losing side preserved under a new id.
    case applyResolution(canonicalMeta: SketchMetadata, canonicalData: Data, canonicalTexts: [TextBlock],
                         conflictMeta: SketchMetadata, conflictData: Data, conflictTexts: [TextBlock])
}

extension SyncMessage {

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) throws -> SyncMessage {
        try JSONDecoder().decode(SyncMessage.self, from: data)
    }
}
