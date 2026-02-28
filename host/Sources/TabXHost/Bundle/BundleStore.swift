import Foundation

/// Persists context bundles and scoring state to `~/.tabx/`.
///
/// Directory layout:
///   ~/.tabx/
///     bundles/          – timestamped JSON bundle files
///     state.json        – latest BundleStore.State snapshot
public final class BundleStore {
    public static let shared = BundleStore()

    private let fm = FileManager.default
    private let root: URL

    public init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let home = fm.homeDirectoryForCurrentUser
            self.root = home.appendingPathComponent(".tabx")
        }
        try? fm.createDirectory(at: bundlesDir, withIntermediateDirectories: true)
    }

    // MARK: - Directories

    private var bundlesDir: URL { root.appendingPathComponent("bundles") }
    private var stateURL:   URL { root.appendingPathComponent("state.json") }

    // MARK: - Saving

    /// Saves the bundle to a timestamped JSON file and updates `state.json`.
    public func save(_ bundle: ContextBundle) throws {
        let enc = makeEncoder()
        let data = try enc.encode(bundle)

        // Timestamped file
        let filename = "bundle-\(timestamp(bundle.generatedAt)).json"
        let fileURL  = bundlesDir.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)

        // Prune old bundles (keep last 20)
        pruneOldBundles()
    }

    /// Saves the current state snapshot.
    public func saveState(_ state: State) throws {
        let data = try makeEncoder().encode(state)
        try data.write(to: stateURL, options: .atomic)
    }

    // MARK: - Loading

    /// Loads the most recently saved bundle, or nil if none exists.
    public func loadLatestBundle() -> ContextBundle? {
        guard let url = latestBundleURL() else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? makeDecoder().decode(ContextBundle.self, from: data)
    }

    /// Loads the persisted state, or returns a default empty state.
    public func loadState() -> State {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? makeDecoder().decode(State.self, from: data)
        else { return State() }
        return state
    }

    /// Lists all bundle file URLs, sorted newest-first.
    public func allBundleURLs() -> [URL] {
        (try? fm.contentsOfDirectory(
            at: bundlesDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ))?.filter { $0.pathExtension == "json" }
          .sorted { a, b in
              let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
              let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
              return aDate > bDate
          } ?? []
    }

    // MARK: - State model

    public struct State: Codable, Sendable {
        public var lastScoredAt: Date?
        public var tabCount: Int
        public var closedCount: Int

        public init(lastScoredAt: Date? = nil, tabCount: Int = 0, closedCount: Int = 0) {
            self.lastScoredAt = lastScoredAt
            self.tabCount = tabCount
            self.closedCount = closedCount
        }
    }

    // MARK: - Private helpers

    private func latestBundleURL() -> URL? {
        allBundleURLs().first
    }

    private func pruneOldBundles(keepLast count: Int = 20) {
        let urls = allBundleURLs()
        guard urls.count > count else { return }
        for url in urls.dropFirst(count) {
            try? fm.removeItem(at: url)
        }
    }

    private func timestamp(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
    }

    private func makeEncoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }

    private func makeDecoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }
}
