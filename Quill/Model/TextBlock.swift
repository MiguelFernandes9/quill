import Foundation

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

    init(id: UUID = UUID(), text: String = "", x: Double, y: Double, size: Double = 17) {
        self.id = id
        self.text = text
        self.x = x
        self.y = y
        self.size = size
    }

    // Older blocks: no `size`; fall back to their style's size, else body.
    enum CodingKeys: String, CodingKey { case id, text, x, y, size, style }
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
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(size, forKey: .size)
    }
}
