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

    // Studio metrics (mocks 4a/4b): Mac compact, iPad touch-sized.
    #if targetEnvironment(macCatalyst)
    private let blockRadius: CGFloat = 6
    private let handleSize: CGFloat = 7
    private let stripRadius: CGFloat = 9
    private let stripButton = CGSize(width: 34, height: 32)
    private let stripOffset: CGFloat = 44
    #else
    private let blockRadius: CGFloat = 8
    private let handleSize: CGFloat = 9
    private let stripRadius: CGFloat = 12
    private let stripButton = CGSize(width: 48, height: 44)
    private let stripOffset: CGFloat = 58
    #endif

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
        // Always fill the canvas: in pen mode the expanding tap-catcher is
        // gone, and a shrunk-to-content layer gets re-centered by the parent
        // ZStack — every block visually jumps on tool switch.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            .foregroundStyle(QuillTheme.ink)
            // Mac idiom won't relayout a live field on a FONT-only change —
            // A± steps landed in the data but never on screen, so the field's
            // identity is keyed to its size (focus re-asserted by A±). Width
            // is a frame change and relayouts normally — keep it OUT of the
            // key or handle-dragging would recreate the field per tick.
            .id("field-\(value.id)-\(Int(value.size))")
            .focused($focused, equals: value.id)
            .disabled(!editing)
            .onSubmit { onChanged() }
            // Mac idiom doesn't relayout a vertical-axis field per keystroke —
            // typed text stayed invisible until something else (A±) forced a
            // layout pass. Content-sizing forces it every change.
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: value.width.map { CGFloat(max($0, 60)) }, alignment: .leading)
            .frame(minWidth: 60, maxWidth: value.width == nil ? 360 : nil, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            // Idle blocks: dashed hairline over translucent white; selected:
            // solid accent border on a more opaque white (mock 4a/4b).
            .background(
                RoundedRectangle(cornerRadius: blockRadius)
                    .fill(Color.white.opacity(isFocused ? 0.85 : 0.72))
                    .opacity(editing || !value.text.isEmpty ? 1 : 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: blockRadius)
                    .stroke(isFocused ? QuillTheme.accent : QuillTheme.dashedBlock,
                            style: isFocused
                                ? StrokeStyle(lineWidth: 1.5)
                                : StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .opacity(editing ? 1 : 0)
            )
            // Focus tap covers the block body ONLY — attached BEFORE the strip
            // overlay, or the parent gesture swallows the strip's buttons
            // (that's what broke delete).
            .contentShape(RoundedRectangle(cornerRadius: blockRadius))
            .onTapGesture {
                if editing { focused = value.id }
            }
            // Corner handles: drag to resize the block's box (A± = font size).
            .overlay {
                if editing && isFocused {
                    resizeHandles(block)
                }
            }
            // Control strip floats centered BELOW the block (mock 4a/4b).
            .overlay(alignment: .bottom) {
                if editing && isFocused {
                    controlStrip(block)
                        .offset(y: stripOffset)
                }
            }
            .offset(x: value.x + (isDragging ? dragOffset.width : 0),
                    y: value.y + (isDragging ? dragOffset.height : 0))
    }

    /// Four white circles with accent borders on the block's corners. Dragging
    /// any of them resizes the block's box: trailing handles move the right
    /// edge; leading handles move the left edge (x shifts so the right edge
    /// stays put). Height always follows the wrapped text.
    private func resizeHandles(_ block: Binding<TextBlock>) -> some View {
        GeometryReader { geo in
            let corners: [(point: CGPoint, leading: Bool)] = [
                (CGPoint(x: 0, y: 0), true),
                (CGPoint(x: geo.size.width, y: 0), false),
                (CGPoint(x: 0, y: geo.size.height), true),
                (CGPoint(x: geo.size.width, y: geo.size.height), false),
            ]
            ForEach(corners.indices, id: \.self) { index in
                let corner = corners[index]
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(QuillTheme.accent, lineWidth: 1.5))
                    .frame(width: handleSize, height: handleSize)
                    .padding(8) // real hit target around the tiny circle
                    .contentShape(Circle())
                    .position(corner.point)
                    .gesture(resizeGesture(for: block, leading: corner.leading,
                                           startWidth: geo.size.width))
            }
        }
    }

    /// In-flight resize bookkeeping (width and x at drag start).
    @State private var resizeStart: (width: CGFloat, x: Double)?

    private func resizeGesture(for block: Binding<TextBlock>, leading: Bool,
                               startWidth: CGFloat) -> some Gesture {
        DragGesture(coordinateSpace: .named("textLayer"))
            .onChanged { drag in
                if resizeStart == nil {
                    resizeStart = (startWidth, block.wrappedValue.x)
                }
                guard let start = resizeStart else { return }
                let dx = drag.translation.width
                let newWidth = max(60, min(800, leading ? start.width - dx : start.width + dx))
                block.wrappedValue.width = Double(newWidth)
                if leading {
                    // Keep the right edge fixed while the left edge moves.
                    block.wrappedValue.x = start.x + Double(start.width - newWidth)
                }
            }
            .onEnded { _ in
                resizeStart = nil
                onChanged()
            }
    }

    /// Move / resize / delete controls on the dark floating strip. Plain
    /// buttons with real hit targets — no Menu (flaky on Catalyst overlays).
    private func controlStrip(_ block: Binding<TextBlock>) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .stripIcon(size: stripButton)
                .gesture(dragGesture(for: block))

            stripDivider
            Button {
                resize(block, by: -2)
            } label: {
                Text("A−").stripText(size: stripButton, fontSize: 13)
            }
            .buttonStyle(.plain)

            stripDivider
            Button {
                resize(block, by: 2)
            } label: {
                Text("A+").stripText(size: stripButton, fontSize: 17)
            }
            .buttonStyle(.plain)

            stripDivider
            Button {
                // Resign focus first, then remove on the NEXT runloop turn:
                // removing synchronously while the block's TextField is still
                // focused crashes SwiftUI's ForEach-binding write-back.
                let id = block.wrappedValue.id
                focused = nil
                DispatchQueue.main.async {
                    texts.removeAll { $0.id == id }
                    onChanged()
                }
            } label: {
                Image(systemName: "trash").stripIcon(size: stripButton, tint: QuillTheme.softRed)
            }
            .buttonStyle(.plain)
        }
        .background(QuillTheme.darkStrip, in: RoundedRectangle(cornerRadius: stripRadius))
        .shadow(color: .black.opacity(0.22), radius: 7, y: 4)
        .fixedSize() // never squeezed by the block's width
    }

    private var stripDivider: some View {
        Color.white.opacity(0.15).frame(width: 1, height: stripButton.height - 12)
    }

    /// Step the block's font size and keep it focused — the size-keyed field
    /// identity recreates the field, which would otherwise drop focus.
    private func resize(_ block: Binding<TextBlock>, by step: Double) {
        let id = block.wrappedValue.id
        block.wrappedValue.size = min(60, max(11, block.wrappedValue.size + step))
        onChanged()
        DispatchQueue.main.async { focused = id }
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
    func stripIcon(size: CGSize, tint: Color = .white) -> some View {
        self
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
    }
}

private extension Text {
    func stripText(size: CGSize, fontSize: CGFloat) -> some View {
        self
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
    }
}
