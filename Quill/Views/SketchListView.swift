import SwiftUI

/// Studio home screen: sidebar (search / nav / folders / connection status)
/// beside the pad grid, search results, or the empty state. Mocks 1b/2a/2c.
struct SketchListView: View {
    @EnvironmentObject private var store: SketchStore
    @EnvironmentObject private var connectivity: ConnectivityManager

    /// Persisted sidebar selection (replaces the old collapsed-cards state).
    @AppStorage("sidebarSelection") private var selectionRaw = "all"
    @State private var searchText = ""
    /// Search results compute from this ~250ms behind `searchText` —
    /// `searchMatches` reads text sidecars from disk, so no per-keystroke I/O.
    @State private var debouncedQuery = ""

    // Dialogs
    @State private var renamingSketch: SketchDigest?
    @State private var renameText = ""
    @State private var movingSketch: SketchDigest?
    @State private var renamingSection: SectionMetadata?
    @State private var sectionNameText = ""
    @State private var creatingSection = false

    /// Programmatic navigation — grid cards are plain buttons.
    @State private var path: [SketchDigest] = []

    /// Derived once; the four consumers below all read this.
    private var currentSelection: SidebarSelection {
        SidebarSelection(rawValue: selectionRaw)
    }

    private var selection: Binding<SidebarSelection> {
        Binding(get: { SidebarSelection(rawValue: selectionRaw) },
                set: { selectionRaw = $0.rawValue })
    }

    var body: some View {
        NavigationStack(path: $path) {
            HStack(spacing: 0) {
                SidebarView(selection: selection,
                            searchText: $searchText,
                            onNewFolder: { sectionNameText = ""; creatingSection = true },
                            onNewPadIn: { newPad(in: $0) },
                            onRenameFolder: { section in
                                sectionNameText = section.name
                                renamingSection = section
                            },
                            onDeleteFolder: deleteSection)
                mainArea
            }
            .task(id: searchText) {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if !Task.isCancelled { debouncedQuery = searchText }
            }
            .background(QuillTheme.background)
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SketchDigest.self) { SketchDetailView(sketch: $0) }
            .alert("Pad name", isPresented: bind($renamingSketch)) {
                TextField("Title", text: $renameText)
                Button("Cancel", role: .cancel) { renamingSketch = nil }
                Button("Save") {
                    if let id = renamingSketch?.id {
                        store.rename(id, to: renameText)
                        connectivity.announceLibrary()
                    }
                    renamingSketch = nil
                }
            }
            .alert("New folder", isPresented: $creatingSection) {
                TextField("Name", text: $sectionNameText)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    guard !sectionNameText.isEmpty else { return }
                    let section = store.createSection(name: sectionNameText)
                    connectivity.announceLibrary()
                    selectionRaw = SidebarSelection.section(section.id).rawValue
                }
            }
            .alert("Rename folder", isPresented: bind($renamingSection)) {
                TextField("Name", text: $sectionNameText)
                Button("Cancel", role: .cancel) { renamingSection = nil }
                Button("Save") {
                    if let id = renamingSection?.id, !sectionNameText.isEmpty {
                        store.renameSection(id, to: sectionNameText)
                        connectivity.announceLibrary()
                    }
                    renamingSection = nil
                }
            }
            .confirmationDialog("Move to…", isPresented: bind($movingSketch), titleVisibility: .visible) {
                ForEach(store.sections) { section in
                    Button(section.name) { move(to: section.id) }
                }
                Button("Unsorted") { move(to: nil) }
                Button("Cancel", role: .cancel) { movingSketch = nil }
            }
        }
    }

    // MARK: - Main area

    @ViewBuilder
    private var mainArea: some View {
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            SearchResultsView(matches: store.searchMatches(debouncedQuery), onOpen: open)
        } else if store.sketches.isEmpty {
            EmptyHomeView(onNewPad: newPad)
        } else {
            PadGridView(title: gridTitle,
                        pads: filteredPads,
                        onNewPad: newPad,
                        onOpen: open,
                        onRename: { pad in
                            renameText = pad.title
                            renamingSketch = pad
                        },
                        onMove: { movingSketch = $0 },
                        onDelete: deletePad)
        }
    }

    private var filteredPads: [SketchDigest] {
        switch currentSelection {
        case .all: return store.sketches
        case .unsorted: return store.sketches.filter { $0.sectionID == nil }
        case let .section(id): return store.sketches.filter { $0.sectionID == id }
        }
    }

    private var gridTitle: String {
        switch currentSelection {
        case .all: return "All pads"
        case .unsorted: return "Unsorted"
        case let .section(id): return store.section(id)?.name ?? "All pads"
        }
    }

    // MARK: - Actions

    private func open(_ pad: SketchDigest) {
        path.append(pad)
    }

    private func newPad(in sectionID: UUID? = nil) {
        let target: UUID?
        if let sectionID {
            target = sectionID
        } else if case let .section(id) = currentSelection {
            target = id
        } else {
            target = nil
        }
        let meta = store.create(in: target)
        connectivity.announceLibrary()
        renameText = meta.title
        renamingSketch = meta.digest
    }

    private func newPad() { newPad(in: nil) }

    private func move(to sectionID: UUID?) {
        if let id = movingSketch?.id {
            store.moveSketch(id, to: sectionID)
            connectivity.announceLibrary()
        }
        movingSketch = nil
    }

    private func deletePad(_ pad: SketchDigest) {
        store.delete(pad.id)
        connectivity.sendDelete(pad.id)
        path.removeAll { $0.id == pad.id } // never leave a deleted pad on-screen
    }

    private func deleteSection(_ section: SectionMetadata) {
        store.deleteSection(section.id)
        if let tomb = store.sectionTombstones[section.id] {
            connectivity.sendDeleteSection(section.id, versions: tomb.versions)
        }
        connectivity.announceLibrary() // pads moved to unsorted
        if selectionRaw == section.id.uuidString { selectionRaw = "all" }
    }

    private func bind<T>(_ value: Binding<T?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }
}
