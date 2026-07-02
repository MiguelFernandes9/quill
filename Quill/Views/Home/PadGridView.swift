import SwiftUI

/// Studio main area (mocks 1b / 2a / 2c): header row, conflict cards, and the
/// 3-column thumbnail grid ending in a dashed "New pad" card.
struct PadGridView: View {
    @EnvironmentObject private var store: SketchStore
    @EnvironmentObject private var connectivity: ConnectivityManager

    let title: String
    let pads: [SketchDigest]
    var onNewPad: () -> Void
    var onOpen: (SketchDigest) -> Void
    var onRename: (SketchDigest) -> Void
    var onMove: (SketchDigest) -> Void
    var onDelete: (SketchDigest) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                let grouped = pairConflicts(pads)
                if !grouped.pairs.isEmpty {
                    conflictSection(grouped.pairs)
                }
                grid(grouped.plain)
            }
            .padding(20)
        }
        .background(QuillTheme.background)
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.system(size: 17 + QuillTheme.typeBump, weight: .semibold))
                .foregroundStyle(QuillTheme.ink)
            Spacer()
            Button(action: onNewPad) {
                Text("＋ New pad")
                    .font(.system(size: 13 + QuillTheme.typeBump, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: QuillTheme.rowHeight >= 44 ? 44 : 30)
                    .background(QuillTheme.accent, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Grid

    private func grid(_ plain: [SketchDigest]) -> some View {
        // Adaptive columns: ~3 across in landscape, fewer in portrait or a
        // narrow window — keeps the vertical orientation usable.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: QuillTheme.gridGap)],
                  spacing: QuillTheme.gridGap) {
            ForEach(plain) { pad in
                PadCard(pad: pad,
                        sectionName: sectionName(pad),
                        when: HomeFormat.relative.localizedString(for: pad.updatedAt, relativeTo: Date()),
                        peerHere: connectivity.peerOpenSketchID == pad.id,
                        peerLabel: PeerLabel.short(connectivity.peerName),
                        onOpen: { onOpen(pad) })
                    .contextMenu {
                        Button { onRename(pad) } label: { Label("Rename", systemImage: "pencil") }
                        Button { onMove(pad) } label: { Label("Move…", systemImage: "folder") }
                        Button(role: .destructive) { onDelete(pad) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            newPadCard
        }
    }

    @State private var newPadHovering = false

    private var newPadCard: some View {
        Button(action: onNewPad) {
            VStack(spacing: 6) {
                Text("＋")
                    .font(.system(size: 22, weight: .medium))
                Text("New pad")
                    .font(QuillTheme.rowTitle())
            }
            .foregroundStyle(newPadHovering ? QuillTheme.accent : QuillTheme.muted)
            .frame(maxWidth: .infinity)
            .frame(height: QuillTheme.thumbnailHeight + 42)
            .background(
                RoundedRectangle(cornerRadius: QuillTheme.cardRadius)
                    .stroke(newPadHovering ? QuillTheme.accent : QuillTheme.dashedCard,
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { newPadHovering = $0 }
    }

    // MARK: - Conflicts (mock 2c)

    private func conflictSection(_ pairs: [(original: SketchDigest?, fork: SketchDigest)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EDITED ON BOTH DEVICES WHILE APART")
                .font(QuillTheme.sectionLabel())
                .kerning(0.8)
                .foregroundStyle(QuillTheme.muted)
            ForEach(pairs, id: \.fork.id) { pair in
                ConflictCard(original: pair.original, fork: pair.fork,
                             peerLabel: PeerLabel.short(connectivity.peerName),
                             onOpen: onOpen, onDelete: onDelete)
            }
        }
    }

    private func sectionName(_ pad: SketchDigest) -> String? {
        pad.sectionID.flatMap { id in store.section(id)?.name }
    }
}
