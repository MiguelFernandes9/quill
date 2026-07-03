import Foundation

/// The "infinite page" rule: a pad's page starts one viewport in size and
/// grows whenever content (ink or text blocks) reaches the edge margin —
/// like Notes, the page always keeps fresh space beyond the last mark. The
/// rule is per-axis: downward AND rightward (devices have different viewport
/// widths, so peer content can land beyond a narrower device's edge — the
/// page must widen to reach it). Pure math so it's unit-testable;
/// `CanvasView` applies the result as the scroll view's content size.
enum PageGrowth {
    /// Content entering this band before the page edge triggers growth.
    static let margin: CGFloat = 220
    /// Fresh page added per growth, beyond the content's far edge.
    static let chunk: CGFloat = 480

    /// Next page extent along one axis (content coordinates, zoom 1). Never
    /// shrinks below `current` — mid-session the page only grows, so scroll
    /// positions and peer coordinates stay valid.
    static func extent(current: CGFloat, viewport: CGFloat, contentEdge: CGFloat) -> CGFloat {
        var extent = max(current, viewport)
        if contentEdge > extent - margin {
            extent = contentEdge + chunk
        }
        return extent
    }
}
