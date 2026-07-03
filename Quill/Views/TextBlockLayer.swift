import SwiftUI

/// Renders a pad's text blocks over the canvas (in content coordinates — the
/// parent applies the canvas's zoom/pan transform to this whole layer).
///
/// In pen mode it's display-only. In text mode the canvas is frozen and this
/// layer takes over: tap empty space to add a block (or to deselect first);
/// the focused block shows a floating control strip ABOVE it — drag to move,
/// A−/A+ to resize, trash to delete. The strip is an overlay, so the block
/// itself never shifts when it appears.
/// Collects every block's rendered rect (content coordinates).
struct BlockFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct TextBlockLayer: View {
    @Binding var texts: [TextBlock]
    let editing: Bool
    /// The canvas viewport in CONTENT coordinates. The tap-catcher is pinned
    /// to exactly this rect — a full-size catcher, scaled and panned, extends
    /// past the canvas in hit-test space and eats toolbar clicks (clipping is
    /// visual only; hit-testing ignores it).
    let visibleRect: CGRect
    /// Mirrors whether any block is focused (drives Esc behavior upstream).
    @Binding var hasFocusedBlock: Bool
    /// Parent increments to force-deselect (Esc).
    let deselectSignal: Int
    /// iPad long-press: focus the block at `point` (content coordinates) or
    /// create one there. `id` increments per request.
    var focusRequest: (id: Int, point: CGPoint)?
    /// Reports every block's ACTUAL rendered rect (content coordinates) —
    /// the canvas-side hit-tests need real frames, not estimates.
    var onFrames: (([UUID: CGRect]) -> Void)? = nil
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
                // Sized to the visible viewport only — never over the bar.
                Color.clear
                    .frame(width: visibleRect.width, height: visibleRect.height)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        if focused != nil {
                            focused = nil
                        } else {
                            addBlock(at: CGPoint(x: location.x + visibleRect.minX,
                                                 y: location.y + visibleRect.minY))
                        }
                    }
                    .offset(x: visibleRect.minX, y: visibleRect.minY)
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
        .onPreferenceChange(BlockFramesKey.self) { onFrames?($0) }
        .allowsHitTesting(editing)
        .onChange(of: focused) { old, value in
            hasFocusedBlock = value != nil
            // Leaving a block commits its typed text — otherwise content typed
            // without a trailing Return only syncs when text mode ends.
            if old != nil { onChanged() }
        }
        .onChange(of: deselectSignal) { _, _ in
            focused = nil
        }
        .onChange(of: editing) { _, nowEditing in
            if !nowEditing { focused = nil }
        }
        .onChange(of: focusRequest?.id) { _, _ in
            guard editing, let request = focusRequest else { return }
            // A press on an existing block edits it; on empty paper it plants
            // a new one. Bounds are estimated for auto-sized blocks — a miss
            // just means a fresh block next to the old one.
            if let hit = texts.last(where: { $0.approxRect.contains(request.point) }) {
                focused = hit.id
            } else {
                addBlock(at: request.point)
            }
        }
    }

    // MARK: - Block

    private func blockView(_ block: Binding<TextBlock>) -> some View {
        let value = block.wrappedValue
        let isDragging = draggingID == value.id
        let isFocused = focused == value.id

        // The FIELD keeps its own content-driven layout (the Mac idiom needs a
        // layout change per keystroke or typed text doesn't render); the BOX
        // around it carries the user-set width/height from handle resizing.
        let field = TextField("Text", text: block.text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: value.size))
            .foregroundStyle(QuillTheme.ink)
            // Font-only changes don't relayout a live field in the Mac idiom —
            // identity is keyed to size (focus re-asserted by A±). Box changes
            // are frame changes and relayout normally: keep them OUT of the key
            // or handle-dragging would recreate the field per tick.
            .id("field-\(value.id)-\(Int(value.size))")
            .focused($focused, equals: value.id)
            .disabled(!editing)
            .onSubmit { onChanged() }
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 40, maxWidth: value.width == nil ? 360 : .infinity,
                   alignment: .leading)

        return ZStack(alignment: .topLeading) {
            field
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
        }
        .frame(width: value.width.map { CGFloat(max($0, 60)) },
               height: value.height.map { CGFloat(max($0, 32)) },
               alignment: .topLeading)
        .clipped() // a box shorter than its text crops, like a real text frame
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
        // Drag anywhere on an UNFOCUSED block to move it (intuitive drag &
        // drop) — high priority so the text field underneath can't claim the
        // drag. A focused block keeps its text interactions (its Mac field
        // editor owns that rect anyway) — move it with the strip's ✥ handle.
        .highPriorityGesture(dragGesture(for: block), including: isFocused ? .subviews : .all)
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
        .background(
            // Blocks are placed via .offset, which never moves GEOMETRY — the
            // real rect is the model origin plus the measured size.
            GeometryReader { geo in
                Color.clear.preference(key: BlockFramesKey.self,
                                       value: [value.id: CGRect(x: value.x, y: value.y,
                                                                width: geo.size.width,
                                                                height: geo.size.height)])
            }
        )
        .offset(x: value.x + (isDragging ? dragOffset.width : 0),
                y: value.y + (isDragging ? dragOffset.height : 0))
    }

    /// Four white circles with accent borders on the block's corners. Dragging
    /// resizes the box as a free rectangle: each handle moves its own two
    /// edges; the opposite corner stays anchored. Drag out a wide short box or
    /// a tall narrow one — the text wraps (and crops) to fit.
    private func resizeHandles(_ block: Binding<TextBlock>) -> some View {
        GeometryReader { geo in
            // Handles sit OUTSIDE the box corners: a focused field (and its
            // Mac field editor) owns events over the block's own rect, which
            // silently ate on-corner handle drags — the strip below the block
            // always worked for exactly this reason.
            let out: CGFloat = handleSize / 2 + 6
            let corners: [(point: CGPoint, leading: Bool, top: Bool)] = [
                (CGPoint(x: -out, y: -out), true, true),
                (CGPoint(x: geo.size.width + out, y: -out), false, true),
                (CGPoint(x: -out, y: geo.size.height + out), true, false),
                (CGPoint(x: geo.size.width + out, y: geo.size.height + out), false, false),
            ]
            ForEach(corners.indices, id: \.self) { index in
                let corner = corners[index]
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(QuillTheme.accent, lineWidth: 1.5))
                    .frame(width: handleSize, height: handleSize)
                    .padding(10) // real hit target around the tiny circle
                    .contentShape(Circle())
                    .position(corner.point)
                    .gesture(resizeGesture(for: block, leading: corner.leading,
                                           top: corner.top, startSize: geo.size))
            }
        }
    }

    /// In-flight resize bookkeeping (box size and origin at drag start).
    @State private var resizeStart: (size: CGSize, x: Double, y: Double)?

    private func resizeGesture(for block: Binding<TextBlock>, leading: Bool,
                               top: Bool, startSize: CGSize) -> some Gesture {
        DragGesture(coordinateSpace: .named("textLayer"))
            .onChanged { drag in
                if resizeStart == nil {
                    resizeStart = (startSize, block.wrappedValue.x, block.wrappedValue.y)
                }
                guard let start = resizeStart else { return }
                let dx = drag.translation.width
                let dy = drag.translation.height

                let newWidth = max(60, min(800, leading ? start.size.width - dx
                                                        : start.size.width + dx))
                let newHeight = max(32, min(800, top ? start.size.height - dy
                                                     : start.size.height + dy))
                block.wrappedValue.width = Double(newWidth)
                block.wrappedValue.height = Double(newHeight)
                if leading { // left edge moves; right edge stays anchored
                    block.wrappedValue.x = start.x + Double(start.size.width - newWidth)
                }
                if top { // top edge moves; bottom edge stays anchored
                    block.wrappedValue.y = start.y + Double(start.size.height - newHeight)
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
