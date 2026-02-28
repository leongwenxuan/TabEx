import Foundation

/// Top-level application configuration combining scoring settings and app preferences.
public struct AppConfig: Codable, Sendable {
    /// Scoring / pruning configuration.
    public var scoring: ScoringConfig
    /// OpenAI / LLM agent configuration.
    public var openai: OpenAIConfig
    /// Whether to write debug logs to stderr.
    public var debugLogging: Bool
    /// Version string reported by `--version`.
    public var version: String
    /// Path to the git repository to monitor for branch switches.
    /// When nil, falls back to the process working directory (which won't work
    /// when Chrome launches the native host).
    public var repoPath: String?

    public init(
        scoring: ScoringConfig = .default,
        openai: OpenAIConfig = .default,
        debugLogging: Bool = false,
        version: String = "1.0.0",
        repoPath: String? = nil
    ) {
        self.scoring = scoring
        self.openai = openai
        self.debugLogging = debugLogging
        self.version = version
        self.repoPath = repoPath
    }

    public static let `default` = AppConfig()

    // Custom decoding for backward compatibility — missing keys decode to defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.scoring = try container.decodeIfPresent(ScoringConfig.self, forKey: .scoring) ?? .default
        self.openai = try container.decodeIfPresent(OpenAIConfig.self, forKey: .openai) ?? .default
        self.debugLogging = try container.decodeIfPresent(Bool.self, forKey: .debugLogging) ?? false
        self.version = try container.decodeIfPresent(String.self, forKey: .version) ?? "1.0.0"
        self.repoPath = try container.decodeIfPresent(String.self, forKey: .repoPath)
    }
}
