import PencilKit

/// Finger interaction with ink: hit-testing and whole-stroke edits. PencilKit
/// has no public selection API, so Quill selects strokes itself — these pure
/// helpers keep that logic testable; `CanvasView` applies the results.
enum StrokeEdit {

    /// Indices of strokes whose path passes within `radius` of `point`
    /// (drawing coordinates).
    static func strokes(in drawing: PKDrawing, near point: CGPoint,
                        radius: CGFloat = 14) -> IndexSet {
        var hits = IndexSet()
        for (index, stroke) in drawing.strokes.enumerated() {
            guard stroke.renderBounds.insetBy(dx: -radius, dy: -radius)
                .contains(point) else { continue }
            let squared = radius * radius
            for slice in stroke.path.interpolatedPoints(by: .distance(6)) {
                let p = slice.location.applying(stroke.transform)
                let dx = p.x - point.x, dy = p.y - point.y
                if dx * dx + dy * dy <= squared {
                    hits.insert(index)
                    break
                }
            }
        }
        return hits
    }

    /// The on-canvas box around a set of strokes (drawing coordinates).
    static func bounds(of indices: IndexSet, in drawing: PKDrawing) -> CGRect {
        indices.compactMap { index -> CGRect? in
            guard drawing.strokes.indices.contains(index) else { return nil }
            return drawing.strokes[index].renderBounds
        }
        .reduce(CGRect.null) { $0.union($1) }
    }

    /// Move the selected strokes by (dx, dy).
    static func translate(_ drawing: PKDrawing, indices: IndexSet,
                          dx: CGFloat, dy: CGFloat) -> PKDrawing {
        var strokes = drawing.strokes
        for index in indices where strokes.indices.contains(index) {
            strokes[index].transform = strokes[index].transform
                .concatenating(CGAffineTransform(translationX: dx, y: dy))
        }
        return PKDrawing(strokes: strokes)
    }

    /// Remove the selected strokes.
    static func delete(_ drawing: PKDrawing, indices: IndexSet) -> PKDrawing {
        PKDrawing(strokes: drawing.strokes.enumerated()
            .filter { !indices.contains($0.offset) }
            .map(\.element))
    }

    /// Append offset copies of the selected strokes (appended at the end, so
    /// the copies ride the cheap append-delta sync path).
    static func duplicate(_ drawing: PKDrawing, indices: IndexSet,
                          offset: CGFloat = 16) -> PKDrawing {
        var strokes = drawing.strokes
        for index in indices where drawing.strokes.indices.contains(index) {
            var copy = drawing.strokes[index]
            copy.transform = copy.transform
                .concatenating(CGAffineTransform(translationX: offset, y: offset))
            strokes.append(copy)
        }
        return PKDrawing(strokes: strokes)
    }
}
