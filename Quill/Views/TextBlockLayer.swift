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
    /// Select `blockID` (resolved by the parent against REAL frames) or
    /// create a block at `point` (content coordinates). `id` increments per
    /// request.
    var focusRequest: (id: Int, point: CGPoint, blockID: UUID?)?
    /// Reports every block's ACTUAL rendered rect (content coordinates) —
    /// the canvas-side hit-tests need real frames, not estimates.
    var onFrames: (([UUID: CGRect]) -> Void)? = nil
    var onChanged: () -> Void

    @FocusState private var focused: UUID?
    /// Two-step activation, Notes-style: a first press SELECTS a block
    /// (chrome + drag, no keyboard, so no Cut/Copy bar can appear); tapping
    /// the selected block again FOCUSES its field for typing.
    @State private var selected: UUID?
    /// In-flight drag offset for the block being moved.
    @State private var dragOffset: CGSize = .zero
    @State private var draggingID: UUID?
    /// Each block's measured box rect (content coords) — the resize gesture
    /// needs the box size as its start size for auto-sized blocks.
    @State private var boxRects: [UUID: CGRect] = [:]

    private var activeID: UUID? { focused ?? selected }

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
            #if targetEnvironment(macCatalyst)
            // Mac only: the frozen canvas can't deliver empty clicks, so a
            // catcher provides click-empty-to-DESELECT. Adding a block is the
            // right-click menu's job now — an empty click must never plant
            // one (that leftover made stray blocks pop in). On iPad the canvas
            // stays LIVE while a block is selected and deselects on its own.
            if editing {
                Color.clear
                    .frame(width: visibleRect.width, height: visibleRect.height)
                    .contentShape(Rectangle())
                    .onTapGesture { _ in
                        if activeID != nil { deactivate() }
                    }
                    .offset(x: visibleRect.minX, y: visibleRect.minY)
            }
            #endif
            ForEach($texts) { $block in
                blockView($block)
            }
        }
        // Always fill the canvas: in pen mode the expanding tap-catcher is
        // gone, and a shrunk-to-content layer gets re-centered by the parent
        // ZStack — every block visually jumps on tool switch.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coordinateSpace(name: "textLayer") // stable space for drag deltas
        .onPreferenceChange(BlockFramesKey.self) { frames in
            boxRects = frames
            onFrames?(frames)
        }
        .allowsHitTesting(editing)
        .onChange(of: focused) { old, value in
            if let value { selected = value } // typing implies selected
            hasFocusedBlock = activeID != nil
            // Leaving a block commits its typed text — otherwise content typed
            // without a trailing Return only syncs when text mode ends.
            if old != nil { onChanged() }
        }
        .onChange(of: selected) { _, _ in
            hasFocusedBlock = activeID != nil
        }
        .onChange(of: deselectSignal) { _, _ in
            deactivate()
        }
        .onChange(of: editing) { _, nowEditing in
            if !nowEditing { deactivate() }
        }
        .onChange(of: focusRequest?.id) { _, _ in
            guard editing, let request = focusRequest else { return }
            // A press on an existing block SELECTS it (no keyboard yet — that
            // keeps the text Cut/Copy bar away); on empty paper it plants a
            // fresh block, which does open for typing straight away. The
            // parent resolved the block against real frames — never re-derive
            // it here from the estimate.
            if let blockID = request.blockID, texts.contains(where: { $0.id == blockID }) {
                selected = blockID
            } else {
                addBlock(at: request.point)
            }
        }
    }

    private func deactivate() {
        focused = nil
        selected = nil
    }

    // MARK: - Block

    private func blockView(_ block: Binding<TextBlock>) -> some View {
        let value = block.wrappedValue
        let isDragging = draggingID == value.id
        let isFocused = focused == value.id
        let isActive = activeID == value.id

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
            // Enabled only for the ACTIVE block: an inactive field can't
            // grab taps or pop the text Cut/Copy bar; a selected one accepts
            // the second tap that starts typing.
            .disabled(!editing || !isActive)
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
                .fill(Color.white.opacity(isActive ? 0.85 : 0.72))
                .opacity((editing && isActive) || !value.text.isEmpty ? 1 : 0)
        )
        // Only the PRESSED block shows its border — text mode is entered
        // per-object now, so lighting up every block's box on one press
        // read as a bug (it was the old Text-tool's "reveal all" look).
        .overlay(
            RoundedRectangle(cornerRadius: blockRadius)
                .stroke(QuillTheme.accent, style: StrokeStyle(lineWidth: 1.5))
                .opacity(editing && isActive ? 1 : 0)
        )
        // Focus tap covers the block body ONLY — attached BEFORE the strip
        // overlay, or the parent gesture swallows the strip's buttons
        // (that's what broke delete). First tap selects; the second starts
        // typing.
        .contentShape(RoundedRectangle(cornerRadius: blockRadius))
        .onTapGesture {
            guard editing else { return }
            if selected == value.id, focused != value.id {
                focused = value.id
            } else if !isActive {
                selected = value.id
            }
        }
        // Drag anywhere on an UNFOCUSED block to move it (intuitive drag &
        // drop) — high priority so the text field underneath can't claim the
        // drag. A focused block keeps its text interactions (its Mac field
        // editor owns that rect anyway) — move it with the strip's ✥ handle.
        .highPriorityGesture(dragGesture(for: block), including: isFocused ? .subviews : .all)
        // Report the BOX's rect (model origin + measured size) for the
        // canvas-side hit-tests. Measured BEFORE the margin padding below.
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: BlockFramesKey.self,
                                       value: [value.id: CGRect(x: value.x, y: value.y,
                                                                width: geo.size.width,
                                                                height: geo.size.height)])
            }
        )
        // A REAL margin around the box. SwiftUI never hit-tests content drawn
        // outside a view's frame, so the previous out-of-corner handles (an
        // overlay grown with NEGATIVE padding) rendered but received nothing —
        // that's why the body drag worked and the handles were dead. Positive
        // padding makes the container frame genuinely CONTAIN the handles, so
        // their hit area sits inside a real frame. The block's offset is
        // pulled back by the margin so nothing shifts visually.
        .padding(handleMargin)
        // Four corner handles, each placed with .overlay(alignment:) + a tiny
        // fixed offset — the SAME structure as the working control strip. The
        // earlier GeometryReader-fill + large per-handle .offset drew the dots
        // correctly but their hit targets never moved with the offset, so even
        // a Button there received nothing while the strip's buttons worked.
        .overlay(alignment: .topLeading) {
            if editing && isActive { cornerHandle(block, leading: true, top: true) }
        }
        .overlay(alignment: .topTrailing) {
            if editing && isActive { cornerHandle(block, leading: false, top: true) }
        }
        .overlay(alignment: .bottomLeading) {
            if editing && isActive { cornerHandle(block, leading: true, top: false) }
        }
        .overlay(alignment: .bottomTrailing) {
            if editing && isActive { cornerHandle(block, leading: false, top: false) }
        }
        // Control strip floats centered BELOW the block (mock 4a/4b). The
        // container now extends `handleMargin` past the box, so pull the strip
        // back up by it to keep the same gap under the box.
        .overlay(alignment: .bottom) {
            if editing && isActive {
                controlStrip(block)
                    .offset(y: stripOffset - handleMargin)
            }
        }
        .offset(x: value.x - handleMargin + (isDragging ? dragOffset.width : 0),
                y: value.y - handleMargin + (isDragging ? dragOffset.height : 0))
    }

    /// Margin of transparent, hittable space padded around every block so the
    /// out-of-corner resize handles fall inside a real frame.
    private var handleMargin: CGFloat { 28 }

    /// One corner handle. The drag is driven by a real UIKit
    /// `UIPanGestureRecognizer` (`ResizePanHandle`), NOT a SwiftUI gesture:
    /// on Mac Catalyst, SwiftUI drag gestures on overlays over the frozen
    /// canvas never fire (even a Button placed there via a filled overlay was
    /// dead), while real UIKit controls — like the strip's buttons — do get
    /// events. The white circle is drawn on top, non-interactive.
    private func cornerHandle(_ block: Binding<TextBlock>, leading: Bool, top: Bool) -> some View {
        let out: CGFloat = handleSize / 2 + 6
        let hit: CGFloat = 34 // UIKit hit-view size
        // Container corner is `handleMargin` beyond the box; nudge inward so the
        // handle centre lands `out` beyond the box corner.
        let inset = handleMargin - hit / 2 - out
        let boxSize = boxRects[block.wrappedValue.id]?.size
            ?? CGSize(width: block.wrappedValue.width ?? 200,
                      height: block.wrappedValue.height ?? 44)
        return ResizePanHandle(
            onChanged: { t in
                applyResize(block, leading: leading, top: top, startSize: boxSize, translation: t)
            },
            onEnded: { resizeStart = nil; onChanged() }
        )
        .frame(width: hit, height: hit)
        .overlay(
            Circle()
                .fill(.white)
                .overlay(Circle().stroke(QuillTheme.accent, lineWidth: 1.5))
                .frame(width: handleSize, height: handleSize)
                .allowsHitTesting(false)
        )
        .offset(x: leading ? inset : -inset, y: top ? inset : -inset)
    }

    /// Shared resize math: sets the box's width/height (and x/y for the
    /// left/top edges) from a drag translation in content coordinates.
    private func applyResize(_ block: Binding<TextBlock>, leading: Bool, top: Bool,
                             startSize: CGSize, translation: CGSize) {
        if resizeStart == nil {
            resizeStart = (startSize, block.wrappedValue.x, block.wrappedValue.y)
        }
        guard let start = resizeStart else { return }
        let dx = translation.width
        let dy = translation.height
        let newWidth = max(60, min(800, leading ? start.size.width - dx : start.size.width + dx))
        let newHeight = max(32, min(800, top ? start.size.height - dy : start.size.height + dy))
        block.wrappedValue.width = Double(newWidth)
        block.wrappedValue.height = Double(newHeight)
        if leading { block.wrappedValue.x = start.x + Double(start.size.width - newWidth) }
        if top { block.wrappedValue.y = start.y + Double(start.size.height - newHeight) }
    }

    /// In-flight resize bookkeeping (box size and origin at drag start).
    @State private var resizeStart: (size: CGSize, x: Double, y: Double)?

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
                deactivate()
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

    /// Step the block's font size. The size-keyed field identity recreates
    /// the field, which would drop an active FOCUS — re-assert it, but only
    /// if the user was actually typing (a merely-selected block must not
    /// summon the keyboard from A±).
    private func resize(_ block: Binding<TextBlock>, by step: Double) {
        let id = block.wrappedValue.id
        let wasFocused = focused == id
        block.wrappedValue.size = min(60, max(11, block.wrappedValue.size + step))
        onChanged()
        if wasFocused {
            DispatchQueue.main.async { focused = id }
        }
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
        selected = block.id
        focused = block.id // fresh block: straight to typing
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

/// A transparent UIKit view with a `UIPanGestureRecognizer`, bridged into
/// SwiftUI. Used for the corner resize handles because SwiftUI drag gestures
/// on overlays above the frozen PKCanvasView never fire on Mac Catalyst,
/// whereas real UIKit gesture recognizers (like the ones backing the working
/// strip buttons) do. Reports the pan translation in the view's own
/// coordinate space — which equals canvas CONTENT space, since an ancestor
/// applies the zoom transform, so deltas are already zoom-correct.
private struct ResizePanHandle: UIViewRepresentable {
    var onChanged: (CGSize) -> Void
    var onEnded: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handle(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    final class Coordinator: NSObject {
        var onChanged: ((CGSize) -> Void)?
        var onEnded: (() -> Void)?

        @objc func handle(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            switch g.state {
            case .changed:
                onChanged?(CGSize(width: t.x, height: t.y))
            case .ended, .cancelled, .failed:
                onEnded?()
            default:
                break
            }
        }
    }
}
