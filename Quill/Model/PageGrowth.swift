import Foundation

/// The "infinite page" rule: a pad's page starts one viewport tall and grows
/// downward whenever content (ink or text blocks) reaches the bottom margin —
/// like Notes, the page always keeps fresh space below the lowest mark.
/// Pure math so it's unit-testable; `CanvasView` applies the result as the
/// scroll view's content height.
enum PageGrowth {
    /// Content entering this band above the page bottom triggers growth.
    static let margin: CGFloat = 220
    /// Fresh page added per growth, beyond the content's bottom edge.
    static let chunk: CGFloat = 480

    /// Next page height (content coordinates, zoom 1). Never shrinks below
    /// `current` — mid-session the page only grows, so scroll positions and
    /// peer coordinates stay valid.
    static func height(current: CGFloat, viewport: CGFloat, contentBottom: CGFloat) -> CGFloat {
        var height = max(current, viewport)
        if contentBottom > height - margin {
            height = contentBottom + chunk
        }
        return height
    }
}
