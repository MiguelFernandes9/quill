import Foundation

/// Section (folder) CRUD + peer-change application. Sections are real entities:
/// they can exist empty, and deleting one moves its pads to unfiled (each move
/// is a normal pad edit, so it propagates through the usual sketch sync).
extension SketchStore {

    private func sectionURL(_ id: UUID) -> URL {
        root.appendingPathComponent("\(id.uuidString).section.json")
    }

    private func sectionTombURL(_ id: UUID) -> URL {
        root.appendingPathComponent("\(id.uuidString).sectiontomb.json")
    }

    func section(_ id: UUID) -> SectionMetadata? {
        sections.first { $0.id == id }
    }

    func sectionTombstoneList() -> [SketchTombstone] { Array(sectionTombstones.values) }

    // MARK: - Local edits

    @discardableResult
    func createSection(name: String) -> SectionMetadata {
        let now = Date()
        let section = SectionMetadata(id: UUID(), name: name, createdAt: now,
                                      updatedAt: now, versions: [deviceID: 1])
        writeSection(section)
        return section
    }

    func renameSection(_ id: UUID, to name: String) {
        guard var section = section(id) else { return }
        section.name = name
        section.updatedAt = Date()
        section.versions = VV.bumped(section.versions, deviceID)
        writeSection(section)
    }

    /// Delete the folder; pads inside become unfiled (never deleted). Each pad
    /// move bumps that pad's version so it syncs as a normal edit.
    func deleteSection(_ id: UUID) {
        let versions = section(id)?.versions ?? [:]
        for sketch in sketches where sketch.sectionID == id {
            moveSketch(sketch.id, to: nil)
        }
        setSectionTombstone(SketchTombstone(id: id, versions: versions),
                            id: id, url: sectionTombURL(id))
        try? fm.removeItem(at: sectionURL(id))
        replaceSections(sections.filter { $0.id != id })
    }

    // MARK: - Applying peer changes

    func applySectionAction(_ action: SectionAction) {
        switch action {
        case let .adopt(section):
            setSectionTombstone(nil, id: section.id, url: sectionTombURL(section.id))
            writeSection(section)

        case let .deleteLocal(id, versions):
            for sketch in sketches where sketch.sectionID == id {
                moveSketch(sketch.id, to: nil)
            }
            setSectionTombstone(SketchTombstone(id: id, versions: versions),
                                id: id, url: sectionTombURL(id))
            try? fm.removeItem(at: sectionURL(id))
            replaceSections(sections.filter { $0.id != id })

        case let .adoptTombstone(id, versions):
            setSectionTombstone(SketchTombstone(id: id, versions: versions),
                                id: id, url: sectionTombURL(id))
        }
    }

    // MARK: - Private

    private func writeSection(_ section: SectionMetadata) {
        SketchStore.writeJSON(section, to: sectionURL(section.id))
        var updated = sections.filter { $0.id != section.id }
        updated.append(section)
        replaceSections(updated)
    }
}
