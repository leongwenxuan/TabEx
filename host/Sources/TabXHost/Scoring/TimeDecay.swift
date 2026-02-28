import Foundation

/// Computes a recency score using exponential decay from the tab's last visit time.
///
/// Score = exp(−age / halfLifeSeconds), yielding:
///   • 1.0 at age = 0  (just visited)
///   • ≈0.5 at age ≈ halfLife
///   • → 0.0 as age → ∞
public struct TimeDecayScorer: Sendable {
    /// Age in seconds at which the score reaches ~0.37 (1/e). Defaults to 3600 s = 1 hour.
    public let halfLifeSeconds: Double

    public init(halfLifeSeconds: Double = 3600) {
        self.halfLifeSeconds = max(60, halfLifeSeconds)
    }

    /// Returns a score in [0.0, 1.0].
    public func score(lastVisitedAt: Date, now: Date = Date()) -> Double {
        let age = max(0, now.timeIntervalSince(lastVisitedAt))
        return exp(-age / halfLifeSeconds)
    }
}
