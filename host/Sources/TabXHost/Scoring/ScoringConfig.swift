import Foundation

/// Per-signal weights used in the composite scoring formula.
public struct SignalWeights: Codable, Sendable {
    /// Weight for git-branch / file relevance signal (default 35%).
    public var git: Double
    /// Weight for recency / time-decay signal (default 20%).
    public var recency: Double
    /// Weight for reading depth signal (default 25%).
    public var readingDepth: Double
    /// Weight for semantic similarity signal (default 20%).
    public var semantic: Double

    public init(git: Double = 0.35, recency: Double = 0.20, readingDepth: Double = 0.25, semantic: Double = 0.20) {
        self.git = git
        self.recency = recency
        self.readingDepth = readingDepth
        self.semantic = semantic
    }

    public static let `default` = SignalWeights()

    /// Validates that weights sum to 1.0 (within floating point tolerance).
    public var isValid: Bool {
        abs(git + recency + readingDepth + semantic - 1.0) < 0.001
    }
}

/// Score thresholds that map a composite score to a tab decision.
public struct DecisionThresholds: Codable, Sendable {
    /// Score below this → .close decision.
    public var close: Double
    /// Score above this → .keep decision. Between close and keep → .flag.
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
