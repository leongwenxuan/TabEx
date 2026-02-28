import Foundation

/// Manages loading, saving, and live-updating of `AppConfig`.
///
/// Config is stored at `~/.tabx/config.json`.
public final class ConfigManager: @unchecked Sendable {

    // MARK: - Paths

    public static var configURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".tabx/config.json")
    }

    // MARK: - State

    private(set) public var config: AppConfig

    public init() {
        self.config = ConfigManager.load()
    }

    // MARK: - Public API

    /// Loads config from disk, falling back to defaults.
    public static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL) else { return .default }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(AppConfig.self, from: data)) ?? .default
    }

    /// Saves the current config to disk.
    public func save() throws {
        let url = ConfigManager.configURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(config)
        try data.write(to: url, options: .atomic)
    }

    /// Applies a partial `ScoringConfig` update received from the extension.
    public func apply(scoringUpdate: ScoringConfig) {
        config.scoring = scoringUpdate
    }

    /// Returns a pretty-printed JSON string of the current config.
    public func prettyJSON() -> String {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(config) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
