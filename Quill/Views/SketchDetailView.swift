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
            Divider()
            canvasStack
        }
        .background(Color(uiColor: .systemBackground))
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        #else
        canvasStack
            .navigationTitle(sketch.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) { textModeButton }
                ToolbarItem(placement: .primaryAction) { paperMenu }
                if connectivity.peerOpenSketchID == sketch.id {
                    ToolbarItem(placement: .primaryAction) { presenceBadge }
                }
            }
        #endif
    }

    private var canvasStack: some View {
        ZStack {
            // Paper, text blocks, and remote cursor live in canvas CONTENT
            // coordinates; these transforms keep them glued to the ink at any
            // zoom/pan. Paper sits under the ink; text + cursor above it.
            PaperBackgroundView(style: paper)
                .scaleEffect(canvasScale, anchor: .topLeading)
                .offset(x: -canvasOffset.x, y: -canvasOffset.y)
                .ignoresSafeArea(edges: .bottom)

            if let initialDrawing {
                CanvasView(
                    initialDrawing: initialDrawing,
                    commands: commandRelay.eraseToAnyPublisher(),
                    tool: macToolOrNil,
                    zoomRequest: zoomRequest,
                    onDrawingChanged: { data in
                        store.saveDrawing(sketch.id, data: data,
                                          bumpVersion: connectivity.shouldBumpVersion(for: sketch.id))
                    },
                    onStrokeDelta: { delta in connectivity.sendStrokes(delta) },
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

    private var macToolOrNil: PKTool? {
        #if targetEnvironment(macCatalyst)
        return macTool
        #else
        return nil
        #endif
    }

    #if targetEnvironment(macCatalyst)
    /// Zoom out / reset / in. iPad zooms by pinching; the Mac gets buttons
    /// (trackpad pinch works too).
    private var zoomControls: some View {
        HStack(spacing: 0) {
            Button {
                requestZoom(step: -0.5)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 17))
                    .frame(width: 38, height: 34)
            }
            Button {
                requestZoomReset()
            } label: {
                Text("\(Int((canvasScale * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .frame(minWidth: 56)
            }
            .help("Reset zoom")
            Button {
                requestZoom(step: 0.5)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 17))
                    .frame(width: 38, height: 34)
            }
        }
        .buttonStyle(.plain)
        .background(Color(uiColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 8))
    }

    private func requestZoom(step: CGFloat) {
        // Step from the last REQUESTED zoom, not from canvasScale — the state
        // can lag an in-flight animation, which made repeated presses no-ops.
        let base = zoomRequest?.scale ?? canvasScale
        let clamped = min(4, max(1, base + step))
        zoomRequest = (id: (zoomRequest?.id ?? 0) + 1, scale: clamped)
    }

    private func requestZoomReset() {
        zoomRequest = (id: (zoomRequest?.id ?? 0) + 1, scale: 1)
    }
    #endif

    /// Persist + broadcast the current text blocks.
    private func commitTexts() {
        store.saveTexts(sketch.id, texts,
                        bumpVersion: connectivity.shouldBumpVersion(for: sketch.id))
        connectivity.sendTexts(texts)
    }

    private var textModeButton: some View {
        Button {
            if editingTexts { commitTexts() } // leaving text mode commits
            editingTexts.toggle()
        } label: {
            Image(systemName: editingTexts ? "pencil.tip.crop.circle" : "textformat")
        }
        .help(editingTexts ? "Back to drawing" : "Add and edit text")
    }

    #if targetEnvironment(macCatalyst)
    /// Pen-free bar: the canvas lives entirely below it, so PencilKit's input
    /// machinery can never claim clicks on these controls. One compact,
    /// flat, Mac-style row: back · tools · zoom · presence · text · paper.
    private var macTopBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 42, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Esc: deselect a focused text block first; else go back.
            .background(
                Button("") {
                    if hasFocusedBlock {
                        deselectSignal += 1
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
            )

            Divider().frame(height: 22)

            MacToolStrip(tool: $macTool)
                .disabled(editingTexts)
                .opacity(editingTexts ? 0.4 : 1)

            Spacer(minLength: 12)

            zoomControls

            if connectivity.peerOpenSketchID == sketch.id {
                Image(systemName: "person.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
                    .help("\(connectivity.peerName ?? "Peer") is in this pad")
            }

            textModeButton
                .buttonStyle(.plain)
                .font(.system(size: 19, weight: .medium))
                .frame(width: 42, height: 36)
                .background(editingTexts ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 8))

            paperMenu
                .font(.system(size: 19, weight: .medium))
                .frame(width: 42, height: 36)
                .contentShape(Rectangle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    #endif

    private var paperMenu: some View {
        Menu {
            ForEach(PaperStyle.allCases, id: \.self) { style in
                Button {
                    setPaper(style)
                } label: {
                    Label(style.label, systemImage: style.symbolName)
                }
            }
        } label: {
            Image(systemName: "doc.text")
        }
    }

    private func setPaper(_ style: PaperStyle) {
        paper = style
        store.setPaper(sketch.id, style,
                       bumpVersion: connectivity.shouldBumpVersion(for: sketch.id))
        connectivity.sendPaper(style)
    }

    private var presenceBadge: some View {
        Label(connectivity.peerName ?? "Peer", systemImage: "person.fill")
            .labelStyle(.titleAndIcon)
            .font(.caption)
            .foregroundStyle(.green)
    }
}
