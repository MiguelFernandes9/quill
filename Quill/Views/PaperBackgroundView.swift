import SwiftUI

/// Draws the pad's paper pattern (lines / grid / dots) beneath the transparent
/// drawing canvas. A SwiftUI `Canvas` renders once per size/style change — no
/// per-frame cost.
struct PaperBackgroundView: View {
    let style: PaperStyle

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
                var y = lineSpacing
                while y < size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += lineSpacing
                }
                context.stroke(path, with: .color(ruleColor), lineWidth: 0.5)

            case .grid:
                var path = Path()
                var x = gridSpacing
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += gridSpacing
                }
                var y = gridSpacing
                while y < size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += gridSpacing
                }
                context.stroke(path, with: .color(ruleColor), lineWidth: 0.5)

            case .dots:
                var y = dotSpacing
                while y < size.height {
                    var x = dotSpacing
                    while x < size.width {
                        let dot = CGRect(x: x - 1, y: y - 1, width: 2, height: 2)
                        context.fill(Path(ellipseIn: dot), with: .color(dotColor))
                        x += dotSpacing
                    }
                    y += dotSpacing
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var ruleColor: Color { Color(uiColor: .separator) }
    private var dotColor: Color { Color(uiColor: .systemGray3) }
}
