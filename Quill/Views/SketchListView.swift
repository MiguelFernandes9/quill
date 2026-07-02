import SwiftUI

/// Notes-like home screen: pads grouped into sections (folders), with
/// create / rename / delete / move, peer-connection status, and an eye badge
/// on the pad the other device currently has open.
struct SketchListView: View {
    @EnvironmentObject private var store: SketchStore
    @EnvironmentObject private var connectivity: ConnectivityManager

    @State private var renamingSketch: SketchDigest?
    @State private var renameText = ""
    @State private var movingSketch: SketchDigest?
    @State private var renamingSection: SectionMetadata?
    @State private var sectionNameText = ""
    @State private var creatingSection = false

    /// Collapsed section ids (plus "unsorted"), persisted across launches.
    @AppStorage("collapsedSections") private var collapsedCSV = ""

    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if store.sketches.isEmpty && store.sections.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("")
            .navigationDestination(for: SketchDigest.self) { SketchDetailView(sketch: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { peerBadge }
                ToolbarItem(placement: .principal) {
                    searchField
                        .frame(minWidth: 220, maxWidth: 420)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { createPad(in: nil) } label: { Image(systemName: "square.and.pencil") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        sectionNameText = ""
                        creatingSection = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
            }
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
            .alert("New section", isPresented: $creatingSection) {
                TextField("Name", text: $sectionNameText)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    guard !sectionNameText.isEmpty else { return }
                    store.createSection(name: sectionNameText)
                    connectivity.announceLibrary()
                }
            }
            .alert("Rename section", isPresented: bind($renamingSection)) {
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
                Button("Unfiled") { move(to: nil) }
                Button("Cancel", role: .cancel) { movingSketch = nil }
            }
        }
    }

    // MARK: - List

    /// Custom search field — the system `.searchable` control renders
    /// misaligned on Catalyst, so we own the layout.
    private var searchField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(.secondary)
            TextField("Search pads and text", text: $searchText)
                .textFieldStyle(.plain)
                .font(.body)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // White bubble, Mac-style field: subtle border + faint lift.
        .background(Color(uiColor: .systemBackground),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(uiColor: .separator).opacity(0.6), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 1, y: 0.5)
    }

    /// Each section is one rounded card: a folder row that expands in place to
    /// reveal its pads, and collapses back to a closed card. While searching,
    /// the cards give way to a flat result list (titles + text content match).
    private var list: some View {
        List {
            if searchText.isEmpty {
                sectionCard(key: "unsorted", icon: "tray", name: "Unsorted",
                            section: nil,
                            pads: store.sketches.filter { $0.sectionID == nil })
                ForEach(store.sections) { section in
                    sectionCard(key: section.id.uuidString, icon: "folder", name: section.name,
                                section: section,
                                pads: store.sketches.filter { $0.sectionID == section.id })
                }
            } else {
                let results = store.search(searchText)
                if results.isEmpty {
                    Text("No matches")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results) { row(for: $0) }
                }
            }
        }
        #if !targetEnvironment(macCatalyst)
        .listStyle(.insetGrouped) // rounded card per section
        #endif
    }

    @ViewBuilder
    private func sectionCard(key: String, icon: String, name: String,
                             section: SectionMetadata?, pads: [SketchDigest]) -> some View {
        let expanded = !collapsedSet.contains(key)
        Section {
            folderRow(key: key, icon: icon, name: name, section: section,
                      count: pads.count, expanded: expanded)
            if expanded {
                ForEach(pads) { row(for: $0) }
            }
        }
    }

    private func folderRow(key: String, icon: String, name: String,
                           section: SectionMetadata?, count: Int, expanded: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
            Text(name)
                .fontWeight(.semibold)
            Spacer()
            if let section {
                Menu {
                    Button {
                        createPad(in: section.id)
                    } label: {
                        Label("New Pad Here", systemImage: "square.and.pencil")
                    }
                    Button {
                        sectionNameText = section.name
                        renamingSection = section
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        deleteSection(section)
                    } label: {
                        Label("Delete Section", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
            }
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle(key) }
    }

    private func toggle(_ key: String) {
        withAnimation(.snappy) {
            var set = collapsedSet
            if set.contains(key) { set.remove(key) } else { set.insert(key) }
            collapsedCSV = set.sorted().joined(separator: ",")
        }
    }

    private var collapsedSet: Set<String> {
        Set(collapsedCSV.split(separator: ",").map(String.init))
    }

    /// Row with a platform-appropriate edit affordance:
    /// Mac → right-click context menu; iPad → swipe actions.
    @ViewBuilder
    private func row(for sketch: SketchDigest) -> some View {
        let link = NavigationLink(value: sketch) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sketch.title).font(.body)
                    Text(sketch.updatedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if connectivity.peerOpenSketchID == sketch.id {
                    Spacer()
                    Image(systemName: "eye.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
        }
        #if targetEnvironment(macCatalyst)
        link.contextMenu {
            renameButton(sketch)
            moveButton(sketch)
            deleteButton(sketch)
        }
        #else
        link.swipeActions(edge: .trailing) {
            deleteButton(sketch)
            moveButton(sketch).tint(.orange)
            renameButton(sketch).tint(.blue)
        }
        #endif
    }

    // MARK: - Actions

    private func renameButton(_ sketch: SketchDigest) -> some View {
        Button {
            renameText = sketch.title
            renamingSketch = sketch
        } label: {
            Label("Rename", systemImage: "pencil")
        }
    }

    private func moveButton(_ sketch: SketchDigest) -> some View {
        Button {
            movingSketch = sketch
        } label: {
            Label("Move…", systemImage: "folder")
        }
    }

    private func deleteButton(_ sketch: SketchDigest) -> some View {
        Button(role: .destructive) {
            store.delete(sketch.id)
            connectivity.sendDelete(sketch.id)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func createPad(in sectionID: UUID?) {
        let meta = store.create(in: sectionID)
        connectivity.announceLibrary()
        // Name it right away (cancel keeps "Untitled").
        renameText = meta.title
        renamingSketch = meta.digest
    }

    private func move(to sectionID: UUID?) {
        if let id = movingSketch?.id {
            store.moveSketch(id, to: sectionID)
            connectivity.announceLibrary()
        }
        movingSketch = nil
    }

    private func deleteSection(_ section: SectionMetadata) {
        store.deleteSection(section.id)
        if let tomb = store.sectionTombstones[section.id] {
            connectivity.sendDeleteSection(section.id, versions: tomb.versions)
        }
        connectivity.announceLibrary() // pads moved to unfiled
    }

    // MARK: - Chrome

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "scribble.variable")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No sketches yet").font(.headline)
            Text("Tap the pencil to start drawing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var peerBadge: some View {
        Image(systemName: connectivity.connectedPeers > 0 ? "person.2.fill" : "person.2")
            .foregroundStyle(connectivity.connectedPeers > 0 ? Color.green : Color.secondary)
            .accessibilityLabel(connectivity.connectedPeers > 0
                                ? "\(connectivity.connectedPeers) connected"
                                : "Not connected")
    }

    private func bind<T>(_ value: Binding<T?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }
}
