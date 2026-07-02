import SwiftUI

/// One grid card (mock 1b/2a): paper-backed thumbnail, presence pill,
/// title + "2h ago · Section" footer. Hover turns the border accent.
struct PadCard: View {
    @EnvironmentObject private var thumbnails: ThumbnailStore

    let pad: SketchDigest
    let sectionName: String?
    let when: String
    let peerHere: Bool
    let peerLabel: String
    var onOpen: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 0) {
                thumbnail
                footer
            }
            .background(QuillTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: QuillTheme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: QuillTheme.cardRadius)
                    .stroke(hovering ? QuillTheme.accent : QuillTheme.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var thumbnail: some View {
        ZStack(alignment: .topTrailing) {
            PaperBackgroundView(style: pad.paper)
            // Observe the cache generation so freshly rendered previews land.
            let _ = thumbnails.generation
            if let image = thumbnails.thumbnail(
                for: pad, size: CGSize(width: QuillTheme.thumbnailHeight * 1.6,
                                       height: QuillTheme.thumbnailHeight)) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if peerHere {
                HStack(spacing: 4) {
                    Image(systemName: "eye.fill").font(.system(size: 9))
                    Text(peerLabel).font(.system(size: 10.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(QuillTheme.darkStrip, in: Capsule())
                .padding(8)
            }
        }
        .frame(height: QuillTheme.thumbnailHeight)
        .clipped()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(pad.title)
                .font(QuillTheme.rowTitle())
                .foregroundStyle(QuillTheme.ink)
                .lineLimit(1)
            Text(sectionName.map { "\(when) · \($0)" } ?? when)
                .font(QuillTheme.metadata())
                .foregroundStyle(QuillTheme.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { QuillTheme.hairline.frame(height: 1) }
    }
}
