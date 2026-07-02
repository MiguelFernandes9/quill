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

/// The other device's live pointer/pencil, drawn as a ghost dot with a label.
/// Non-interactive — it never intercepts touches from the canvas beneath it.
struct RemoteCursorOverlay: View {
    let cursor: RemoteCursor

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(cursor.down ? Color.orange : Color.accentColor)
                .frame(width: cursor.down ? 18 : 12, height: cursor.down ? 18 : 12)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(radius: 1)

            Text(cursor.peerName)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .position(cursor.point)
        .allowsHitTesting(false)
        .animation(.linear(duration: 0.05), value: cursor.point)
    }
}
