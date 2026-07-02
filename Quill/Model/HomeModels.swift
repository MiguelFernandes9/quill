import Foundation

// MARK: - Search matches (mock 2c)

/// A search hit with enough detail to highlight the matched substring.
struct SearchMatch: Equatable, Identifiable {
    enum Field: Equatable {
        case title
        /// Matched inside a text block; carries a windowed snippet.
        case text(snippet: String)
    }

    let digest: SketchDigest
    let field: Field
    /// Range of the query inside `displayString` (title or snippet).
    let matchedRange: Range<String.Index>?

    var id: UUID { digest.id }

    /// The string the row shows (title, or the snippet for text matches).
    var displayString: String {
        switch field {
        case .title: return digest.title
        case let .text(snippet): return snippet
        }
    }
}

enum SearchEngine {

    /// Window a matched text-block string to ~`radius` characters around the
    /// first match, with ellipses. Returns the snippet and the match range
    /// within it.
    static func snippet(for query: String, in text: String,
                        radius: Int = 24) -> (String, Range<String.Index>?)? {
        guard let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
        else { return nil }
        let start = text.index(range.lowerBound, offsetBy: -radius,
                               limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: radius,
                             limitedBy: text.endIndex) ?? text.endIndex
        var snippet = String(text[start..<end])
        if start > text.startIndex { snippet = "…" + snippet }
        if end < text.endIndex { snippet += "…" }
        let matchInSnippet = snippet.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
        return (snippet, matchInSnippet)
    }
}

// MARK: - Conflict pairing (mock 2c)

/// The fork suffix the resolver appends (ConnectivityManager+Library).
private let conflictSuffix = " (conflict)"

/// Groups `"X (conflict)"` forks with their `"X"` originals so the grid can
/// nest the fork row inside the original's card. Forks without a matching
/// original (renamed/deleted) surface as standalone `(nil, fork)` pairs.
func pairConflicts(_ digests: [SketchDigest]) -> (plain: [SketchDigest],
                                                  pairs: [(original: SketchDigest?, fork: SketchDigest)]) {
    var forks: [SketchDigest] = []
    var others: [SketchDigest] = []
    for digest in digests {
        if digest.title.hasSuffix(conflictSuffix) {
            forks.append(digest)
        } else {
            others.append(digest)
        }
    }

    var pairedOriginalIDs = Set<UUID>()
    var pairs: [(SketchDigest?, SketchDigest)] = []
    for fork in forks {
        let base = String(fork.title.dropLast(conflictSuffix.count))
        // Prefer an original in the same section, then any with the base title.
        let candidates = others.filter { $0.title == base && !pairedOriginalIDs.contains($0.id) }
        let original = candidates.first { $0.sectionID == fork.sectionID } ?? candidates.first
        if let original { pairedOriginalIDs.insert(original.id) }
        pairs.append((original, fork))
    }

    let plain = others.filter { !pairedOriginalIDs.contains($0.id) }
    return (plain, pairs)
}

// MARK: - Peer labels

enum PeerLabel {

    /// Short device-type chip label ("iPad" / "Mac") from an MPC display name
    /// like "Miguel's iPad-3F2A". Falls back to the cleaned name.
    static func short(_ displayName: String?) -> String {
        guard let name = clean(displayName), !name.isEmpty else { return "Device" }
        let lower = name.lowercased()
        if lower.contains("ipad") { return "iPad" }
        if lower.contains("iphone") { return "iPhone" }
        if lower.contains("mac") { return "Mac" }
        return name
    }

    /// Full name minus the per-launch "-XXXX" suffix MultipeerSession appends.
    static func clean(_ displayName: String?) -> String? {
        guard let displayName else { return nil }
        // Strip a trailing "-" + 4 alphanumerics (the random suffix).
        if let dash = displayName.lastIndex(of: "-"),
           displayName.distance(from: dash, to: displayName.endIndex) == 5,
           displayName[displayName.index(after: dash)...].allSatisfy({ $0.isLetter || $0.isNumber }) {
            return String(displayName[..<dash])
        }
        return displayName
    }
}
