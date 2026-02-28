import Foundation

/// Scoring configuration that can be updated at runtime via a `config_update` message.
public struct ScoringConfig: Codable, Sendable {
    /// 0.0 = very permissive (keep almost everything), 1.0 = very aggressive pruning.
    public var sensitivity: Double

    /// Score below this → close decision.
    public var closeThreshold: Double

    /// Score above this → keep decision. Scores between close and keep → flag.
    public var keepThreshold: Double

    /// Domain names or URL patterns that must never be auto-closed.
    public var safelist: [String]

    /// Age in seconds beyond which a tab is considered stale (contributes to lower score).
    public var stalenessThresholdSeconds: Double

    /// How long (seconds) to retain page records in the bundle. 0 = session only.
    public var retentionSeconds: Double

    public init(
        sensitivity: Double = 0.5,
        closeThreshold: Double = 0.3,
        keepThreshold: Double = 0.6,
        safelist: [String] = [],
        stalenessThresholdSeconds: Double = 3600,
        retentionSeconds: Double = 86400
    ) {
        self.sensitivity = sensitivity
        self.closeThreshold = closeThreshold
        self.keepThreshold = keepThreshold
        self.safelist = safelist
        self.stalenessThresholdSeconds = stalenessThresholdSeconds
        self.retentionSeconds = retentionSeconds
    }

    public static let `default` = ScoringConfig()

    // MARK: Persistence

    private static var configURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("TabXHost/config.json")
    }

    public static func load() -> ScoringConfig {
        let url = configURL
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(ScoringConfig.self, from: data)
        else { return .default }
        return config
    }

    public func save() {
        let url = Self.configURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: url)
        }
    }
}
