import SwiftUI

/// Conflict card (mock 2c): original row on top, amber fork row below with a
/// FORK badge.
struct ConflictCard: View {
    let original: SketchDigest?
    let fork: SketchDigest
    let peerLabel: String
    var onOpen: (SketchDigest) -> Void
    var onDelete: (SketchDigest) -> Void

    private var thisDevice: String {
        #if targetEnvironment(macCatalyst)
        "this Mac"
        #else
        "this iPad"
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            if let original {
                row(original, isFork: false)
                QuillTheme.hairline.frame(height: 1)
            }
            row(fork, isFork: true)
        }
        .background(QuillTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(QuillTheme.hairline, lineWidth: 1))
    }

    private func row(_ pad: SketchDigest, isFork: Bool) -> some View {
        Button {
            onOpen(pad)
        } label: {
            HStack(spacing: 10) {
                MiniThumb(pad: pad,
                          borderColor: isFork ? QuillTheme.amberBorder : QuillTheme.hairline)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pad.title)
                        .font(QuillTheme.rowTitle())
                        .foregroundStyle(QuillTheme.ink)
                    Text(isFork
                         ? "Forked from your \(peerLabel)'s edits · keep, merge by hand, or delete"
                         : "\(HomeFormat.relative.localizedString(for: pad.updatedAt, relativeTo: Date())) · \(thisDevice)")
                        .font(QuillTheme.metadata())
                        .foregroundStyle(isFork ? QuillTheme.amberText : QuillTheme.muted)
                        .lineLimit(1)
                }
                Spacer()
                if isFork {
                    Text("FORK")
                        .font(.system(size: 10.5, weight: .bold))
                        .kerning(0.5)
                        .foregroundStyle(QuillTheme.amberText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(QuillTheme.surface, in: Capsule())
                        .overlay(Capsule().stroke(QuillTheme.amberBorder, lineWidth: 1))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(isFork ? QuillTheme.amberRowBackground : QuillTheme.surface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { onDelete(pad) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
