import Foundation

/// Top-level application configuration combining scoring settings and app preferences.
public struct AppConfig: Codable, Sendable {
    /// Scoring / pruning configuration.
    public var scoring: ScoringConfig
    /// Whether to write debug logs to stderr.
    public var debugLogging: Bool
    /// Version string reported by `--version`.
    public var version: String

    public init(
        scoring: ScoringConfig = .default,
        debugLogging: Bool = false,
        version: String = "1.0.0"
    ) {
        self.scoring = scoring
        self.debugLogging = debugLogging
        self.version = version
    }

    public static let `default` = AppConfig()
}
