import SwiftUI

/// A finger-selected set of strokes: indices into the drawing plus their
/// on-canvas box (content coordinates). While a drag is in flight the strokes
/// are lifted out of the canvas and `dragImage` rides the box instead.
struct StrokeSelection: Equatable {
    let indices: IndexSet
    var rect: CGRect
    var dragImage: UIImage?
}

/// The ink counterpart of a focused text block (iPad): a dashed accent box
/// around the selected strokes with a dark strip below — drag the box to move
/// the ink, duplicate or delete it. Lives in content coordinates; the parent
/// applies the canvas zoom/pan transform.
///
/// Dragging lifts the strokes into an image (`.beginStrokeDrag`) so box and
/// ink move together at full frame rate — mutating the drawing per tick
/// re-rasterizes the whole canvas and visibly lagged. `.endStrokeDrag` drops
/// the strokes translated; the canvas re-selects them.
struct StrokeSelectionOverlay: View {
    @Binding var selection: StrokeSelection?
    /// Routes edits into the canvas.
    var onCommand: (CanvasCommand) -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var lifting = false

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
                .overlay {
                    if let image = current.dragImage {
                        Image(uiImage: image)
                            .resizable()
                            .padding(10) // box = rect + 10pt on every side
                    }
                }
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

    private func dragGesture(_ current: StrokeSelection) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if !lifting {
                    lifting = true
                    onCommand(.beginStrokeDrag(current.indices))
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                lifting = false
                dragOffset = .zero
                // The canvas re-inserts the strokes translated and re-selects
                // them (fresh indices + rect arrive via onInkSelection).
                onCommand(.endStrokeDrag(dx: value.translation.width,
                                         dy: value.translation.height))
            }
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
