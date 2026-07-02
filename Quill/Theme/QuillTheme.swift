import SwiftUI

/// Studio design tokens (design_handoff_quill_redesign/README.md — final).
/// All redesigned views draw their colors, radii, and type from here.
enum QuillTheme {

    // MARK: - Colors

    /// App background.
    static let background = Color(hex: 0xFBFBFA)
    /// Cards / fields / bars.
    static let surface = Color(hex: 0xFFFFFF)
    /// Hairline borders.
    static let hairline = Color(hex: 0xE7E7E2)
    /// Lighter inner dividers + segmented-control container fill.
    static let hairlineInner = Color(hex: 0xF1F1EC)
    /// Primary text.
    static let ink = Color(hex: 0x16161A)
    /// Secondary text.
    static let secondaryText = Color(hex: 0x44443E)
    /// Muted text / placeholders.
    static let muted = Color(hex: 0x9C9C94)

    static let accent = Color(hex: 0x2547F4)
    static let accentPressed = Color(hex: 0x1D39C9)
    /// Soft accent background (selected sidebar row, focus glow).
    static let accentSoft = Color(hex: 0xEDF0FE)
    /// Search text-match highlight.
    static let matchHighlight = Color(hex: 0xDCE4FD)

    static let green = Color(hex: 0x1FA84D)
    static let greenChipBackground = Color(hex: 0xEBF7EE)
    static let greenChipBorder = Color(hex: 0xBBE3C6)
    static let greenChipText = Color(hex: 0x177A38)

    static let amberText = Color(hex: 0xB07818)
    static let amberBorder = Color(hex: 0xEDD9AE)
    static let amberRowBackground = Color(hex: 0xFFF9EE)

    static let destructive = Color(hex: 0xD63030)
    /// Trash icon inside the dark control strip.
    static let softRed = Color(hex: 0xFF7A6E)

    /// Dark floating strips / tooltips (white content on top).
    static let darkStrip = Color(hex: 0x16161A)

    /// Segmented-button hover.
    static let segmentHover = Color(hex: 0xE4E4DE)
    /// Dashed borders (new-pad card #D6D6CE, idle text block #C9C9C1).
    static let dashedCard = Color(hex: 0xD6D6CE)
    static let dashedBlock = Color(hex: 0xC9C9C1)

    /// Drawing ink palette (order fixed by the mock).
    static let inkPalette: [(name: String, ui: UIColor)] = [
        ("black", UIColor(hex: 0x16161A)),
        ("blue", UIColor(hex: 0x2547F4)),
        ("red", UIColor(hex: 0xD63030)),
        ("green", UIColor(hex: 0x1FA84D)),
        ("orange", UIColor(hex: 0xE8850C)),
        ("purple", UIColor(hex: 0x8B3FD1)),
    ]

    // MARK: - Metrics

    #if targetEnvironment(macCatalyst)
    static let sidebarWidth: CGFloat = 240
    static let cardRadius: CGFloat = 10
    static let thumbnailHeight: CGFloat = 128
    static let gridGap: CGFloat = 16
    static let rowHeight: CGFloat = 36
    /// Additive type-size adjustment. The mock's literal sizes read too small
    /// at the Mac's 1:1 rendering — Miguel wants everything bigger.
    static let typeBump: CGFloat = 2.5
    #else
    static let sidebarWidth: CGFloat = 236
    static let cardRadius: CGFloat = 12
    static let thumbnailHeight: CGFloat = 128
    static let gridGap: CGFloat = 16
    static let rowHeight: CGFloat = 44
    static let typeBump: CGFloat = 1.5
    #endif

    static let fieldRadius: CGFloat = 8
    static let chipRadius: CGFloat = 9

    // MARK: - Type scale (SF Pro; mock sizes + platform bump)

    static func sectionLabel() -> Font { .system(size: 10.5 + typeBump, weight: .bold) }
    static func rowTitle() -> Font { .system(size: 13.5 + typeBump, weight: .semibold) }
    static func sectionTitle() -> Font { .system(size: 15 + typeBump, weight: .semibold) }
    static func chip() -> Font { .system(size: 12 + typeBump, weight: .medium) }
    static func metadata() -> Font { .system(size: 11.5 + typeBump) }
    static func body() -> Font { .system(size: 13 + typeBump) }
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
