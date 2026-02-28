import Foundation

/// Maintains a rolling window of tab activity and generates context bundles on demand.
/// Satisfies FR13, FR14, FR15, NFR2.
public final class BundleManager {
    private var pageRecords: [String: PageRecord] = [:]     // keyed by URL
    private var latestResults: [TabResult] = []
    private var gitContext: GitContext
    private let config: ScoringConfig
    /// Configured repo path for git detection. When set, `GitContext.detect(from:)` uses
    /// this instead of the process working directory (which is wrong when Chrome launches us).
    private let configuredRepoPath: String?

    /// URL of the context bundle JSON written to disk (for CLI / agent consumption).
    public static var bundleFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("TabXHost/context-bundle.json")
    }

    public init(config: ScoringConfig = .default, repoPath: String? = nil) {
        self.config = config
        self.configuredRepoPath = repoPath
        self.gitContext = GitContext.detect(from: repoPath ?? FileManager.default.currentDirectoryPath)
    }

    // MARK: - Updating state

    /// Ingest tab data from the extension.  Call every time a `tab_update` message arrives.
    public func ingest(_ tabs: [TabData]) {
        let now = Date()
        let cutoff = config.retentionSeconds > 0
            ? now.addingTimeInterval(-config.retentionSeconds)
            : .distantPast

        // Prune records outside the retention window.
        pageRecords = pageRecords.filter { $0.value.visitedAt >= cutoff }

        for tab in tabs {
            let existing = pageRecords[tab.url]
            // Accumulate time and keep the latest scroll depth / selections.
            let allHighlights: [String]
            if let sel = tab.selectedText, !sel.isEmpty {
                allHighlights = (existing?.highlights ?? []) + [sel]
            } else {
                allHighlights = existing?.highlights ?? []
            }
            pageRecords[tab.url] = PageRecord(
                url: tab.url,
                title: tab.title,
                contentDigest: tab.contentDigest ?? existing?.contentDigest,
                highlights: allHighlights,
                timeSpentSeconds: (existing?.timeSpentSeconds ?? 0) + tab.timeSpentSeconds,
                scrollDepth: max(existing?.scrollDepth ?? 0, tab.scrollDepth),
                visitedAt: tab.lastVisitedAt
            )
        }
    }

    /// Store the latest scoring results so the bundle can reflect surviving tabs.
    public func updateResults(_ results: [TabResult]) {
        latestResults = results
        gitContext = GitContext.detect(from: configuredRepoPath ?? FileManager.default.currentDirectoryPath)
    }

    // MARK: - Bundle generation

    /// Builds and returns a fresh `ContextBundle`.  Also persists it to disk (NFR2 / FR14).
    public func generateBundle() -> ContextBundle {
        let surviving: [SurvivingTab] = latestResults
            .filter { $0.decision != .close }
            .compactMap { result -> SurvivingTab? in
                guard let record = pageRecords[keyForTabId(result.tabId)] ?? pageRecords.values.first
                else { return nil }
                // Find the matching page record by cross-referencing tabId via a side-table if available.
                // Fallback: use the first page record matching any surviving tab in latestResults.
                return nil  // resolved below via tab-indexed lookup
            }

        // Build surviving tab list from the results directly (tabId + record lookup via a
        // parallel dictionary built during ingestion if available).
        let survivingTabs: [SurvivingTab] = latestResults
            .filter { $0.decision != .close }
            .map { result in
                SurvivingTab(
                    tabId: result.tabId,
                    url: urlForTabId[result.tabId] ?? "unknown",
                    title: titleForTabId[result.tabId] ?? "unknown",
                    score: result.score,
                    decision: result.decision
                )
            }

        let taskDescription: String? = gitContext.branch.map { branch in
            // Convert "feat/user-auth-flow" → "feat: user auth flow"
            branch
                .replacingOccurrences(of: "/", with: ": ", options: [], range: nil)
                .replacingOccurrences(of: "-", with: " ")
        }

        let bundle = ContextBundle(
            generatedAt: Date(),
            gitBranch: gitContext.branch,
            gitRepoPath: gitContext.repoPath,
            pagesRead: Array(pageRecords.values).sorted { $0.visitedAt > $1.visitedAt },
            survivingTabs: survivingTabs,
            openFiles: gitContext.recentFiles,
            taskDescription: taskDescription
        )

        persistBundle(bundle)
        return bundle
    }

    // MARK: - Snapshot / Restore

    /// Returns a copy of the manager's private state for session persistence.
    public func snapshot() -> BundleManagerState {
        BundleManagerState(
            pageRecords: pageRecords,
            latestResults: latestResults,
            urlForTabId: urlForTabId,
            titleForTabId: titleForTabId
        )
    }

    /// Replaces all private state from a previously saved snapshot.
    public func restore(_ state: BundleManagerState) {
        pageRecords = state.pageRecords
        latestResults = state.latestResults
        urlForTabId = state.urlForTabId
        titleForTabId = state.titleForTabId
    }

    // MARK: - Side tables (updated during ingestion)

    private var urlForTabId:   [Int: String] = [:]
    private var titleForTabId: [Int: String] = [:]

    // Override ingest to also populate side tables.
    public func ingest(_ tabs: [TabData], trackIds: Bool) {
        if trackIds {
            for tab in tabs {
                urlForTabId[tab.tabId]   = tab.url
                titleForTabId[tab.tabId] = tab.title
            }
        }
        ingest(tabs)
    }

    // MARK: - Persistence

    private func persistBundle(_ bundle: ContextBundle) {
        let url = Self.bundleFileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(bundle) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func keyForTabId(_ tabId: Int) -> String {
        urlForTabId[tabId] ?? ""
    }
}
