import Foundation

/// A per-device edit counter for one sketch. Missing key == 0.
///
/// Comparing two vectors tells us their causal relationship without a clock:
/// - one *dominates* the other  → it's strictly newer (fast-forward, no conflict)
/// - they're *equal*            → same state
/// - neither dominates          → *concurrent* → a real conflict (both edited
///   independently since they last agreed).
typealias VersionVector = [String: Int]

enum VV {

    static func merge(_ a: VersionVector, _ b: VersionVector) -> VersionVector {
        var result = a
        for (key, value) in b {
            result[key] = max(result[key] ?? 0, value)
        }
        return result
    }

    static func bumped(_ v: VersionVector, _ device: String) -> VersionVector {
        var result = v
        result[device] = (result[device] ?? 0) + 1
        return result
    }

    /// True when `a` >= `b` on every component (so `a` is same-or-newer).
    static func dominatesOrEqual(_ a: VersionVector, _ b: VersionVector) -> Bool {
        for (key, value) in b where (a[key] ?? 0) < value {
            return false
        }
        return true
    }

    static func equal(_ a: VersionVector, _ b: VersionVector) -> Bool {
        dominatesOrEqual(a, b) && dominatesOrEqual(b, a)
    }

    /// True when `a` is strictly newer than `b` (dominates and isn't equal).
    static func strictlyDominates(_ a: VersionVector, _ b: VersionVector) -> Bool {
        dominatesOrEqual(a, b) && !dominatesOrEqual(b, a)
    }

    /// True when neither dominates — both changed independently.
    static func concurrent(_ a: VersionVector, _ b: VersionVector) -> Bool {
        !dominatesOrEqual(a, b) && !dominatesOrEqual(b, a)
    }
}
