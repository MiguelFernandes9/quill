import SwiftUI

/// Draws the pad's paper pattern (lines / grid / dots) beneath the transparent
/// drawing canvas. The view stays pinned to the viewport; the pattern itself is
/// drawn phase-shifted by the canvas's zoom + scroll, so the paper is endless —
/// however far the growing page scrolls, the rules stay glued to the ink.
struct PaperBackgroundView: View {
    let style: PaperStyle
    /// Canvas zoom scale (content → view multiplier).
    var scale: CGFloat = 1
    /// Canvas scroll offset in view coordinates (contentOffset).
    var offset: CGPoint = .zero

    private let lineSpacing: CGFloat = 28
    private let gridSpacing: CGFloat = 24
    private let dotSpacing: CGFloat = 24

    var body: some View {
        Canvas { context, size in
            switch style {
            case .blank:
                break

            case .lines:
                var path = Path()
                forEachRule(spacing: lineSpacing, offset: offset.y, limit: size.height) { y in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(ruleColor), lineWidth: 0.5 * scale)

            case .grid:
                var path = Path()
                forEachRule(spacing: gridSpacing, offset: offset.x, limit: size.width) { x in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                forEachRule(spacing: gridSpacing, offset: offset.y, limit: size.height) { y in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(ruleColor), lineWidth: 0.5 * scale)

            case .dots:
                let radius = 1 * scale
                forEachRule(spacing: dotSpacing, offset: offset.y, limit: size.height) { y in
                    forEachRule(spacing: dotSpacing, offset: offset.x, limit: size.width) { x in
                        let dot = CGRect(x: x - radius, y: y - radius,
                                         width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: dot), with: .color(dotColor))
                    }
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    /// Visits every rule line of the pattern visible in the viewport: content
    /// position `k·spacing` (k ≥ 1, matching the original margin-less edge)
    /// appears at view position `k·spacing·scale − offset`.
    private func forEachRule(spacing: CGFloat, offset: CGFloat, limit: CGFloat,
                             _ body: (CGFloat) -> Void) {
        let step = spacing * scale
        guard step > 0.5 else { return }
        var k = max(1, Int((offset / step).rounded(.down)))
        while true {
            let position = CGFloat(k) * step - offset
            if position >= limit { break }
            if position >= 0 { body(position) }
            k += 1
        }
    }

    private var ruleColor: Color { Color(uiColor: .separator) }
    private var dotColor: Color { Color(uiColor: .systemGray3) }
}
