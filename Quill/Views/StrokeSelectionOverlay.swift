import SwiftUI

/// A finger-selected set of strokes: indices into the drawing plus their
/// on-canvas box (content coordinates).
struct StrokeSelection: Equatable {
    let indices: IndexSet
    var rect: CGRect
}

/// The ink counterpart of a focused text block (iPad): a dashed accent box
/// around the selected strokes with a dark strip below — drag the box to move
/// the ink, duplicate or delete it. Lives in content coordinates; the parent
/// applies the canvas zoom/pan transform.
struct StrokeSelectionOverlay: View {
    @Binding var selection: StrokeSelection?
    /// Routes edits into the canvas (`.transformStrokes` / `.deleteStrokes` /
    /// `.duplicateStrokes`).
    var onCommand: (CanvasCommand) -> Void

    /// Translation not yet applied to the ink (kept tiny by the live apply).
    @State private var dragOffset: CGSize = .zero
    /// Translation already applied to the ink during this drag.
    @State private var applied: CGSize = .zero
    @State private var lastApplyTime: CFTimeInterval = 0

    private let stripButton = CGSize(width: 48, height: 44)

    var body: some View {
        if let current = selection {
            let box = current.rect.insetBy(dx: -10, dy: -10)
            RoundedRectangle(cornerRadius: 8)
                .fill(QuillTheme.accent.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(QuillTheme.accent,
                                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                )
                .frame(width: box.width, height: box.height)
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottom) {
                    strip(current)
                        .offset(y: stripButton.height + 14)
                }
                .offset(x: box.minX + dragOffset.width,
                        y: box.minY + dragOffset.height)
                .gesture(dragGesture(current))
        }
    }

    /// The ink follows the finger: the pending translation is applied to the
    /// strokes DURING the drag, throttled to ~20 Hz (every apply re-rasterizes
    /// the canvas). The box shows only the tiny not-yet-applied remainder, so
    /// ink and box move as one. The selection rect is read through the binding
    /// — it advances with each live apply.
    private func dragGesture(_ current: StrokeSelection) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                dragOffset = CGSize(width: value.translation.width - applied.width,
                                    height: value.translation.height - applied.height)
                let now = CACurrentMediaTime()
                guard now - lastApplyTime > 0.05 else { return }
                applyPending(current.indices)
                lastApplyTime = now
            }
            .onEnded { value in
                dragOffset = CGSize(width: value.translation.width - applied.width,
                                    height: value.translation.height - applied.height)
                applyPending(current.indices)
                applied = .zero
            }
    }

    /// Move the ink by the un-applied remainder and advance the box with it.
    private func applyPending(_ indices: IndexSet) {
        let dx = dragOffset.width
        let dy = dragOffset.height
        guard abs(dx) > 0.5 || abs(dy) > 0.5 else { return }
        onCommand(.transformStrokes(indices, dx: dx, dy: dy))
        selection?.rect = (selection?.rect ?? .zero).offsetBy(dx: dx, dy: dy)
        applied = CGSize(width: applied.width + dx, height: applied.height + dy)
        dragOffset = .zero
    }

    private func strip(_ current: StrokeSelection) -> some View {
        HStack(spacing: 0) {
            Button {
                onCommand(.duplicateStrokes(current.indices))
                // Copies land offset +16; selection stays on the originals.
            } label: {
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: stripButton.width, height: stripButton.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Color.white.opacity(0.15).frame(width: 1, height: stripButton.height - 12)

            Button {
                onCommand(.deleteStrokes(current.indices))
                selection = nil
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(QuillTheme.softRed)
                    .frame(width: stripButton.width, height: stripButton.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(QuillTheme.darkStrip, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.22), radius: 7, y: 4)
        .fixedSize()
    }
}
