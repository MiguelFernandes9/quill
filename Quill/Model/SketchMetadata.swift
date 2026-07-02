import Foundation

/// Full on-disk metadata for a single sketch (everything except the drawing
/// bytes, which live in a sibling file).
struct SketchMetadata: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    /// Per-device edit counter used for conflict detection. See `VersionVector`.
    var versions: VersionVector
    /// The section (folder) this pad lives in; nil = unfiled.
    var sectionID: UUID?
    /// Background pattern drawn behind the ink.
    var paper: PaperStyle

    init(id: UUID, title: String, createdAt: Date, updatedAt: Date,
         versions: VersionVector = [:], sectionID: UUID? = nil, paper: PaperStyle = .blank) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.versions = versions
        self.sectionID = sectionID
        self.paper = paper
    }

    // Custom decode so files saved by older builds (no versions / sectionID /
    // paper keys) still load with sensible defaults.
    enum CodingKeys: String, CodingKey { case id, title, createdAt, updatedAt, versions, sectionID, paper }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        versions = try c.decodeIfPresent(VersionVector.self, forKey: .versions) ?? [:]
        sectionID = try c.decodeIfPresent(UUID.self, forKey: .sectionID)
        paper = try c.decodeIfPresent(PaperStyle.self, forKey: .paper) ?? .blank
    }
}

/// Lightweight summary — used both for the Notes-like list rows and as a
/// manifest entry during catch-up sync.
struct SketchDigest: Codable, Equatable, Hashable, Identifiable {
    let id: UUID
    var title: String
    var updatedAt: Date
    var versions: VersionVector
    var sectionID: UUID?
    var paper: PaperStyle

    init(id: UUID, title: String, updatedAt: Date,
         versions: VersionVector = [:], sectionID: UUID? = nil, paper: PaperStyle = .blank) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.versions = versions
        self.sectionID = sectionID
        self.paper = paper
    }

    enum CodingKeys: String, CodingKey { case id, title, updatedAt, versions, sectionID, paper }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        versions = try c.decodeIfPresent(VersionVector.self, forKey: .versions) ?? [:]
        sectionID = try c.decodeIfPresent(UUID.self, forKey: .sectionID)
        paper = try c.decodeIfPresent(PaperStyle.self, forKey: .paper) ?? .blank
    }
}

/// A remembered deletion, exchanged so deletes don't resurrect across offline
/// gaps. Carries the version vector the item had when it was deleted.
/// (Used for both sketches and sections.)
struct SketchTombstone: Codable, Equatable, Identifiable {
    let id: UUID
    var versions: VersionVector
}

extension SketchMetadata {
    var digest: SketchDigest {
        SketchDigest(id: id, title: title, updatedAt: updatedAt,
                     versions: versions, sectionID: sectionID, paper: paper)
    }
}
