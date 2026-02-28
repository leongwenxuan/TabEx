import Foundation

/// Manages loading, saving, and runtime updates of `AppConfig`.
///
/// Config is persisted to `~/.tabx/config.json` (overrides the legacy
/// ApplicationSupport location used by `ScoringConfig.save()`).
public final class ConfigManager: @unchecked Sendable {
    public static let shared = ConfigManager()

    private let configURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var _config: AppConfig
    private let lock = NSLock()

    public init(configURL: URL? = nil) {
        if let configURL {
            self.configURL = configURL
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.configURL = home.appendingPathComponent(".tabx/config.json")
        }

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        self._config = .default
        self._config = load()
    }

    // MARK: - Public API

    public var config: AppConfig {
        lock.withLock { _config }
    }

    public var scoringConfig: ScoringConfig {
        lock.withLock { _config.scoring }
    }

    public func update(_ newConfig: AppConfig) throws {
        lock.withLock { _config = newConfig }
        try save(newConfig)
    }

    public func updateScoring(_ newScoring: ScoringConfig) throws {
        var cfg = lock.withLock { _config }
        cfg.scoring = newScoring
        try update(cfg)
    }

    // MARK: - Persistence

    private func load() -> AppConfig {
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = try? Data(contentsOf: configURL),
              let config = try? decoder.decode(AppConfig.self, from: data)
        else { return .default }
        return config
    }

    private func save(_ config: AppConfig) throws {
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: .atomic)
    }
}
