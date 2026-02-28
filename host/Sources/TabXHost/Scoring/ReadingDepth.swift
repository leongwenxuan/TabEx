import Foundation

/// Computes a reading-depth score from time spent, scroll depth, and text selections.
///
/// Component weights:
///   • Time spent  – 50%  (sigmoid curve; ~0.5 at 60 s, ~0.86 at 120 s, ~1.0 at 300 s)
///   • Scroll depth – 30%  (linear 0–1)
///   • Selection bonus – 20%  (binary: user selected text → +0.2)
public struct ReadingDepthScorer: Sendable {
    public init() {}

    /// Returns a score in [0.0, 1.0].
    public func score(
        timeSpentSeconds: Double,
        scrollDepth: Double,
        hasSelection: Bool
    ) -> Double {
        let timeScore      = 1.0 - exp(-timeSpentSeconds / 120.0)
        let scrollClamped  = max(0.0, min(1.0, scrollDepth))
        let selectionBonus = hasSelection ? 0.2 : 0.0
        return min(1.0, timeScore * 0.5 + scrollClamped * 0.3 + selectionBonus)
    }
}
