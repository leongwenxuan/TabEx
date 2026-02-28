import Foundation

// MARK: - Arena History models

public enum ArenaCategory: String, Codable, CaseIterable, Sendable {
    case auto
    case manual
}

public struct ArenaRound: Codable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let category: ArenaCategory
    public let contestants: [Contestant]
    public let tabCount: Int
    public let keepCount: Int
    public let closeCount: Int
    public let flagCount: Int

    public struct Contestant: Codable, Identifiable, Sendable {
        public let tabId: Int
        public let title: String
        public let url: String
        public let decision: TabDecision
        public let score: Double
        public let summary: String?

        public var id: Int { tabId }

        public init(tabId: Int, title: String, url: String, decision: TabDecision, score: Double, summary: String?) {
            self.tabId = tabId
            self.title = title
            self.url = url
            self.decision = decision
            self.score = score
            self.summary = summary
        }
    }

    public init(
        category: ArenaCategory,
        contestants: [Contestant],
        tabCount: Int,
        keepCount: Int,
        closeCount: Int,
        flagCount: Int
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.category = category
        self.contestants = contestants
        self.tabCount = tabCount
        self.keepCount = keepCount
        self.closeCount = closeCount
        self.flagCount = flagCount
    }
}

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

    public static var resultsURL: URL {
        storeDirectory.appendingPathComponent("latest-results.json")
    }

    public static var arenaHistoryURL: URL {
        storeDirectory.appendingPathComponent("arena-history.json")
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

    // MARK: - Scoring results persistence

    /// Snapshot of the latest scoring round, persisted so the menu bar app can load it.
    public struct ScoringSnapshot: Codable {
        public let results: [TabResult]
        public let tabs: [TabData]
        public let timestamp: Date

        public init(results: [TabResult], tabs: [TabData]) {
            self.results = results
            self.tabs = tabs
            self.timestamp = Date()
        }
    }

    public static func saveResults(_ results: [TabResult], tabs: [TabData]) {
        do {
            try ensureDirectory()
            let snapshot = ScoringSnapshot(results: results, tabs: tabs)
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(snapshot)
            try data.write(to: resultsURL, options: .atomic)
        } catch {
            fputs("[TabX] Failed to save results: \(error)\n", stderr)
        }
    }

    public static func loadResults() -> ScoringSnapshot? {
        guard let data = try? Data(contentsOf: resultsURL) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(ScoringSnapshot.self, from: data)
    }

    // MARK: - Arena history persistence

    private static let arenaHistoryLimit = 50

    public static func saveArenaRound(_ round: ArenaRound) {
        do {
            try ensureDirectory()
            var history = loadArenaHistory()
            history.insert(round, at: 0)
            if history.count > arenaHistoryLimit {
                history = Array(history.prefix(arenaHistoryLimit))
            }
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(history)
            try data.write(to: arenaHistoryURL, options: .atomic)
        } catch {
            fputs("[TabX] Failed to save arena history: \(error)\n", stderr)
        }
    }

    public static func loadArenaHistory() -> [ArenaRound] {
        guard let data = try? Data(contentsOf: arenaHistoryURL) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([ArenaRound].self, from: data)) ?? []
    }

    // MARK: - Private

    private static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }
}
