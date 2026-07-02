import Foundation

/// A folder of pads. A real entity (can exist empty), persisted as
/// `<uuid>.section.json` and synced whole inside the manifest — sections are
/// tiny, so no request/full round-trip is needed.
///
/// Conflict policy differs from sketches: concurrent renames resolve by
/// deterministic last-writer-wins (see `SectionSync`), never by forking — a
/// forked folder couldn't split its contained pads meaningfully.
struct SectionMetadata: Codable, Equatable, Hashable, Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date
    var updatedAt: Date
    /// Per-device edit counter, same machinery as sketches (`VersionVector`).
    var versions: VersionVector
}
