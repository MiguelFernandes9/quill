import SwiftUI

/// Studio sidebar (mocks 1b / 2a): search, nav rows, folders, connection
/// status pinned to the bottom. (`SidebarSelection` lives in HomeModels.)
struct SidebarView: View {
    @EnvironmentObject private var store: SketchStore
    @EnvironmentObject private var connectivity: ConnectivityManager

    @Binding var selection: SidebarSelection
    @Binding var searchText: String
    var onNewFolder: () -> Void
    var onNewPadIn: (UUID) -> Void
    var onRenameFolder: (SectionMetadata) -> Void
    var onDeleteFolder: (SectionMetadata) -> Void

    @FocusState private var searchFocused: Bool
    @State private var hoveredRow: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 10)

            navRow(key: "all", label: "All pads", count: store.sketches.count,
                   selected: selection == .all) { selection = .all }
            navRow(key: "unsorted", label: "Unsorted",
                   count: store.sketches.filter { $0.sectionID == nil }.count,
                   selected: selection == .unsorted) { selection = .unsorted }

            Text("FOLDERS")
                .font(QuillTheme.sectionLabel())
                .kerning(0.8)
                .foregroundStyle(QuillTheme.muted)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 4)

            ForEach(store.sections) { section in
                navRow(key: section.id.uuidString, label: section.name,
                       count: store.sketches.filter { $0.sectionID == section.id }.count,
                       selected: selection == .section(section.id)) {
                    selection = .section(section.id)
                }
                .contextMenu {
                    Button { onNewPadIn(section.id) } label: {
                        Label("New Pad Here", systemImage: "square.and.pencil")
                    }
                    Button { onRenameFolder(section) } label: { Label("Rename", systemImage: "pencil") }
                    Button(role: .destructive) { onDeleteFolder(section) } label: {
                        Label("Delete Folder", systemImage: "trash")
                    }
                }
            }

            Button(action: onNewFolder) {
                Text("+ New folder")
                    .font(.system(size: 12.5 + QuillTheme.typeBump))
                    .foregroundStyle(QuillTheme.muted)
                    .padding(.horizontal, 20)
                    .frame(height: QuillTheme.rowHeight)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            connectionStatus
        }
        .frame(width: QuillTheme.sidebarWidth)
        .background(QuillTheme.background)
        .overlay(alignment: .trailing) {
            QuillTheme.hairline.frame(width: 1)
        }
    }

    // MARK: - Pieces

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12 + QuillTheme.typeBump))
                .foregroundStyle(QuillTheme.muted)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(QuillTheme.body())
                .focused($searchFocused)
        }
        .padding(.horizontal, 9)
        .frame(height: QuillTheme.rowHeight >= 44 ? 44 : 30)
        .background(QuillTheme.surface, in: RoundedRectangle(cornerRadius: QuillTheme.fieldRadius))
        .overlay(
            RoundedRectangle(cornerRadius: QuillTheme.fieldRadius)
                .stroke(searchFocused ? QuillTheme.accent : QuillTheme.hairline,
                        lineWidth: searchFocused ? 1.5 : 1)
        )
        .background( // focused: 3pt soft-accent glow ring outside the border
            RoundedRectangle(cornerRadius: QuillTheme.fieldRadius)
                .stroke(searchFocused ? QuillTheme.accentSoft : .clear, lineWidth: 3)
        )
    }

    private func navRow(key: String, label: String, count: Int,
                        selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 13 + QuillTheme.typeBump,
                                  weight: selected ? .semibold : .regular))
                Spacer()
                Text("\(count)")
                    .font(QuillTheme.metadata())
                    .foregroundStyle(selected ? QuillTheme.accent : QuillTheme.muted)
            }
            .foregroundStyle(selected ? QuillTheme.accent : QuillTheme.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: QuillTheme.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? QuillTheme.accentSoft
                          : hoveredRow == key ? QuillTheme.hairlineInner : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .onHover { hovering in
            hoveredRow = hovering ? key : (hoveredRow == key ? nil : hoveredRow)
        }
    }

    private var connectionStatus: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(connectivity.connectedPeers > 0 ? QuillTheme.green : QuillTheme.muted)
                .frame(width: 7, height: 7)
            Text(connectivity.connectedPeers > 0
                 ? "\(PeerLabel.clean(connectivity.peerName) ?? "Device") · connected"
                 : "not connected")
                .font(.system(size: 11.5 + QuillTheme.typeBump))
                .foregroundStyle(QuillTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { QuillTheme.hairline.frame(height: 1) }
    }
}
