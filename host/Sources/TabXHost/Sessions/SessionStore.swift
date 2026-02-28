import Foundation

/// Persists and loads branch sessions to `~/.tabx/sessions/`.
/// Follows `BundleStore` patterns: static methods, `.iso8601`, `.prettyPrinted`, `.sortedKeys`, `.atomic`.
public final class SessionStore {

    // MARK: - Paths

    public static var sessionsDirectory: URL {
        BundleStore.storeDirectory.appendingPathComponent("sessions", isDirectory: true)
    }

    public static var indexURL: URL {
        sessionsDirectory.appendingPathComponent("index.json")
    }

    public static func sessionURL(for key: WorkspaceKey) -> URL {
        sessionsDirectory.appendingPathComponent("\(key.rawValue).json")
    }

    // MARK: - Save

    public static func save(_ session: BranchSession) {
        do {
            try ensureDirectory()
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(session)
            try data.write(to: sessionURL(for: session.workspaceKey), options: .atomic)
            updateIndex(with: session)
        } catch {
            fputs("[TabX] Failed to save session: \(error)\n", stderr)
        }
    }

    // MARK: - Load

    public static func load(key: WorkspaceKey) -> BranchSession? {
        let url = sessionURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(BranchSession.self, from: data)
    }

    // MARK: - Index

    public static func loadIndex() -> [SessionIndexEntry] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([SessionIndexEntry].self, from: data)) ?? []
    }

    // MARK: - Private

    private static func updateIndex(with session: BranchSession) {
        var index = loadIndex()
        // Remove existing entry for this key.
        index.removeAll { $0.workspaceKey == session.workspaceKey }
        // Insert new entry at the front.
        index.insert(SessionIndexEntry(from: session), at: 0)

        do {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(index)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            fputs("[TabX] Failed to update session index: \(error)\n", stderr)
        }
    }

    private static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    }
}
