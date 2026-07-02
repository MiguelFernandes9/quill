import SwiftUI

/// 52×38 pad preview used by conflict rows and search results.
struct MiniThumb: View {
    @EnvironmentObject private var thumbnails: ThumbnailStore

    let pad: SketchDigest
    var borderColor: Color = QuillTheme.hairline

    var body: some View {
        ZStack {
            let _ = thumbnails.generation // re-render when a render lands
            PaperBackgroundView(style: pad.paper)
            if let image = thumbnails.thumbnail(for: pad, size: CGSize(width: 52, height: 38)) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit).padding(2)
            }
        }
        .frame(width: 52, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(borderColor, lineWidth: 1))
    }
}
