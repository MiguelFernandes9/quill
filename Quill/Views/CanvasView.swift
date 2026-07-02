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
/// Zoom is locked to 1 and scrolling disabled, so view coordinates equal the
/// shared drawing coordinate space across devices.
struct CanvasView: UIViewRepresentable {

    let initialDrawing: Data
    let commands: AnyPublisher<CanvasCommand, Never>
    /// Externally-driven tool (Mac's custom strip). nil → Apple's PKToolPicker
    /// palette drives the tool (iPad).
    var tool: PKTool?
    /// Programmatic zoom request (id increments per request; scale target).
    var zoomRequest: (id: Int, scale: CGFloat)?
    var onDrawingChanged: (Data) -> Void
    var onStrokeDelta: (Data) -> Void
    var onCursor: (CGPoint, Bool) -> Void
    /// Reports the canvas's live zoom + pan so sibling overlays (paper, text,
    /// remote cursor) can transform in lockstep.
    var onTransform: (CGFloat, CGPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput           // finger + pencil + Mac pointer
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
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if let tool {
            canvas.tool = tool
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

        /// Number of strokes already broadcast/known; strokes beyond this count
        /// are new local additions to send.
        var lastSyncedCount = 0

        /// Last applied programmatic zoom request (dedupes updateUIView calls).
        var lastZoomRequestID = 0

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
            let observer = TouchObserver()
            observer.cancelsTouchesInView = false
            observer.delegate = self
            observer.onTouch = { [weak self] point, down in
                self?.reportCursor(point, down: down)
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

            // Never lose ink to a backgrounded app.
            NotificationCenter.default
                .publisher(for: UIApplication.didEnterBackgroundNotification)
                .sink { [weak self] _ in self?.flushSave() }
                .store(in: &cancellables)

            #if !targetEnvironment(macCatalyst)
            // iPad: Apple's tool palette. Attached AFTER the push animation
            // finishes (~0.35s) so the transition isn't stalled. The Mac uses
            // its own MacToolStrip instead — Catalyst's PKToolPicker palette is
            // unreliable and its first-responder machinery fed the input bug.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak canvas] in
                guard let canvas, canvas.window != nil else { return } // already closed
                let picker = Self.sharedToolPicker
                picker.setVisible(true, forFirstResponder: canvas)
                picker.addObserver(canvas)
                canvas.becomeFirstResponder()
            }
            #endif
        }

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
                flushSave()

            case .setPaper, .setTexts:
                break // paper + text blocks render outside the canvas; the detail view handles them
            }
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
        }

        // MARK: Local drawing changes

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingRemote else { return }

            let strokes = canvasView.drawing.strokes
            // Broadcast new strokes FIRST so the network isn't blocked by disk.
            if strokes.count > lastSyncedCount {
                let newStrokes = Array(strokes[lastSyncedCount...])
                parent.onStrokeDelta(PKDrawing(strokes: newStrokes).dataRepresentation())
            }
            // On undo/erase the count drops; rebaseline (live erase isn't
            // propagated — the full drawing reconciles on close).
            lastSyncedCount = strokes.count

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
        /// PencilKit's content is the canvas's first subview.
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            scrollView.subviews.first
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
