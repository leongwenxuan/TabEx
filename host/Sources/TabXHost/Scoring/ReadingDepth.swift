import Foundation

/// Scores a tab based on how deeply the user has engaged with its content:
/// time spent, scroll depth, and whether they selected any text.
///
/// Formula: min(1.0, timeScore * 0.5 + scrollScore * 0.3 + selectionBonus)
public struct ReadingDepthScorer: Sendable {
    public init() {}

    /// Returns a score in [0.0, 1.0].
    ///
    /// - Parameters:
    ///   - timeSpentSeconds: Total time spent on the page.
    ///   - scrollDepth: Fraction of page scrolled, 0.0 (top) … 1.0 (bottom).
    ///   - hasSelection: Whether the user selected text on the page.
    public func score(timeSpentSeconds: Double, scrollDepth: Double, hasSelection: Bool) -> Double {
        // Sigmoid-ish: ~0.7 at 120 s, ~1.0 at 300 s.
        let timeScore = 1.0 - exp(-timeSpentSeconds / 120.0)
        let scrollScore = max(0.0, min(1.0, scrollDepth))
        let selectionBonus: Double = hasSelection ? 0.2 : 0.0
        return min(1.0, timeScore * 0.5 + scrollScore * 0.3 + selectionBonus)
    }
}
