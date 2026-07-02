import Foundation
import Combine

/// Local, file-based library of sketches + sections. Persists everything,
/// remembers deletions as tombstones, and tracks a per-device version vector
/// on each item so `ConnectivityManager` can detect conflicts. No cloud.
///
/// Layout, under Application Support / Quill/Sketches:
///   device-id                  — this install's stable id (for version vectors)
///   <uuid>.meta.json           — `SketchMetadata` (versions, sectionID, paper)
///   <uuid>.drawing             — `PKDrawing.dataRepresentation()` bytes
///   <uuid>.tombstone.json      — `SketchTombstone` for a deleted sketch
///   <uuid>.section.json        — `SectionMetadata` (see SketchStore+Sections)
///   <uuid>.sectiontomb.json    — tombstone for a deleted section
final class SketchStore: ObservableObject {

    @Published private(set) var sketches: [SketchDigest] = []
    @Published private(set) var sections: [SectionMetadata] = []

    /// Stable id for this install; the key this device uses in version vectors.
    let deviceID: String

    // Tombstones cached in memory — manifests are sent often, so no per-send
    // directory scans. Loaded once at init, updated on every write.
    private(set) var sketchTombstones: [UUID: SketchTombstone] = [:]
    private(set) var sectionTombstones: [UUID: SketchTombstone] = [:]

    let root: URL
    let fm = FileManager.default

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.root = base.appendingPathComponent("Quill/Sketches", isDirectory: true)
        }
        try? fm.createDirectory(at: self.root, withIntermediateDirectories: true)
        self.deviceID = SketchStore.loadOrCreateDeviceID(in: self.root, fm: fm)
        reload()
    }

    // MARK: - Paths

    func metaURL(_ id: UUID) -> URL { root.appendingPathComponent("\(id.uuidString).meta.json") }
    func drawingURL(_ id: UUID) -> URL { root.appendingPathComponent("\(id.uuidString).drawing") }
    func tombURL(_ id: UUID) -> URL { root.appendingPathComponent("\(id.uuidString).tombstone.json") }
    func textsURL(_ id: UUID) -> URL { root.appendingPathComponent("\(id.uuidString).texts.json") }

    // MARK: - Reading

    func reload() {
        let files = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var metas: [SketchMetadata] = []
        var tombs: [UUID: SketchTombstone] = [:]
        var secs: [SectionMetadata] = []
        var secTombs: [UUID: SketchTombstone] = [:]

        for url in files {
            let name = url.lastPathComponent
            if name.hasSuffix(".meta.json"), let m: SketchMetadata = Self.readJSON(url) {
                metas.append(m)
            } else if name.hasSuffix(".tombstone.json"), let t: SketchTombstone = Self.readJSON(url) {
                tombs[t.id] = t
            } else if name.hasSuffix(".section.json"), let s: SectionMetadata = Self.readJSON(url) {
                secs.append(s)
            } else if name.hasSuffix(".sectiontomb.json"), let t: SketchTombstone = Self.readJSON(url) {
                secTombs[t.id] = t
            }
        }
        sketches = metas.map(\.digest).sorted { $0.updatedAt > $1.updatedAt }
        sketchTombstones = tombs
        sections = secs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        sectionTombstones = secTombs
    }

    func metadata(_ id: UUID) -> SketchMetadata? {
        Self.readJSON(metaURL(id))
    }

    func loadDrawing(_ id: UUID) -> Data {
        (try? Data(contentsOf: drawingURL(id))) ?? Data()
    }

    func digests() -> [SketchDigest] { sketches }

    /// Pads whose title or text-block content matches the query
    /// (case-insensitive). Pads are few — reading text sidecars per query is fine.
    func search(_ query: String) -> [SketchDigest] {
        searchMatches(query).map(\.digest)
    }

    /// Search with highlight detail: which field matched, the snippet for
    /// text-block hits, and the matched range (mock 2c's result rows).
    /// One match per pad — title wins over text content.
    func searchMatches(_ query: String) -> [SearchMatch] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            return sketches.map { SearchMatch(digest: $0, field: .title, matchedRange: nil) }
        }
        return sketches.compactMap { digest in
            if let range = digest.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) {
                return SearchMatch(digest: digest, field: .title, matchedRange: range)
            }
            for block in loadTexts(digest.id) {
                if let (snippet, range) = SearchEngine.snippet(for: q, in: block.text) {
                    return SearchMatch(digest: digest, field: .text(snippet: snippet),
                                       matchedRange: range)
                }
            }
            return nil
        }
    }

    func tombstones() -> [SketchTombstone] { Array(sketchTombstones.values) }

    /// My knowledge of one sketch, for the reconciler.
    func localState(_ id: UUID) -> LocalState {
        if let meta = metadata(id) { return .live(meta.versions) }
        if let tomb = sketchTombstones[id] { return .tombstone(tomb.versions) }
        return .absent
    }

    // MARK: - Local edits

    @discardableResult
    func create(title: String = "Untitled", in sectionID: UUID? = nil) -> SketchMetadata {
        let now = Date()
        let meta = SketchMetadata(id: UUID(), title: title, createdAt: now, updatedAt: now,
                                  versions: [deviceID: 1], sectionID: sectionID)
        writeMeta(meta)
        try? Data().write(to: drawingURL(meta.id))
        updateInPlace(meta.digest)
        return meta
    }

    func rename(_ id: UUID, to title: String) {
        mutateMeta(id) { $0.title = title }
    }

    func moveSketch(_ id: UUID, to sectionID: UUID?) {
        mutateMeta(id) { $0.sectionID = sectionID }
    }

    func setPaper(_ id: UUID, _ paper: PaperStyle, bumpVersion: Bool = true) {
        mutateMeta(id, bumpVersion: bumpVersion) { $0.paper = paper }
    }

    /// Persist the drawing. `bumpVersion` records this as an independent local
    /// edit; pass `false` when the peer is live co-editing the same sketch (the
    /// content is already shared, so it isn't a divergence).
    func saveDrawing(_ id: UUID, data: Data, bumpVersion: Bool = true) {
        guard var meta = metadata(id) else { return }
        try? data.write(to: drawingURL(id))
        meta.updatedAt = Date()
        if bumpVersion { meta.versions = VV.bumped(meta.versions, deviceID) }
        writeMeta(meta)
        updateInPlace(meta.digest)
    }

    // MARK: - Text blocks

    func loadTexts(_ id: UUID) -> [TextBlock] {
        Self.readJSON(textsURL(id)) ?? []
    }

    /// Persist the pad's text blocks (same bump semantics as `saveDrawing`).
    func saveTexts(_ id: UUID, _ texts: [TextBlock], bumpVersion: Bool = true) {
        guard var meta = metadata(id) else { return }
        Self.writeJSON(texts, to: textsURL(id))
        meta.updatedAt = Date()
        if bumpVersion { meta.versions = VV.bumped(meta.versions, deviceID) }
        writeMeta(meta)
        updateInPlace(meta.digest)
    }

    func delete(_ id: UUID) {
        let versions = metadata(id)?.versions ?? [:]
        writeSketchTombstone(SketchTombstone(id: id, versions: versions))
        try? fm.removeItem(at: metaURL(id))
        try? fm.removeItem(at: drawingURL(id))
        try? fm.removeItem(at: textsURL(id))
        sketches.removeAll { $0.id == id }
    }

    // MARK: - Applying peer changes

    /// Take a peer's copy wholesale (pull / fast-forward / conflict copy /
    /// resolution). Overwrites unconditionally — the caller already decided.
    func applyRemote(_ meta: SketchMetadata, drawing: Data, texts: [TextBlock] = []) {
        dropTombstone(meta.id)
        writeMeta(meta)
        try? drawing.write(to: drawingURL(meta.id))
        Self.writeJSON(texts, to: textsURL(meta.id))
        updateInPlace(meta.digest)
    }

    /// Delete my copy because the peer's tombstone covers it.
    func applyRemoteDelete(_ id: UUID, versions: VersionVector) {
        writeSketchTombstone(SketchTombstone(id: id, versions: versions))
        try? fm.removeItem(at: metaURL(id))
        try? fm.removeItem(at: drawingURL(id))
        try? fm.removeItem(at: textsURL(id))
        sketches.removeAll { $0.id == id }
    }

    func adoptTombstone(_ id: UUID, versions: VersionVector) {
        applyRemoteDelete(id, versions: versions)
    }

    func dropTombstone(_ id: UUID) {
        sketchTombstones[id] = nil
        try? fm.removeItem(at: tombURL(id))
    }

    // MARK: - Internals (shared with SketchStore+Sections)

    private func mutateMeta(_ id: UUID, bumpVersion: Bool = true,
                            _ change: (inout SketchMetadata) -> Void) {
        guard var meta = metadata(id) else { return }
        change(&meta)
        meta.updatedAt = Date()
        if bumpVersion { meta.versions = VV.bumped(meta.versions, deviceID) }
        writeMeta(meta)
        updateInPlace(meta.digest)
    }

    private func writeMeta(_ meta: SketchMetadata) {
        Self.writeJSON(meta, to: metaURL(meta.id))
    }

    private func writeSketchTombstone(_ tomb: SketchTombstone) {
        sketchTombstones[tomb.id] = tomb
        Self.writeJSON(tomb, to: tombURL(tomb.id))
    }

    func setSectionTombstone(_ tomb: SketchTombstone?, id: UUID, url: URL) {
        sectionTombstones[id] = tomb
        if let tomb {
            Self.writeJSON(tomb, to: url)
        } else {
            try? fm.removeItem(at: url)
        }
    }

    func replaceSections(_ new: [SectionMetadata]) {
        sections = new.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func updateInPlace(_ digest: SketchDigest) {
        var updated = sketches
        if let index = updated.firstIndex(where: { $0.id == digest.id }) {
            updated[index] = digest
        } else {
            updated.append(digest)
        }
        sketches = updated.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func readJSON<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func writeJSON<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url)
    }

    private static func loadOrCreateDeviceID(in root: URL, fm: FileManager) -> String {
        let url = root.appendingPathComponent("device-id")
        if let existing = try? String(contentsOf: url, encoding: .utf8) {
            let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        let new = UUID().uuidString
        try? new.write(to: url, atomically: true, encoding: .utf8)
        return new
    }
}
