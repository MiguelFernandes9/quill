import SwiftUI
import Combine
import PencilKit

/// The drawing screen: paper background, canvas, remote ghost cursor, paper
/// switcher, and a presence badge when the peer is in the same pad.
struct SketchDetailView: View {
    let sketch: SketchDigest

    @EnvironmentObject private var store: SketchStore
    @EnvironmentObject private var connectivity: ConnectivityManager
    @Environment(\.dismiss) private var dismiss

    /// Bridges `ConnectivityManager.canvasCommands` (all pads) to this canvas.
    @State private var commandRelay = PassthroughSubject<CanvasCommand, Never>()

    /// Loaded once from disk, so cursor/presence re-renders don't re-read files.
    @State private var initialDrawing: Data?
    @State private var paper: PaperStyle = .blank
    @State private var texts: [TextBlock] = []
    /// Text mode: canvas frozen, blocks editable. Pen mode: blocks display-only.
    @State private var editingTexts = false
    /// Mac: tool driven by MacToolStrip. nil on iPad (Apple palette drives it).
    @State private var macTool: PKTool = PKInkingTool(.pen, color: .label, width: 4)

    /// Canvas zoom/pan, mirrored so the paper/text/cursor overlays track it.
    @State private var canvasScale: CGFloat = 1
    @State private var canvasOffset: CGPoint = .zero
    @State private var zoomRequest: (id: Int, scale: CGFloat)?
    @State private var zoomRequestedAt: Date?
    /// Text-block focus (drives Esc: deselect first, then go back).
    @State private var hasFocusedBlock = false
    @State private var deselectSignal = 0

    var body: some View {
        #if targetEnvironment(macCatalyst)
        // Mac: PencilKit's window-level writing machinery claims ANY click
        // over the canvas region — including overlaid buttons and the system
        // back button (verified via EventTrace: enabled button, delivered
        // clicks, action never fires). Only robust fix: the canvas must not
        // exist under the controls. Dedicated top bar; canvas starts below it.
        VStack(spacing: 0) {
            macTopBar
            QuillTheme.hairline.frame(height: 1)
            canvasStack
        }
        .background(QuillTheme.background)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        #else
        // iPad (mocks 2b/4b): same pen-free custom bar pattern, touch-sized.
        VStack(spacing: 0) {
            iPadTopBar
            QuillTheme.hairline.frame(height: 1)
            canvasStack
        }
        .background(QuillTheme.background)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private var canvasStack: some View {
        GeometryReader { geo in
            canvasContent(viewportSize: geo.size)
        }
    }

    /// The canvas viewport in content coordinates at the current zoom/pan.
    private func visibleContentRect(_ size: CGSize) -> CGRect {
        CGRect(x: canvasOffset.x / canvasScale,
               y: canvasOffset.y / canvasScale,
               width: size.width / canvasScale,
               height: size.height / canvasScale)
    }

    private func canvasContent(viewportSize: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            // Text blocks and the remote cursor live in canvas CONTENT
            // coordinates; the transform below keeps them glued to the ink at
            // any zoom/pan. Paper stays viewport-sized and phase-shifts its
            // pattern instead — the growing page scrolls over endless paper.
            PaperBackgroundView(style: paper, scale: canvasScale, offset: canvasOffset)
                .ignoresSafeArea(edges: .bottom)

            if let initialDrawing {
                CanvasView(
                    initialDrawing: initialDrawing,
                    commands: commandRelay.eraseToAnyPublisher(),
                    tool: macToolOrNil,
                    zoomRequest: zoomRequest,
                    contentBottomHint: textBottomEdge,
                    onDrawingChanged: { data in
                        store.saveDrawing(sketch.id, data: data,
                                          bumpVersion: connectivity.shouldBumpVersion(for: sketch.id))
                    },
                    onStrokeDelta: { delta in connectivity.sendStrokes(delta) },
                    onDrawingResync: { data in connectivity.sendDrawing(data) },
                    onCursor: { point, down in connectivity.sendCursor(point, down: down) },
                    onTransform: { scale, offset in
                        canvasScale = scale
                        canvasOffset = offset
                    }
                )
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(!editingTexts) // text mode freezes the pen
            }

            ZStack(alignment: .topLeading) {
                TextBlockLayer(texts: $texts, editing: editingTexts,
                               visibleRect: visibleContentRect(viewportSize),
                               hasFocusedBlock: $hasFocusedBlock,
                               deselectSignal: deselectSignal) {
                    commitTexts()
                }
                RemoteCursorLayer()
            }
            .scaleEffect(canvasScale, anchor: .topLeading)
            .offset(x: -canvasOffset.x, y: -canvasOffset.y)
            .ignoresSafeArea(edges: .bottom)
        }
        // Zoomed/panned overlay layers must never escape the canvas area and
        // slide over the top bar.
        .clipped()
        .onAppear {
            if initialDrawing == nil {
                initialDrawing = store.loadDrawing(sketch.id)
                paper = store.metadata(sketch.id)?.paper ?? .blank
                texts = store.loadTexts(sketch.id)
            }
            connectivity.setOpenSketch(sketch.id)
        }
        .onDisappear {
            if editingTexts { commitTexts() }
            connectivity.setOpenSketch(nil)
        }
        // EVERY way out of text mode commits — Esc and the iPad button used
        // to, but the Mac tool strip didn't, so Mac-typed text reached the
        // peer only on pad close while iPad-typed text arrived immediately.
        .onChange(of: editingTexts) { _, editing in
            if !editing { commitTexts() }
        }
        .onReceive(connectivity.canvasCommands) { id, command in
            guard id == sketch.id else { return }
            switch command {
            case let .setPaper(style): paper = style
            case let .setTexts(remote): texts = remote
            default: break
            }
            commandRelay.send(command)
        }
    }

    /// Lowest text-block edge (content coordinates) so the page grows past
    /// blocks too, not only ink. Auto-height blocks are estimated — the page
    /// only ever over-provisions, never clips.
    private var textBottomEdge: CGFloat {
        texts.map { CGFloat($0.y) + CGFloat($0.height ?? max(44, $0.size * 1.6)) }
            .max() ?? 0
    }

    private var macToolOrNil: PKTool? {
        #if targetEnvironment(macCatalyst)
        return macTool
        #else
        return nil
        #endif
    }

    #if targetEnvironment(macCatalyst)
    /// Zoom out / reset / in (mock 4a: white bg, hairline, tabular numerals).
    /// iPad zooms by pinching; the Mac gets buttons (trackpad pinch works too).
    private var zoomControls: some View {
        HStack(spacing: 0) {
            Button {
                requestZoom(step: -0.5)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 16))
                    .frame(width: 36, height: 34)
            }
            Button {
                requestZoomReset()
            } label: {
                Text("\(Int((canvasScale * 100).rounded()))%")
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .frame(minWidth: 54)
            }
            .help("Reset zoom")
            Button {
                requestZoom(step: 0.5)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 16))
                    .frame(width: 36, height: 34)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(QuillTheme.secondaryText)
        .background(QuillTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(QuillTheme.hairline, lineWidth: 1))
    }

    private func requestZoom(step: CGFloat) {
        // While a button-driven zoom animation is in flight (~0.35s), step from
        // the requested target — canvasScale lags the animation and made rapid
        // presses no-ops. Once settled (or after a pinch, which never issues a
        // request), step from the REAL current scale, or buttons appear
        // blocked after pinching.
        let animationInFlight = zoomRequestedAt.map { Date().timeIntervalSince($0) < 0.4 } ?? false
        let base = animationInFlight ? (zoomRequest?.scale ?? canvasScale) : canvasScale
        issueZoom(min(4, max(1, base + step)))
    }

    private func requestZoomReset() {
        issueZoom(1)
    }

    private func issueZoom(_ scale: CGFloat) {
        zoomRequest = (id: (zoomRequest?.id ?? 0) + 1, scale: scale)
        zoomRequestedAt = Date()
    }
    #endif

    /// Persist + broadcast the current text blocks.
    private func commitTexts() {
        store.saveTexts(sketch.id, texts,
                        bumpVersion: connectivity.shouldBumpVersion(for: sketch.id))
        connectivity.sendTexts(texts)
    }

    /// Section name for the bar's muted subtitle.
    private var sectionName: String? {
        sketch.sectionID.flatMap { store.section($0)?.name }
    }

    /// Green presence badge: eye icon only, shown when the peer is in this
    /// pad (hover/long-press reveals who).
    private var presenceChip: some View {
        Image(systemName: "eye.fill")
            .font(.system(size: 12))
            .foregroundStyle(QuillTheme.greenChipText)
            .frame(width: QuillTheme.rowHeight >= 44 ? 34 : 30,
                   height: QuillTheme.rowHeight >= 44 ? 34 : 30)
            .background(QuillTheme.greenChipBackground, in: Circle())
            .overlay(Circle().stroke(QuillTheme.greenChipBorder, lineWidth: 1))
            .help("\(PeerLabel.short(connectivity.peerName)) is in this pad")
    }

    /// Paper chip: icon + current style name, opens the style menu.
    private var paperChip: some View {
        Menu {
            ForEach(PaperStyle.allCases, id: \.self) { style in
                Button {
                    setPaper(style)
                } label: {
                    Label(style.label, systemImage: style.symbolName)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: paper.symbolName).font(.system(size: 12))
                Text(paper.label)
                    .font(.system(size: 12 + QuillTheme.typeBump, weight: .medium))
            }
            .foregroundStyle(QuillTheme.secondaryText)
            .padding(.horizontal, 9)
            .frame(height: QuillTheme.rowHeight >= 44 ? 38 : 30)
            .background(QuillTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(QuillTheme.hairline, lineWidth: 1))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .opacity(editingTexts ? 0.35 : 1)
        .disabled(editingTexts)
        .animation(.easeInOut(duration: 0.15), value: editingTexts)
        .help("Paper style")
    }

    #if targetEnvironment(macCatalyst)
    /// Pen-free bar (mock 4a): the canvas lives entirely below it, so
    /// PencilKit's input machinery can never claim clicks on these controls.
    /// back · title · section · | · tool switcher · colors · width · zoom ·
    /// presence · paper.
    private var macTopBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(QuillTheme.ink)
                    .frame(width: 38, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(escHandler)

            Text(sketch.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(QuillTheme.ink)
                .lineLimit(1)
            if let sectionName {
                Text(sectionName)
                    .font(.system(size: 14))
                    .foregroundStyle(QuillTheme.muted)
                    .lineLimit(1)
            }

            QuillTheme.hairline.frame(width: 1, height: 24)

            MacToolStrip(tool: $macTool, textActive: $editingTexts)

            Spacer(minLength: 12)

            zoomControls

            if connectivity.peerOpenSketchID == sketch.id {
                presenceChip
            }

            paperChip
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(QuillTheme.background)
    }

    /// Esc chain: deselect a focused block → exit the Text tool → go back.
    private var escHandler: some View {
        Button("") {
            if hasFocusedBlock {
                deselectSignal += 1
            } else if editingTexts {
                editingTexts = false // snaps MacToolStrip back to Pen; commits via onChange
            } else {
                dismiss()
            }
        }
        .keyboardShortcut(.cancelAction)
        .opacity(0)
        .accessibilityHidden(true)
    }
    #else
    /// iPad bar (mocks 2b/4b): accent back, centered title, presence chip,
    /// Text-tool button, paper chip. Touch-sized; hairline bottom.
    private var iPadTopBar: some View {
        ZStack {
            Text(sketch.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(QuillTheme.ink)
                .lineLimit(1)

            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Pads").font(.system(size: 15))
                    }
                    .foregroundStyle(QuillTheme.accent)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                if connectivity.peerOpenSketchID == sketch.id {
                    presenceChip
                }

                textToolButton

                paperChip
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(QuillTheme.background)
    }

    /// iPad Text tool (mock 4b): 44×38, accent bg + soft ring when active.
    private var textToolButton: some View {
        Button {
            editingTexts.toggle() // leaving the tool commits via onChange
        } label: {
            Image(systemName: "character.cursor.ibeam")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(editingTexts ? .white : QuillTheme.ink)
                .frame(width: 44, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(editingTexts ? QuillTheme.accent : QuillTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(editingTexts ? QuillTheme.accentSoft : QuillTheme.hairline,
                                lineWidth: editingTexts ? 3 : 1)
                )
        }
        .buttonStyle(.plain)
    }
    #endif

    private func setPaper(_ style: PaperStyle) {
        paper = style
        store.setPaper(sketch.id, style,
                       bumpVersion: connectivity.shouldBumpVersion(for: sketch.id))
        connectivity.sendPaper(style)
    }
}
