import Foundation

/// Signal weights that control how much each scoring component contributes to the final score.
public struct SignalWeights: Codable, Sendable {
    public var gitRelevance: Double
    public var recency: Double
    public var readingDepth: Double
    public var semantic: Double

    public init(
        gitRelevance: Double = 0.35,
        recency: Double = 0.20,
        readingDepth: Double = 0.25,
        semantic: Double = 0.20
    ) {
        self.gitRelevance = gitRelevance
        self.recency = recency
        self.readingDepth = readingDepth
        self.semantic = semantic
    }

    public static let `default` = SignalWeights()

    /// Validates that weights sum to approximately 1.0.
    public var isValid: Bool {
        let sum = gitRelevance + recency + readingDepth + semantic
        return abs(sum - 1.0) < 0.001
    }
}

/// Thresholds that determine the close/flag/keep decision bucket.
public struct DecisionThresholds: Codable, Sendable {
    /// Score strictly below this → close decision.
    public var close: Double
    /// Score at or above this → keep decision. Scores in [close, keep) → flag.
    public var keep: Double

    public init(close: Double = 0.3, keep: Double = 0.6) {
        self.close = close
        self.keep = keep
    }

    public static let `default` = DecisionThresholds()

    public func decide(score: Double) -> TabDecision {
        if score < close { return .close }
        if score >= keep { return .keep }
        return .flag
    }
}
