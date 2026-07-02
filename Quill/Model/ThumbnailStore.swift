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

    /// Keyed by pad AND target width — the grid (~176pt) and the mini rows
    /// (52pt) both show the same pad; a single per-pad slot would make the two
    /// sizes evict each other.
    private struct Key: Hashable {
        let id: UUID
        let width: CGFloat
    }

    private var cache: [Key: Entry] = [:]
    private let store: SketchStore
    private let renderQueue = DispatchQueue(label: "quill.thumbnails", qos: .userInitiated)
    /// Renders currently in progress (main-thread access only).
    private var inFlight = Set<Key>()

    init(store: SketchStore) {
        self.store = store
    }

    /// Cached thumbnail if fresh; otherwise schedules a background render and
    /// returns the stale image (or nil) meanwhile. Safe to call from a view
    /// body: all bookkeeping is deferred off the render pass.
    func thumbnail(for digest: SketchDigest, size: CGSize) -> UIImage? {
        let key = Key(id: digest.id, width: size.width)
        if let entry = cache[key], entry.stamp == digest.updatedAt {
            return entry.image
        }
        // Defer the kick-off: mutating even non-published state from inside a
        // SwiftUI body is a hazard; one hop later is invisible to the user.
        DispatchQueue.main.async { [weak self] in
            self?.renderIfNeeded(digest, key: key, size: size)
        }
        return cache[key]?.image
    }

    /// Pure decision: does a cached stamp cover this digest?
    static func isFresh(cachedStamp: Date?, digest: SketchDigest) -> Bool {
        cachedStamp == digest.updatedAt
    }

    /// Render a pad's ink AND text blocks at thumbnail scale. Static +
    /// synchronous for testability; instance callers run it off-main.
    static func render(drawingData: Data, texts: [TextBlock] = [], size: CGSize) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let drawing = (try? PKDrawing(data: drawingData)) ?? PKDrawing()

        // Content bounds: ink plus every text block's estimated frame.
        var content = drawing.bounds
        for block in texts where !block.text.isEmpty {
            let font = UIFont.systemFont(ofSize: block.size)
            let est = (block.text as NSString).boundingRect(
                with: CGSize(width: 360, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: [.font: font], context: nil)
            let frame = CGRect(x: block.x, y: block.y, width: est.width, height: est.height)
            content = content.isEmpty ? frame : content.union(frame)
        }
        let bounds = content.isEmpty
            ? CGRect(x: 0, y: 0, width: size.width * 3, height: size.height * 3)
            : content.insetBy(dx: -12, dy: -12)
        let scale = max(min(size.width / bounds.width, size.height / bounds.height), 0.05)

        let inkImage = drawing.image(from: bounds, scale: scale)
        let target = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in
            inkImage.draw(in: CGRect(origin: .zero, size: target))
            for block in texts where !block.text.isEmpty {
                let font = UIFont.systemFont(ofSize: block.size * scale)
                (block.text as NSString).draw(
                    in: CGRect(x: (block.x - bounds.minX) * scale,
                               y: (block.y - bounds.minY) * scale,
                               width: 360 * scale,
                               height: target.height),
                    withAttributes: [.font: font,
                                     .foregroundColor: UIColor(hex: 0x16161A)])
            }
        }
    }

    private func renderIfNeeded(_ digest: SketchDigest, key: Key, size: CGSize) {
        if let entry = cache[key], entry.stamp == digest.updatedAt { return } // raced a fresh render
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        let data = store.loadDrawing(digest.id)
        let texts = store.loadTexts(digest.id)
        let stamp = digest.updatedAt
        renderQueue.async { [weak self] in
            let image = Self.render(drawingData: data, texts: texts, size: size)
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(key)
                if let image {
                    self.cache[key] = Entry(stamp: stamp, image: image)
                    self.generation += 1
                }
            }
        }
    }
}
