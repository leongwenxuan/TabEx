import Foundation

/// Persists context bundles and scoring state to `~/.tabx/`.
public final class BundleStore {

    // MARK: - Paths

    public static var storeDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".tabx", isDirectory: true)
    }

    public static var bundleURL: URL {
        storeDirectory.appendingPathComponent("context-bundle.json")
    }

    public static var stateURL: URL {
        storeDirectory.appendingPathComponent("state.json")
    }

    // MARK: - Bundle persistence

    /// Saves a `ContextBundle` to `~/.tabx/context-bundle.json`.
    public static func saveBundle(_ bundle: ContextBundle) throws {
        try ensureDirectory()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(bundle)
        try data.write(to: bundleURL, options: .atomic)
    }

    /// Loads the most recently saved `ContextBundle`, or nil if none exists.
    public static func loadBundle() -> ContextBundle? {
        guard let data = try? Data(contentsOf: bundleURL) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(ContextBundle.self, from: data)
    }

    // MARK: - State persistence (arbitrary Codable)

    /// Persists an arbitrary `Encodable` state object to `~/.tabx/state.json`.
    public static func saveState<T: Encodable>(_ state: T) throws {
        try ensureDirectory()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(state)
        try data.write(to: stateURL, options: .atomic)
    }

    /// Loads and decodes a previously saved state object.
    public static func loadState<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(type, from: data)
    }

    // MARK: - Private

    private static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }
}
