import UIKit
import PencilKit

/// Renders and caches pad thumbnails for the home grid.
///
/// Cache entries are keyed by the pad's `updatedAt` — any local save or
/// incoming sync bumps it, which naturally invalidates the thumbnail. Pure
/// rendering + caching; knows nothing about views.
final class ThumbnailStore: ObservableObject {

    /// Bumped whenever a new thumbnail lands so grids re-query.
    @Published private(set) var generation = 0

    private struct Entry {
        let stamp: Date
        let image: UIImage
    }

    private var cache: [UUID: Entry] = [:]
    private let store: SketchStore
    private let renderQueue = DispatchQueue(label: "quill.thumbnails", qos: .userInitiated)
    /// Pads currently being rendered (main-thread access only).
    private var inFlight = Set<UUID>()

    init(store: SketchStore) {
        self.store = store
    }

    /// Cached thumbnail if fresh; otherwise kicks off a background render and
    /// returns the stale image (or nil) meanwhile.
    func thumbnail(for digest: SketchDigest, size: CGSize) -> UIImage? {
        if let entry = cache[digest.id], entry.stamp == digest.updatedAt {
            return entry.image
        }
        renderIfNeeded(digest, size: size)
        return cache[digest.id]?.image
    }

    /// Pure decision: does a cached stamp cover this digest?
    static func isFresh(cachedStamp: Date?, digest: SketchDigest) -> Bool {
        cachedStamp == digest.updatedAt
    }

    /// Render a drawing over white at thumbnail scale. Static + synchronous
    /// for testability; instance callers run it off-main.
    static func render(drawingData: Data, size: CGSize) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let drawing = (try? PKDrawing(data: drawingData)) ?? PKDrawing()
        // Fit the used portion of the drawing (or a default viewport when
        // empty) into the thumbnail, preserving aspect.
        let bounds = drawing.bounds.isEmpty
            ? CGRect(x: 0, y: 0, width: size.width * 3, height: size.height * 3)
            : drawing.bounds.insetBy(dx: -12, dy: -12)
        let scale = min(size.width / bounds.width, size.height / bounds.height)
        let image = drawing.image(from: bounds, scale: max(scale, 0.05))
        return image
    }

    private func renderIfNeeded(_ digest: SketchDigest, size: CGSize) {
        guard !inFlight.contains(digest.id) else { return }
        inFlight.insert(digest.id)
        let data = store.loadDrawing(digest.id)
        let stamp = digest.updatedAt
        renderQueue.async { [weak self] in
            let image = Self.render(drawingData: data, size: size)
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(digest.id)
                if let image {
                    self.cache[digest.id] = Entry(stamp: stamp, image: image)
                    self.generation += 1
                }
            }
        }
    }
}
