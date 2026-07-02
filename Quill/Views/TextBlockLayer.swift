import SwiftUI

/// Renders a pad's text blocks over the canvas (in content coordinates — the
/// parent applies the canvas's zoom/pan transform to this whole layer).
///
/// In pen mode it's display-only. In text mode the canvas is frozen and this
/// layer takes over: tap empty space to add a block (or to deselect first);
/// the focused block shows a floating control strip ABOVE it — drag to move,
/// A−/A+ to resize, trash to delete. The strip is an overlay, so the block
/// itself never shifts when it appears.
struct TextBlockLayer: View {
    @Binding var texts: [TextBlock]
    let editing: Bool
    /// Mirrors whether any block is focused (drives Esc behavior upstream).
    @Binding var hasFocusedBlock: Bool
    /// Parent increments to force-deselect (Esc).
    let deselectSignal: Int
    var onChanged: () -> Void

    @FocusState private var focused: UUID?
    /// In-flight drag offset for the block being moved.
    @State private var dragOffset: CGSize = .zero
    @State private var draggingID: UUID?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if editing {
                // Tap empty space: deselect first; if nothing selected, add.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        if focused != nil {
                            focused = nil
                        } else {
                            addBlock(at: location)
                        }
                    }
            }
            ForEach($texts) { $block in
                blockView($block)
            }
        }
        .coordinateSpace(name: "textLayer") // stable space for drag deltas
        .allowsHitTesting(editing)
        .onChange(of: focused) { _, value in
            hasFocusedBlock = value != nil
        }
        .onChange(of: deselectSignal) { _, _ in
            focused = nil
        }
        .onChange(of: editing) { _, nowEditing in
            if !nowEditing { focused = nil }
        }
    }

    // MARK: - Block

    private func blockView(_ block: Binding<TextBlock>) -> some View {
        let value = block.wrappedValue
        let isDragging = draggingID == value.id
        let isFocused = focused == value.id

        return TextField("Text", text: block.text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: value.size))
            .focused($focused, equals: value.id)
            .disabled(!editing)
            .onSubmit { onChanged() }
            .frame(minWidth: 60, maxWidth: 360, alignment: .leading)
            .padding(6)
            .background(editing ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(editing ? Color.accentColor.opacity(isFocused ? 0.7 : 0.3) : .clear,
                            lineWidth: 1)
            )
            // Floating strip ABOVE the block — out of flow, so focusing never
            // moves the text.
            .overlay(alignment: .topLeading) {
                if editing && isFocused {
                    controlStrip(block)
                        .offset(y: -40)
                }
            }
            .onTapGesture {
                if editing { focused = value.id }
            }
            .offset(x: value.x + (isDragging ? dragOffset.width : 0),
                    y: value.y + (isDragging ? dragOffset.height : 0))
    }

    /// Move / resize / delete controls. Plain buttons with real hit targets —
    /// no Menu (flaky on Catalyst overlays).
    private func controlStrip(_ block: Binding<TextBlock>) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .controlIcon()
                .gesture(dragGesture(for: block))

            Button {
                block.wrappedValue.size = max(11, block.wrappedValue.size - 2)
                onChanged()
            } label: {
                Image(systemName: "textformat.size.smaller").controlIcon()
            }
            .buttonStyle(.plain)

            Button {
                block.wrappedValue.size = min(60, block.wrappedValue.size + 2)
                onChanged()
            } label: {
                Image(systemName: "textformat.size.larger").controlIcon()
            }
            .buttonStyle(.plain)

            Button {
                focused = nil
                texts.removeAll { $0.id == block.wrappedValue.id }
                onChanged()
            } label: {
                Image(systemName: "trash").controlIcon(tint: .red)
            }
            .buttonStyle(.plain)
        }
        .padding(3)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 1)
        .fixedSize() // never squeezed by the block's width
    }

    private func dragGesture(for block: Binding<TextBlock>) -> some Gesture {
        DragGesture(coordinateSpace: .named("textLayer"))
            .onChanged { value in
                draggingID = block.wrappedValue.id
                dragOffset = value.translation
            }
            .onEnded { value in
                block.wrappedValue.x += value.translation.width
                block.wrappedValue.y += value.translation.height
                draggingID = nil
                dragOffset = .zero
                onChanged()
            }
    }

    private func addBlock(at location: CGPoint) {
        let block = TextBlock(x: location.x, y: location.y)
        texts.append(block)
        focused = block.id
        onChanged()
    }
}

private extension Image {
    func controlIcon(tint: Color = .primary) -> some View {
        self
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 30, height: 28)
            .contentShape(Rectangle())
    }
}
