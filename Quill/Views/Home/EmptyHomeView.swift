import SwiftUI

/// Empty state (mock 2c): squiggle glyph, "No pads yet", sync subline, and an
/// accent New-pad button.
struct EmptyHomeView: View {
    var onNewPad: () -> Void

    private var otherDevice: String {
        #if targetEnvironment(macCatalyst)
        "iPad"
        #else
        "Mac"
        #endif
    }

    var body: some View {
        VStack(spacing: 10) {
            SquiggleGlyph()
                .stroke(QuillTheme.dashedCard, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 72, height: 50)
            Text("No pads yet")
                .font(QuillTheme.sectionTitle())
                .foregroundStyle(QuillTheme.ink)
            Text("Everything you draw here syncs to your \(otherDevice) when it's nearby.")
                .font(QuillTheme.body())
                .foregroundStyle(QuillTheme.muted)
            Button(action: onNewPad) {
                Text("＋ New pad")
                    .font(.system(size: 13 + QuillTheme.typeBump, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(QuillTheme.accent, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(QuillTheme.background)
    }
}

/// The muted squiggle in the empty state.
struct SquiggleGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY * 0.7))
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.midY * 0.6),
                   control1: CGPoint(x: rect.width * 0.2, y: rect.maxY),
                   control2: CGPoint(x: rect.width * 0.35, y: rect.minY))
        p.addCurve(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.5),
                   control1: CGPoint(x: rect.width * 0.65, y: rect.midY * 1.4),
                   control2: CGPoint(x: rect.width * 0.85, y: rect.minY + 4))
        return p
    }
}
