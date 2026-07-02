import SwiftUI

/// Search results (mock 2c): `N RESULTS` label + rows with a mini thumbnail,
/// the matched substring highlighted, and a match-type subline.
struct SearchResultsView: View {
    @EnvironmentObject private var store: SketchStore

    let matches: [SearchMatch]
    var onOpen: (SketchDigest) -> Void

    @State private var hoveredID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(matches.count) RESULT\(matches.count == 1 ? "" : "S")")
                    .font(QuillTheme.sectionLabel())
                    .kerning(0.8)
                    .foregroundStyle(QuillTheme.muted)
                    .padding(.bottom, 2)

                ForEach(matches) { match in
                    row(match)
                }
                if matches.isEmpty {
                    Text("No matches")
                        .font(QuillTheme.body())
                        .foregroundStyle(QuillTheme.muted)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(QuillTheme.background)
    }

    private func row(_ match: SearchMatch) -> some View {
        Button {
            onOpen(match.digest)
        } label: {
            HStack(spacing: 10) {
                MiniThumb(pad: match.digest)
                VStack(alignment: .leading, spacing: 2) {
                    titleLine(match)
                    subline(match)
                }
                Spacer()
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hoveredID == match.id ? QuillTheme.hairlineInner : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredID = $0 ? match.id : (hoveredID == match.id ? nil : hoveredID) }
    }

    @ViewBuilder
    private func titleLine(_ match: SearchMatch) -> some View {
        if case .title = match.field, let range = match.matchedRange {
            Text(highlighted(match.digest.title, range: range))
                .font(QuillTheme.rowTitle())
                .foregroundStyle(QuillTheme.ink)
        } else {
            Text(match.digest.title)
                .font(QuillTheme.rowTitle())
                .foregroundStyle(QuillTheme.ink)
        }
    }

    @ViewBuilder
    private func subline(_ match: SearchMatch) -> some View {
        switch match.field {
        case .title:
            Text("Title match\(sectionSuffix(match.digest))")
                .font(QuillTheme.metadata())
                .foregroundStyle(QuillTheme.muted)
        case let .text(snippet):
            (Text("Text match: ").foregroundColor(QuillTheme.muted)
             + quotedSnippet(snippet, range: match.matchedRange))
                .font(QuillTheme.metadata())
                .lineLimit(1)
        }
    }

    // MARK: - Highlighting

    private func highlighted(_ string: String, range: Range<String.Index>) -> AttributedString {
        var attributed = AttributedString(string)
        if let attrRange = Range(range, in: attributed) {
            attributed[attrRange].backgroundColor = QuillTheme.matchHighlight
        }
        return attributed
    }

    private func quotedSnippet(_ snippet: String, range: Range<String.Index>?) -> Text {
        var attributed = AttributedString("\u{201C}\(snippet)\u{201D}")
        if let range {
            // Re-locate the match inside the quoted string (+1 for the quote).
            let start = snippet.distance(from: snippet.startIndex, to: range.lowerBound)
            let length = snippet.distance(from: range.lowerBound, to: range.upperBound)
            if let lower = attributed.characters.index(attributed.startIndex, offsetBy: start + 1,
                                                       limitedBy: attributed.endIndex),
               let upper = attributed.characters.index(lower, offsetBy: length,
                                                       limitedBy: attributed.endIndex) {
                attributed[lower..<upper].backgroundColor = QuillTheme.matchHighlight
            }
        }
        return Text(attributed).foregroundColor(QuillTheme.secondaryText)
    }

    private func sectionSuffix(_ digest: SketchDigest) -> String {
        guard let id = digest.sectionID, let section = store.section(id) else { return "" }
        return " · \(section.name)"
    }

}
