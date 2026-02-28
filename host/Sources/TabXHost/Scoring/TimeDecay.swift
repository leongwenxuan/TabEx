import Foundation

/// Scores a tab based on how recently it was last visited.
/// Uses an exponential decay: score = exp(-age / threshold).
/// Score approaches 1.0 for very recent tabs, approaches 0.0 for old ones.
public struct TimeDecayScorer: Sendable {
    /// The half-life constant (in seconds). Defaults to 1 hour.
    public var thresholdSeconds: Double

    public init(thresholdSeconds: Double = 3600) {
        self.thresholdSeconds = thresholdSeconds
    }

    /// Returns a score in [0.0, 1.0].
    public func score(lastVisitedAt: Date, now: Date = Date()) -> Double {
        let age = max(0, now.timeIntervalSince(lastVisitedAt))
        let t = max(thresholdSeconds, 60)
        return exp(-age / t)
    }
}
