import SwiftUI
import PencilKit
import Combine

/// SwiftUI bridge around `PKCanvasView` + Apple's `PKToolPicker`.
///
/// - Transparent: the paper pattern (`PaperBackgroundView`) shows through.
/// - Broadcasts just-added strokes live; persists the drawing debounced (2s),
///   flushing on close, on app-background, and when a peer asks (`.flush`).
/// - Applies peer commands: append strokes, or reload the whole drawing after
///   an open-refresh — both without echoing anything back.
///
/// The page grows downward as content approaches the bottom (`PageGrowth`),
/// so notes scroll on forever; content coordinates are shared across devices
/// unchanged (growth never moves existing ink).
struct CanvasView: UIViewRepresentable {

    let initialDrawing: Data
    let commands: AnyPublisher<CanvasCommand, Never>
    /// Externally-driven tool (Mac's custom strip). nil → Apple's PKToolPicker
    /// palette drives the tool (iPad).
    var tool: PKTool?
    /// Programmatic zoom request (id increments per request; scale target).
    var zoomRequest: (id: Int, scale: CGFloat)?
    /// Farthest content edges the page must contain besides ink (text
    /// blocks, content coordinates) — the page grows past them like it does
    /// for ink.
    var contentBottomHint: CGFloat = 0
    var contentRightHint: CGFloat = 0
    var onDrawingChanged: (Data) -> Void
    var onStrokeDelta: (Data) -> Void
    /// The whole drawing, after a change an append delta can't carry (erase /
    /// undo) — the peer replaces its copy.
    var onDrawingResync: (Data) -> Void
    var onCursor: (CGPoint, Bool) -> Void
    /// Reports the canvas's live zoom + pan so sibling overlays (paper, text,
    /// remote cursor) can transform in lockstep.
    var onTransform: (CGFloat, CGPoint) -> Void
    /// iPad: a finger long-press on the canvas, in content coordinates —
    /// the entry point into text editing (no recognizer on Mac).
    var onLongPress: ((CGPoint) -> Void)?
    /// iPad: which text block (if any) covers a content point — lets the
    /// long-press become a grab on existing blocks.
    var blockAt: ((CGPoint) -> UUID?)?
    /// iPad: live finger drag of a grabbed block. Incremental content-coord
    /// delta per event; `finished` fires once on release.
    var onBlockMove: ((UUID, CGSize, Bool) -> Void)?
    /// iPad: a finger tapped ink — these strokes (and their box, content
    /// coordinates) become the selection.
    var onInkSelection: ((IndexSet, CGRect) -> Void)?
    /// iPad: the lifted strokes' image for a drag in flight (see
    /// `.beginStrokeDrag`), with their box.
    var onDragImage: ((UIImage, CGRect) -> Void)?
    /// iPad: is a text block currently active? While it is, the canvas stays
    /// scrollable, so empty taps must deselect (and show no menu).
    var textActive: (() -> Bool)?
    /// iPad: a tap on truly empty paper while a block was active.
    var onEmptyTap: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = GrowingCanvasView()
        #if targetEnvironment(macCatalyst)
        canvas.drawingPolicy = .anyInput           // Mac pointer draws
        #else
        // iPad: only the Pencil draws; fingers scroll and pinch-zoom.
        canvas.drawingPolicy = .pencilOnly
        #endif
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 4                // pinch (or Mac buttons) to zoom
        canvas.isScrollEnabled = true              // pan while zoomed in
        canvas.alwaysBounceVertical = false
        canvas.alwaysBounceHorizontal = false
        // Never auto-inset: on Catalyst the safe-area inset adjustment can
        // feedback-loop with a zoomed scroll view (offset oscillates, delegate
        // storms, main thread livelocks — the frozen bar after a zoom press).
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.clipsToBounds = true
        canvas.backgroundColor = .clear            // paper pattern shows through
        canvas.isOpaque = false
        canvas.delegate = context.coordinator

        if let drawing = try? PKDrawing(data: initialDrawing) {
            canvas.drawing = drawing
            context.coordinator.lastSyncedCount = drawing.strokes.count
        }

        context.coordinator.attach(to: canvas)
        context.coordinator.refreshInkBottom(canvas)

        #if !targetEnvironment(macCatalyst)
        canvas.onInsertTextBlock = onLongPress
        let blockAt = blockAt
        let textActive = textActive
        canvas.menuSuppressed = { [weak canvas] point in
            if textActive?() == true { return true } // deselecting tap, not a menu
            if blockAt?(point) != nil { return true }
            guard let canvas else { return false }
            return !StrokeEdit.strokes(in: canvas.drawing, near: point).isEmpty
        }
        #endif

        // Re-derive the page size on every layout pass: first appearance
        // (bounds are zero in here), rotation, window resize, and every
        // zoom/scroll frame (the target contentSize tracks zoomScale).
        canvas.onLayout = { [weak canvas, weak coordinator = context.coordinator] in
            guard let canvas, let coordinator else { return }
            coordinator.updateContentSize(canvas)
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if let tool {
            canvas.tool = tool
        }
        if contentBottomHint != context.coordinator.bottomHint
            || contentRightHint != context.coordinator.rightHint {
            context.coordinator.bottomHint = contentBottomHint
            context.coordinator.rightHint = contentRightHint
            // Defer: contentSize growth can move scroll internals; never
            // mutate them inside a SwiftUI view update.
            let coordinator = context.coordinator
            DispatchQueue.main.async { [weak canvas] in
                guard let canvas else { return }
                coordinator.updateContentSize(canvas)
            }
        }
        if let request = zoomRequest, request.id != context.coordinator.lastZoomRequestID {
            context.coordinator.lastZoomRequestID = request.id
            // Defer off the view update (setZoomScale fires the scroll
            // delegate synchronously). Unanimated: the delegate reports
            // immediately, so ink, paper, and text overlays change together —
            // animated zoom left overlays lagging behind the ink. NOTE: the
            // coordinator is captured directly; SwiftUI's `context` must not
            // escape updateUIView.
            let coordinator = context.coordinator
            DispatchQueue.main.async { [weak canvas] in
                guard let canvas else { return }
                canvas.setZoomScale(request.scale, animated: false)
                coordinator.parentTransform(canvas)
            }
        }
    }

    /// Flush the last (debounced) save when leaving the canvas.
    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        coordinator.detachToolPicker(from: uiView)
        coordinator.restoreDraggedStrokes()
        coordinator.flushSave()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        /// One picker for the app's lifetime. Creating a fresh `PKToolPicker`
        /// per pad spins up an entire palette window on the main thread — on
        /// Catalyst that's seconds of jank that also eats back-button clicks.
        private static let sharedToolPicker = PKToolPicker()

        private let parent: CanvasView
        private weak var canvas: PKCanvasView?
        private var cancellables = Set<AnyCancellable>()
        private var lastCursorSend: CFTimeInterval = 0

        /// Coalesces frequent drawing-change callbacks into one disk save.
        private let saveSubject = PassthroughSubject<Void, Never>()
        private var dirty = false

        /// Coalesces erase-driven full-drawing sends: a bitmap-eraser scrub
        /// fires per-frame changes, and each resync ships the whole drawing.
        private let resyncSubject = PassthroughSubject<Void, Never>()

        /// Number of strokes already broadcast/known; strokes beyond this count
        /// are new local additions to send.
        var lastSyncedCount = 0

        /// Last applied programmatic zoom request (dedupes updateUIView calls).
        var lastZoomRequestID = 0

        /// Page size in content coordinates (zoom 1). Grows via `PageGrowth`
        /// as ink or text nears the bottom/right edge; never shrinks
        /// mid-session. Width matters across devices: the Mac's viewport is
        /// wider, so its ink can land beyond a narrower iPad's page.
        private var pageHeight: CGFloat = 0
        private var pageWidth: CGFloat = 0
        /// Cached farthest ink edges (recomputing drawing.bounds per layout
        /// frame would be O(strokes) during every scroll/zoom tick).
        private var inkBottom: CGFloat = 0
        private var inkRight: CGFloat = 0
        /// Farthest text-block edges, pushed in from updateUIView.
        var bottomHint: CGFloat = 0
        var rightHint: CGFloat = 0

        /// True while applying peer content, so the resulting change callback
        /// never rebroadcasts it (which would ping-pong forever).
        private var isApplyingRemote = false

        init(_ parent: CanvasView) {
            self.parent = parent
        }

        func attach(to canvas: PKCanvasView) {
            self.canvas = canvas

            // Cursor while hovering (Mac pointer / pencil hover on capable iPads).
            let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
            canvas.addGestureRecognizer(hover)

            // Cursor while drawing: passive observer, never steals a stroke.
            // Doubles as the edit menu's anchor tracker on iPad.
            let observer = TouchObserver()
            observer.cancelsTouchesInView = false
            observer.delegate = self
            observer.onTouch = { [weak self, weak canvas] point, down in
                self?.reportCursor(point, down: down)
                #if !targetEnvironment(macCatalyst)
                if down { (canvas as? GrowingCanvasView)?.lastTouchPoint = point }
                #endif
            }
            canvas.addGestureRecognizer(observer)

            parent.commands
                .sink { [weak self] command in self?.handle(command) }
                .store(in: &cancellables)

            // Persist at most every ~2s while drawing, off the hot path; flush
            // covers close/background/peer-request.
            saveSubject
                .debounce(for: .seconds(2.0), scheduler: DispatchQueue.main)
                .sink { [weak self] in self?.flushSave() }
                .store(in: &cancellables)

            // Ship the post-erase drawing once the scrub settles.
            resyncSubject
                .debounce(for: .seconds(0.35), scheduler: DispatchQueue.main)
                .sink { [weak self] in
                    guard let self, let canvas = self.canvas else { return }
                    self.parent.onDrawingResync(canvas.drawing.dataRepresentation())
                }
                .store(in: &cancellables)

            // Never lose ink to a backgrounded app.
            NotificationCenter.default
                .publisher(for: UIApplication.didEnterBackgroundNotification)
                .sink { [weak self] _ in
                    self?.restoreDraggedStrokes()
                    self?.flushSave()
                }
                .store(in: &cancellables)

            #if !targetEnvironment(macCatalyst)
            // iPad: Apple's tool palette. Attached AFTER the push animation
            // finishes so the transition isn't stalled — with retries, because
            // a single-shot attach silently bailed whenever the canvas wasn't
            // in a window yet (palette never appeared). The Mac uses its own
            // MacToolStrip instead.
            attachToolPickerWhenReady(canvas)

            // Put the A| action into PencilKit's tap edit menu. Retried like
            // the tool picker — the menu machinery attaches lazily.
            if let growing = canvas as? GrowingCanvasView {
                EditMenuAugment.activeCanvas = growing
                augmentEditMenuWhenReady(growing)
            }
            #endif

            // Press-and-hold on a TEXT BLOCK grabs it (drag to move, release
            // in place to edit). iPad: finger-only, and gated (shouldReceive)
            // to touches over a block so presses on paper or ink fall through
            // to PencilKit's edit menu, which gains "Insert Text Block" via
            // buildMenu. Mac: click-and-hold, ungated — holding empty paper
            // creates a block right there (no system menu exists to join).
            let longPress = UILongPressGestureRecognizer(target: self,
                                                         action: #selector(handleLongPress(_:)))
            longPress.minimumPressDuration = 0.5
            #if !targetEnvironment(macCatalyst)
            longPress.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            #endif
            longPress.delegate = self
            canvas.addGestureRecognizer(longPress)
            blockPressRecognizer = longPress

            #if !targetEnvironment(macCatalyst)
            // A plain finger TAP on a block opens it for interaction (drag,
            // resize, edit) — no menu, no hold. Gated (shouldReceive) to
            // touches over a block, so taps on paper/ink still summon
            // PencilKit's edit menu. Not on Mac: a mouse click is a pen dot.
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleBlockTap(_:)))
            tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            tap.delegate = self
            canvas.addGestureRecognizer(tap)
            blockTapRecognizer = tap
            #endif
        }

        #if !targetEnvironment(macCatalyst)
        private func attachToolPickerWhenReady(_ canvas: PKCanvasView, attempt: Int = 0) {
            guard attempt < 20 else { return } // ~5s of retries, then give up
            DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.4 : 0.25)) {
                [weak self, weak canvas] in
                guard let self, let canvas else { return }
                guard canvas.window != nil else {
                    self.attachToolPickerWhenReady(canvas, attempt: attempt + 1)
                    return
                }
                let picker = Self.sharedToolPicker
                picker.setVisible(true, forFirstResponder: canvas)
                picker.addObserver(canvas)
                canvas.becomeFirstResponder()
            }
        }
        #endif

        #if !targetEnvironment(macCatalyst)
        private func augmentEditMenuWhenReady(_ canvas: GrowingCanvasView, attempt: Int = 0) {
            guard attempt < 12 else { return } // ~6s, then live with the stock menu
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak canvas] in
                guard let canvas else { return }
                if !EditMenuAugment.install(on: canvas) {
                    self.augmentEditMenuWhenReady(canvas, attempt: attempt + 1)
                }
            }
        }
        #endif

        func detachToolPicker(from canvas: PKCanvasView) {
            #if !targetEnvironment(macCatalyst)
            let picker = Self.sharedToolPicker
            picker.setVisible(false, forFirstResponder: canvas)
            picker.removeObserver(canvas)
            canvas.resignFirstResponder()
            #endif
        }

        // MARK: Commands from the peer

        private func handle(_ command: CanvasCommand) {
            guard let canvas else { return }
            switch command {
            case let .appendStrokes(delta):
                // Coalesce: setting `canvas.drawing` re-rasterizes the WHOLE
                // canvas, so applying per-message during a peer's stroke burst
                // (handwriting!) starves the main thread — the back button
                // stops responding. Buffer and apply at most ~5×/sec.
                pendingDeltas.append(delta)
                scheduleDeltaApply()

            case let .reloadDrawing(data):
                guard let drawing = try? PKDrawing(data: data) else { return }
                pendingDeltas.removeAll() // superseded by the full copy
                setRemote(drawing, on: canvas)
                dirty = false // store already has exactly this state

            case .flush:
                restoreDraggedStrokes()
                flushSave()

            case let .transformStrokes(indices, dx, dy):
                applyLocalEdit { StrokeEdit.translate($0, indices: indices, dx: dx, dy: dy) }

            case let .deleteStrokes(indices):
                applyLocalEdit { StrokeEdit.delete($0, indices: indices) }

            case let .duplicateStrokes(indices):
                applyLocalEdit { StrokeEdit.duplicate($0, indices: indices) }

            case let .beginStrokeDrag(indices):
                beginStrokeDrag(indices)

            case let .endStrokeDrag(dx, dy):
                endStrokeDrag(dx: dx, dy: dy)

            case .setPaper, .setTexts:
                break // paper + text blocks render outside the canvas; the detail view handles them
            }
        }

        /// A whole-drawing edit from the selection overlay (move / delete /
        /// duplicate). Applied without the auto-broadcast (none of these are
        /// append deltas), then persisted and — unless `sync` is off (a drag
        /// in flight ships once, on drop) — sent as a full resync.
        private func applyLocalEdit(sync: Bool = true, _ edit: (PKDrawing) -> PKDrawing) {
            guard let canvas else { return }
            applyPendingDeltas() // fold in buffered peer strokes first
            let edited = edit(canvas.drawing)
            isApplyingRemote = true
            canvas.drawing = edited
            isApplyingRemote = false
            lastSyncedCount = edited.strokes.count
            refreshInkBottom(canvas)
            dirty = true
            saveSubject.send(())
            if sync { resyncSubject.send(()) }
        }

        // MARK: Ink drag (lift → image → drop)

        /// Strokes lifted out of the drawing while the finger drags their
        /// image. Restored by `flushSave` if anything interrupts the drag.
        private var draggedStrokes: [PKStroke]?

        private func beginStrokeDrag(_ indices: IndexSet) {
            guard draggedStrokes == nil, let canvas else { return }
            let strokes = indices.compactMap {
                canvas.drawing.strokes.indices.contains($0) ? canvas.drawing.strokes[$0] : nil
            }
            let bounds = StrokeEdit.bounds(of: indices, in: canvas.drawing)
            guard !strokes.isEmpty, !bounds.isNull, bounds.width > 0, bounds.height > 0
            else { return }
            draggedStrokes = strokes
            let image = PKDrawing(strokes: strokes)
                .image(from: bounds, scale: canvas.traitCollection.displayScale)
            // No resync while lifted: the peer gets one clean update on drop.
            applyLocalEdit(sync: false) { StrokeEdit.delete($0, indices: indices) }
            parent.onDragImage?(image, bounds)
        }

        private func endStrokeDrag(dx: CGFloat, dy: CGFloat) {
            guard let strokes = draggedStrokes, let canvas else { return }
            draggedStrokes = nil
            let translated = strokes.map { stroke -> PKStroke in
                var copy = stroke
                copy.transform = copy.transform
                    .concatenating(CGAffineTransform(translationX: dx, y: dy))
                return copy
            }
            applyLocalEdit { PKDrawing(strokes: $0.strokes + translated) }
            // Re-select the dropped strokes (they now sit at the end).
            let count = canvas.drawing.strokes.count
            let indices = IndexSet(integersIn: (count - translated.count)..<count)
            parent.onInkSelection?(indices, StrokeEdit.bounds(of: indices, in: canvas.drawing))
        }

        /// Teardown points (close, background, peer flush request) must put
        /// the lifted strokes back where they were — NOT the 2s autosave,
        /// which can fire mid-drag and would break the drop.
        func restoreDraggedStrokes() {
            guard let strokes = draggedStrokes else { return }
            draggedStrokes = nil
            applyLocalEdit { PKDrawing(strokes: $0.strokes + strokes) }
        }

        /// Peer stroke deltas waiting to be applied in one batch.
        private var pendingDeltas: [Data] = []
        private var deltaApplyScheduled = false

        private func scheduleDeltaApply() {
            guard !deltaApplyScheduled else { return }
            deltaApplyScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self else { return }
                self.deltaApplyScheduled = false
                self.applyPendingDeltas()
            }
        }

        private func applyPendingDeltas() {
            guard let canvas, !pendingDeltas.isEmpty else { return }
            let strokes = pendingDeltas
                .compactMap { try? PKDrawing(data: $0) }
                .flatMap(\.strokes)
            pendingDeltas.removeAll()
            guard !strokes.isEmpty else { return }
            setRemote(PKDrawing(strokes: canvas.drawing.strokes + strokes), on: canvas)
            dirty = true
            saveSubject.send(())
        }

        private func setRemote(_ drawing: PKDrawing, on canvas: PKCanvasView) {
            // Baseline BEFORE assigning (the assignment fires the change
            // callback synchronously) so peer content is never rebroadcast.
            lastSyncedCount = drawing.strokes.count
            isApplyingRemote = true
            canvas.drawing = drawing
            isApplyingRemote = false
            refreshInkBottom(canvas) // peer ink can extend the page too
        }

        // MARK: Infinite page

        /// Recompute the cached ink edges from the drawing, then resize.
        func refreshInkBottom(_ canvas: PKCanvasView) {
            let bounds = canvas.drawing.bounds
            inkBottom = bounds.isNull ? 0 : bounds.maxY
            inkRight = bounds.isNull ? 0 : bounds.maxX
            updateContentSize(canvas)
        }

        /// Apply the page-growth rule as the scroll view's content size
        /// (scaled by the current zoom). Called from every layout pass, so it
        /// must converge: it only writes when the target actually changes.
        func updateContentSize(_ canvas: PKCanvasView) {
            let viewport = canvas.bounds.size
            guard viewport.width > 0, viewport.height > 0 else { return }
            pageHeight = PageGrowth.extent(current: pageHeight,
                                           viewport: viewport.height,
                                           contentEdge: max(inkBottom, bottomHint))
            pageWidth = PageGrowth.extent(current: pageWidth,
                                          viewport: viewport.width,
                                          contentEdge: max(inkRight, rightHint))
            let scale = canvas.zoomScale
            let target = CGSize(width: pageWidth * scale,
                                height: pageHeight * scale)
            if abs(canvas.contentSize.width - target.width) > 0.5 ||
                abs(canvas.contentSize.height - target.height) > 0.5 {
                canvas.contentSize = target
            }
        }

        // MARK: Local drawing changes

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingRemote else { return }

            let strokes = canvasView.drawing.strokes
            // Broadcast FIRST so the network isn't blocked by disk. New pen
            // strokes go as cheap append deltas; erases and undos replace the
            // peer's whole drawing (StrokeSync explains why count alone can't
            // tell — the bitmap eraser splits strokes).
            switch StrokeSync.action(erasing: canvasView.tool is PKEraserTool,
                                     count: strokes.count,
                                     lastSynced: lastSyncedCount) {
            case let .appendDelta(from):
                let newStrokes = Array(strokes[from...])
                parent.onStrokeDelta(PKDrawing(strokes: newStrokes).dataRepresentation())
            case .resync:
                resyncSubject.send(())
            case .none:
                break
            }
            lastSyncedCount = strokes.count

            refreshInkBottom(canvasView) // writing near the bottom grows the page

            dirty = true
            saveSubject.send(())
        }

        func flushSave() {
            applyPendingDeltas() // fold in any buffered peer strokes first
            guard let canvas, dirty else { return }
            dirty = false
            parent.onDrawingChanged(canvas.drawing.dataRepresentation())
        }

        // MARK: Zoom / pan (UIScrollViewDelegate via PKCanvasViewDelegate)

        /// Required for UIScrollView zooming to function at all — without a
        /// zooming view from the delegate, pinch and setZoomScale are inert.
        /// PencilKit's content view must be picked carefully: `subviews.first`
        /// can be a scroll INDICATOR on some OS versions, and zooming that
        /// scales the indicator while the ink never moves.
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            scrollView.subviews
                .filter { !NSStringFromClass(type(of: $0)).lowercased().contains("indicator") }
                .max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            reportTransform(scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            reportTransform(scrollView)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            reportTransform(scrollView) // final value after a pinch settles
        }

        private var lastReportedTransform: (CGFloat, CGPoint)?

        private func reportTransform(_ scrollView: UIScrollView) {
            // Delegate callbacks can land inside a SwiftUI view update (e.g.
            // when a layout pass adjusts contentOffset) — hop off it before
            // touching the parent's @State. Dedupe so delegate chatter with
            // unchanged values never churns renders.
            let scale = scrollView.zoomScale
            let offset = scrollView.contentOffset
            if let last = lastReportedTransform, last.0 == scale, last.1 == offset { return }
            lastReportedTransform = (scale, offset)
            DispatchQueue.main.async { [weak self] in
                self?.parent.onTransform(scale, offset)
            }
        }

        /// Exposed for post-animation reporting from `updateUIView`.
        func parentTransform(_ scrollView: UIScrollView) {
            reportTransform(scrollView)
        }

        /// The block-grab long-press; identified in the delegate so ONLY it
        /// gets gated (iPad) to touches over a text block.
        weak var blockPressRecognizer: UILongPressGestureRecognizer?

        #if !targetEnvironment(macCatalyst)
        /// The tap-a-block-to-edit recognizer, gated the same way.
        weak var blockTapRecognizer: UITapGestureRecognizer?

        @objc private func handleBlockTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let view = g.view else { return }
            let raw = g.location(in: view)
            let scale = canvas?.zoomScale ?? 1
            let point = CGPoint(x: raw.x / scale, y: raw.y / scale)
            if parent.blockAt?(point) != nil {
                parent.onLongPress?(point) // opens the block: focus + controls
                return
            }
            // Ink: select the strokes under the finger (PencilKit has no
            // public selection, so Quill provides its own).
            guard let canvas else { return }
            let hits = StrokeEdit.strokes(in: canvas.drawing, near: point)
            if !hits.isEmpty {
                parent.onInkSelection?(hits, StrokeEdit.bounds(of: hits, in: canvas.drawing))
                return
            }
            // Empty paper while a block is active: deselect it.
            if parent.textActive?() == true { parent.onEmptyTap?() }
        }
        #endif

        /// Press-and-drag state: the block grabbed at `.began`, the anchor to
        /// tell a grab-and-drag from a press-in-place, and the last point for
        /// incremental move deltas.
        private var pressedBlockID: UUID?
        private var pressAnchor: CGPoint = .zero
        private var lastPressPoint: CGPoint = .zero
        private var pressMoved = false

        /// Hold a block and drag → move it; hold and release in place →
        /// edit it. On iPad, touches not over a block never reach this
        /// (shouldReceive) so PencilKit keeps its native press behavior; on
        /// the Mac, holding empty paper creates a block at the pointer.
        @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
            guard let view = g.view else { return }
            let raw = g.location(in: view)
            let scale = canvas?.zoomScale ?? 1
            let point = CGPoint(x: raw.x / scale, y: raw.y / scale)

            switch g.state {
            case .began:
                pressAnchor = point
                lastPressPoint = point
                pressMoved = false
                pressedBlockID = parent.blockAt?(point)
                if pressedBlockID != nil {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                #if targetEnvironment(macCatalyst)
                if pressedBlockID == nil {
                    parent.onLongPress?(point) // click-hold empty → new block
                }
                #endif

            case .changed:
                guard let id = pressedBlockID else { return }
                if hypot(point.x - pressAnchor.x, point.y - pressAnchor.y) > 4 {
                    pressMoved = true
                }
                let delta = CGSize(width: point.x - lastPressPoint.x,
                                   height: point.y - lastPressPoint.y)
                lastPressPoint = point
                if pressMoved { parent.onBlockMove?(id, delta, false) }

            case .ended, .cancelled, .failed:
                guard let id = pressedBlockID else { return }
                pressedBlockID = nil
                if pressMoved {
                    parent.onBlockMove?(id, .zero, true) // drop: persist + sync
                } else if g.state == .ended {
                    parent.onLongPress?(pressAnchor) // press in place → edit
                }

            default:
                break
            }
        }

        // MARK: Cursor

        @objc private func handleHover(_ g: UIHoverGestureRecognizer) {
            guard let view = g.view else { return }
            if g.state == .ended || g.state == .cancelled { return }
            reportCursor(g.location(in: view), down: false)
        }

        private func reportCursor(_ point: CGPoint, down: Bool) {
            let now = CACurrentMediaTime()
            guard now - lastCursorSend > 0.033 else { return } // ~30 Hz
            lastCursorSend = now
            // Convert from the (zoomed) bounds space to content coordinates so
            // peers place the cursor correctly regardless of either side's zoom.
            let scale = canvas?.zoomScale ?? 1
            parent.onCursor(CGPoint(x: point.x / scale, y: point.y / scale), down)
        }
    }
}

extension CanvasView.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    #if !targetEnvironment(macCatalyst)
    /// The block grab takes ONLY touches on a text block; the tap takes
    /// touches on a block OR on ink (stroke selection). Touches on empty
    /// paper always fall through, so PencilKit's own edit menu (Select All /
    /// Insert Space) keeps appearing there.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let view = g.view else { return true }
        let raw = touch.location(in: view)
        let scale = (view as? UIScrollView)?.zoomScale ?? 1
        let point = CGPoint(x: raw.x / scale, y: raw.y / scale)
        if g === blockPressRecognizer {
            return parent.blockAt?(point) != nil
        }
        if g === blockTapRecognizer {
            if parent.blockAt?(point) != nil { return true }
            guard let drawing = (view as? PKCanvasView)?.drawing else { return false }
            if !StrokeEdit.strokes(in: drawing, near: point).isEmpty { return true }
            // Empty paper: claim the tap only while a block is active — it
            // deselects instead of summoning PencilKit's menu.
            return parent.textActive?() == true
        }
        return true
    }
    #endif
}

/// `PKCanvasView` with a layout hook: `UIScrollViewDelegate` has no layout
/// callback, but the growing page must be re-derived on first layout (bounds
/// are zero during make), rotation, window resize, and every zoom frame.
///
/// On iPad it also injects **Insert Text Block** into the system edit menu
/// PencilKit shows on a finger press (next to Select All / Insert Space) —
/// PencilKit exposes no menu API, so the action rides the responder-chain
/// menu builder instead.
final class GrowingCanvasView: PKCanvasView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }

    #if !targetEnvironment(macCatalyst)
    /// Called with the menu's tap point in content coordinates. Reached from
    /// the A| action `EditMenuAugment` adds to PencilKit's tap edit menu
    /// (the menu-builder route was verified dead on device — PencilKit's
    /// edit menu bypasses UIMenuSystem).
    var onInsertTextBlock: ((CGPoint) -> Void)?
    /// True when the tapped content point sits on an object (text block or
    /// ink) — the system edit bar is suppressed there; objects get direct
    /// interaction instead.
    var menuSuppressed: ((CGPoint) -> Bool)?
    /// Last touch in view coordinates, tracked passively — the edit menu
    /// doesn't hand its anchor point to the augmented action.
    var lastTouchPoint: CGPoint = .zero
    #endif
}

/// A gesture recognizer that only *observes* touches — it stays in `.possible`
/// forever, so it never cancels the touches PencilKit needs to draw.
private final class TouchObserver: UIGestureRecognizer {
    var onTouch: ((CGPoint, Bool) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        report(touches, down: true)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        report(touches, down: true)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        report(touches, down: false)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        report(touches, down: false)
    }

    private func report(_ touches: Set<UITouch>, down: Bool) {
        guard let touch = touches.first, let view else { return }
        onTouch?(touch.location(in: view), down)
    }
}
