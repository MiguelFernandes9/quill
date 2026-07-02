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
            if !editingTexts {
                MacToolStrip(tool: $macTool)
            }
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
        HStack(spacing: 2) {
            Button {
                requestZoom(canvasScale - 0.5)
            } label: {
                Image(systemName: "minus.magnifyingglass").frame(width: 30, height: 30)
            }
            Button {
                requestZoom(1)
            } label: {
                Text("\(Int((canvasScale * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 42)
            }
            Button {
                requestZoom(canvasScale + 0.5)
            } label: {
                Image(systemName: "plus.magnifyingglass").frame(width: 30, height: 30)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func requestZoom(_ scale: CGFloat) {
        let clamped = min(4, max(1, scale))
        zoomRequest = (id: (zoomRequest?.id ?? 0) + 1, scale: clamped)
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
    /// Pen-free strip: the canvas lives entirely below it, so PencilKit's
    /// input machinery can never claim clicks on these controls. Styled like
    /// the original toolbar — round icon buttons, centered title.
    private var macTopBar: some View {
        ZStack {
            Text(sketch.title)
                .font(.headline)

            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
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

                Spacer()

                zoomControls

                if connectivity.peerOpenSketchID == sketch.id {
                    presenceBadge
                }

                textModeButton
                    .buttonStyle(.plain)
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(editingTexts ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.ultraThinMaterial),
                                in: Circle())

                paperMenu
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
