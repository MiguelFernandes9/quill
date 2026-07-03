import Foundation
import CoreGraphics

/// Visual style of a text block (Notes-like "Aa" styles).
enum TextStyle: String, Codable, CaseIterable {
    case title
    case heading
    case body

    var label: String {
        switch self {
        case .title: return "Title"
        case .heading: return "Heading"
        case .body: return "Body"
        }
    }
}

extension TextStyle {
    /// Font size a legacy style maps to (blocks saved before free resizing).
    var defaultSize: Double {
        switch self {
        case .title: return 28
        case .heading: return 22
        case .body: return 17
        }
    }
}

/// A text element placed on a pad, in canvas coordinates. Stored as a sidecar
/// JSON next to the drawing (`<uuid>.texts.json`) and synced whole — pads have
/// few blocks, so replacing the array is simpler and safe (last-writer-wins).
struct TextBlock: Codable, Equatable, Hashable, Identifiable {
    let id: UUID
    var text: String
    var x: Double
    var y: Double
    var size: Double
    /// Fixed box width from a corner-handle resize; nil = auto (content-sized
    /// up to the default maximum).
    var width: Double?
    /// Fixed box height from a corner-handle resize; nil = auto (follows the
    /// wrapped text).
    var height: Double?

    init(id: UUID = UUID(), text: String = "", x: Double, y: Double,
         size: Double = 17, width: Double? = nil, height: Double? = nil) {
        self.id = id
        self.text = text
        self.x = x
        self.y = y
        self.size = size
        self.width = width
        self.height = height
    }

    // Older blocks: no `size` (fall back to style), no `width`/`height` (auto).
    enum CodingKeys: String, CodingKey { case id, text, x, y, size, style, width, height }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        if let size = try c.decodeIfPresent(Double.self, forKey: .size) {
            self.size = size
        } else {
            let style = try c.decodeIfPresent(TextStyle.self, forKey: .style) ?? .body
            self.size = style.defaultSize
        }
        width = try c.decodeIfPresent(Double.self, forKey: .width)
        height = try c.decodeIfPresent(Double.self, forKey: .height)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(size, forKey: .size)
        try c.encodeIfPresent(width, forKey: .width)
        try c.encodeIfPresent(height, forKey: .height)
    }
}

extension TextBlock {
    /// Rough on-canvas rect for hit-testing (finger press, long-press).
    /// Boxes resized by handles are exact; auto-sized blocks are estimated
    /// from their text, padded so a slightly-off press still lands.
    var approxRect: CGRect {
        let lines = text.isEmpty ? [""] : text.components(separatedBy: "\n")
        let longest = lines.map(\.count).max() ?? 0
        let estimatedWidth = min(360, max(120, CGFloat(longest) * size * 0.6))
        let estimatedHeight = max(44, CGFloat(lines.count) * size * 1.35 + 14)
        return CGRect(x: x, y: y,
                      width: width.map { CGFloat($0) } ?? estimatedWidth,
                      height: height.map { CGFloat($0) } ?? estimatedHeight)
            .insetBy(dx: -8, dy: -8)
    }
}
