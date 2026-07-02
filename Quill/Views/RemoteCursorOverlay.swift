import SwiftUI

/// Owns the ~30 Hz cursor stream in isolation, so its frequent updates only
/// re-render this tiny view — never the canvas alongside it.
struct RemoteCursorLayer: View {
    @EnvironmentObject private var connectivity: ConnectivityManager
    @State private var cursor: RemoteCursor?

    var body: some View {
        ZStack {
            if let cursor {
                RemoteCursorOverlay(cursor: cursor)
            }
        }
        .onReceive(connectivity.remoteCursor) { self.cursor = $0 }
    }
}

/// The other device's live pointer/pencil (mock 2b): an accent cursor
/// triangle with an accent name pill. Non-interactive — never intercepts
/// touches from the canvas beneath it.
struct RemoteCursorOverlay: View {
    let cursor: RemoteCursor

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            CursorTriangle()
                .fill(QuillTheme.accent)
                .frame(width: cursor.down ? 15 : 12, height: cursor.down ? 17 : 14)
                .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)

            Text(PeerLabel.clean(cursor.peerName) ?? cursor.peerName)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(QuillTheme.accent, in: RoundedRectangle(cornerRadius: 6))
                .offset(x: 8)
        }
        .position(cursor.point)
        .allowsHitTesting(false)
        .animation(.linear(duration: 0.05), value: cursor.point)
    }
}

/// Pointer-style triangle (tip at top-left, like a cursor arrowhead).
struct CursorTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.62))
        p.addLine(to: CGPoint(x: rect.maxX * 0.42, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
