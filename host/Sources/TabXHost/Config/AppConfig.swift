import Foundation

/// Top-level application configuration that wraps scoring config and host preferences.
public struct AppConfig: Codable, Sendable {
    public var scoring: ScoringConfig
    public var logLevel: LogLevel
    /// Optional path override for the bundle storage root (defaults to ~/.tabx/).
    public var bundleStorePath: String?

    public enum LogLevel: String, Codable, Sendable {
        case debug, info, warning, error
    }

    public init(
        scoring: ScoringConfig = .default,
        logLevel: LogLevel = .info,
        bundleStorePath: String? = nil
    ) {
        self.scoring = scoring
        self.logLevel = logLevel
        self.bundleStorePath = bundleStorePath
    }

    public static let `default` = AppConfig()
}
