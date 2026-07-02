import Foundation

/// How a local drawing change reaches the live peer. Appends are cheap deltas;
/// anything else (erase, undo) needs the whole drawing, because PencilKit
/// erasers don't just remove strokes — the bitmap eraser can shorten or SPLIT
/// them, so the stroke count may rise while content shrank, and a count-based
/// delta would ship garbage fragments.
enum StrokeSyncAction: Equatable {
    /// Send strokes `[from...]` as an append delta.
    case appendDelta(from: Int)
    /// Send the full drawing (replaces the peer's copy).
    case resync
    /// Nothing new to send.
    case none
}

enum StrokeSync {
    /// Decide from what's observable at change time: the active tool kind,
    /// the new stroke count, and the count already synced.
    static func action(erasing: Bool, count: Int, lastSynced: Int) -> StrokeSyncAction {
        if erasing { return .resync }           // erase mutates arbitrarily
        if count > lastSynced { return .appendDelta(from: lastSynced) }
        if count < lastSynced { return .resync } // undo / programmatic removal
        return .none
    }
}
