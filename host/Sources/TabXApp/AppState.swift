import Foundation
import TabXHostLib

// MARK: - Display models

struct TabDisplayItem: Identifiable, Sendable {
    let id: Int
    let title: String
    let url: String
    let decision: TabDecision
    let score: Double
    let reason: String
    let summary: String?
    let insights: [String]?
}

struct ClosedTabRecord: Identifiable, Sendable {
    let id: UUID
    let item: TabDisplayItem
    let closedAt: Date

    init(item: TabDisplayItem) {
        self.id = UUID()
        self.item = item
        self.closedAt = Date()
    }
}

// MARK: - Arena

enum ArenaPhase: Equatable, Sendable {
    case idle
    case analyzing(completed: Int, total: Int)
    case judging
    case decided
}

enum TabArenaStatus: Equatable, Sendable {
    case waiting
    case analyzing
    case analyzed(score: Double)
    case decided(decision: TabDecision, score: Double)
}

struct ArenaContestant: Identifiable, Sendable {
    let id: Int
    let title: String
    let url: String
    var status: TabArenaStatus
    var summary: String?
    var insights: [String]?
}

// MARK: - AppState

/// Observable state shared between the menu bar UI and the native messaging service.
@Observable
final class AppState {
    var tabResults: [TabDisplayItem] = []
    var gitBranch: String? = nil
    var gitRepoPath: String? = nil
    var bundleGeneratedAt: Date? = nil
    var recentlyClosed: [ClosedTabRecord] = []

    // Branch / session state
    var activeBranch: String? = nil
    var activeWorkspaceKey: String? = nil
    var sessionIndex: [SessionIndexEntry] = []

    // Arena state
    var arenaPhase: ArenaPhase = .idle
    var contestants: [ArenaContestant] = []
    var lastArenaAt: Date? = nil
    var arenaRunning: Bool = false
    var arenaHistory: [ArenaRound] = []

    // Bundle server state
    var bundleServerRunning: Bool = false
    var bundleServerURL: String = "http://localhost:9876/bundle"
    private var bundleServer: BundleServer?

    var sensitivity: Double = 0.5 {
        didSet { persistConfig() }
    }
    var safelist: [String] = [] {
        didSet { persistConfig() }
    }

    private let configManager = ConfigManager()
    private var pollTimer: Timer?

    init() {
        let cfg = configManager.config
        sensitivity = cfg.scoring.sensitivity
        safelist = cfg.scoring.safelist
        arenaHistory = BundleStore.loadArenaHistory()
        refreshGitContext()
        refreshBundle()
        loadResultsFromDisk()
        loadTabsFromDisk()
        loadActiveSessionFromDisk()
        loadSessionIndex()
        startPolling()
        startBundleServer()
    }

    private func startBundleServer() {
        let server = BundleServer()
        server.onStatusChange = { [weak self] running in
            DispatchQueue.main.async {
                self?.bundleServerRunning = running
            }
        }
        server.start()
        bundleServer = server
    }

    /// Poll `~/.tabx/` every 2 seconds so the standalone app
    /// stays in sync with the CLI host that Chrome talks to.
    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshGitContext()
            self?.loadResultsFromDisk()
            self?.loadTabsFromDisk()
            self?.loadActiveSessionFromDisk()
            self?.loadSessionIndex()
        }
    }

    private func loadResultsFromDisk() {
        guard let snapshot = BundleStore.loadResults() else { return }
        // Only apply if newer than what we already have.
        if let lastArena = lastArenaAt, snapshot.timestamp <= lastArena { return }
        // Seed contestants from disk if arena hasn't been started live
        if contestants.isEmpty {
            contestants = snapshot.tabs.map { tab in
                ArenaContestant(
                    id: tab.tabId,
                    title: tab.title,
                    url: tab.url,
                    status: .waiting,
                    summary: nil,
                    insights: nil
                )
            }
        }
        applyDecisions(snapshot.results, tabs: snapshot.tabs)
    }

    /// Load raw tab data from Chrome (available on every tab_update, not just branch switches).
    private var lastBranchSwitchAt: Date? = nil

    private func loadTabsFromDisk() {
        guard let snapshot = BundleStore.loadTabs() else { return }
        // Don't overwrite while an arena fight is actively running.
        if case .idle = arenaPhase {} else { return }
        // Skip stale tabs from before a branch switch
        if let switchAt = lastBranchSwitchAt, snapshot.timestamp <= switchAt { return }
        tabResults = snapshot.tabs.map { tab in
            TabDisplayItem(
                id: tab.tabId,
                title: tab.title,
                url: tab.url,
                decision: .keep,
                score: 0,
                reason: "Awaiting scoring",
                summary: nil,
                insights: nil
            )
        }
    }

    /// Generates a markdown context bundle from arena winners (keep/flag decisions only).
    func winningContextMarkdown() -> String {
        let winners = tabResults.filter { $0.decision == .keep || $0.decision == .flag }
            .sorted { $0.score > $1.score }
        if winners.isEmpty { return "No winning tabs from the last arena fight." }

        var lines: [String] = []
        lines.append("# TabX Winning Context")
        lines.append("")
        if let branch = activeBranch ?? gitBranch {
            lines.append("**Branch:** `\(branch)`")
        }
        lines.append("**Winners:** \(winners.count) tabs")
        lines.append("")

        for tab in winners {
            let badge = tab.decision == .keep ? "KEEP" : "FLAG"
            lines.append("## [\(badge) \(String(format: "%.0f%%", tab.score * 100))] \(tab.title)")
            lines.append("- **URL:** \(tab.url)")
            if !tab.reason.isEmpty && tab.reason != "Awaiting scoring" {
                lines.append("- **Reason:** \(tab.reason)")
            }
            if let summary = tab.summary {
                lines.append("- **Summary:** \(summary)")
            }
            if let insights = tab.insights, !insights.isEmpty {
                lines.append("- **Insights:**")
                for insight in insights {
                    lines.append("  - \(insight)")
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    func resetArena() {
        lastArenaAt = nil
        arenaPhase = .idle
        contestants = []
    }

    // MARK: - Arena events

    /// Called when a new scoring round begins.
    func arenaStarted(tabs: [TabData]) {
        arenaPhase = .analyzing(completed: 0, total: tabs.count)
        contestants = tabs.map { tab in
            ArenaContestant(
                id: tab.tabId,
                title: tab.title,
                url: tab.url,
                status: .waiting,
                summary: nil,
                insights: nil
            )
        }
    }

    /// Called when a single tab agent finishes analysis.
    func agentCompleted(tabId: Int, score: Double, summary: String?) {
        if let idx = contestants.firstIndex(where: { $0.id == tabId }) {
            contestants[idx].status = .analyzed(score: score)
            contestants[idx].summary = summary
        }
        // Update phase progress
        let completed = contestants.filter {
            if case .analyzed = $0.status { return true }
            if case .decided = $0.status { return true }
            return false
        }.count
        arenaPhase = .analyzing(completed: completed, total: contestants.count)
    }

    /// Called when a tab agent starts analyzing.
    func agentStarted(tabId: Int) {
        if let idx = contestants.firstIndex(where: { $0.id == tabId }) {
            contestants[idx].status = .analyzing
        }
    }

    /// Called when the judge phase starts.
    func judgeStarted() {
        arenaPhase = .judging
    }

    /// Called when all decisions are in.
    func arenaCompleted() {
        arenaPhase = .decided
        lastArenaAt = Date()
        saveArenaRound()
    }

    // MARK: - Manual arena trigger

    func runManualArena() {
        guard !arenaRunning else { return }

        // Try scored results first, fall back to raw tab data from Chrome.
        let tabs: [TabData]
        if let scored = BundleStore.loadResults(), !scored.tabs.isEmpty {
            tabs = scored.tabs
        } else if let raw = BundleStore.loadTabs(), !raw.tabs.isEmpty {
            tabs = raw.tabs
        } else {
            return
        }

        arenaRunning = true
        let runner = AgentRunner(
            config: configManager.config.scoring,
            openaiConfig: configManager.config.openai
        )

        runner.arenaCallbacks = ArenaCallbacks(
            onArenaStarted: { [weak self] tabs in
                DispatchQueue.main.async { self?.arenaStarted(tabs: tabs) }
            },
            onAgentStarted: { [weak self] tabId in
                DispatchQueue.main.async { self?.agentStarted(tabId: tabId) }
            },
            onAgentCompleted: { [weak self] tabId, score, summary in
                DispatchQueue.main.async { self?.agentCompleted(tabId: tabId, score: score, summary: summary) }
            },
            onJudgeStarted: { [weak self] in
                DispatchQueue.main.async { self?.judgeStarted() }
            }
        )

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let results = runner.score(tabs: tabs)
            BundleStore.saveResults(results, tabs: tabs)
            DispatchQueue.main.async {
                self?.applyDecisions(results, tabs: tabs)
                self?.arenaRunning = false
            }
        }
    }

    // MARK: - Data update

    func applyDecisions(_ results: [TabResult], tabs: [TabData]) {
        let tabMap = Dictionary(uniqueKeysWithValues: tabs.map { ($0.tabId, $0) })
        tabResults = results.map { result in
            let tab = tabMap[result.tabId]
            return TabDisplayItem(
                id: result.tabId,
                title: tab?.title ?? "Tab \(result.tabId)",
                url: tab?.url ?? "",
                decision: result.decision,
                score: result.score,
                reason: result.reason,
                summary: result.summary,
                insights: result.insights
            )
        }.sorted { $0.score > $1.score }

        // Update arena contestants with final decisions
        for result in results {
            if let idx = contestants.firstIndex(where: { $0.id == result.tabId }) {
                contestants[idx].status = .decided(decision: result.decision, score: result.score)
                contestants[idx].summary = result.summary
                contestants[idx].insights = result.insights
            }
        }
        // Sort contestants by score (winners at top)
        contestants.sort { lhs, rhs in
            scoreValue(lhs.status) > scoreValue(rhs.status)
        }

        arenaCompleted()
        refreshGitContext()
        refreshBundle()
    }

    func refreshGitContext() {
        let detectFrom = configManager.config.repoPath ?? FileManager.default.currentDirectoryPath
        let ctx = GitContext.detect(from: detectFrom)
        // Detect branch change from local git and update active session
        if let branch = ctx.branch, let repoPath = ctx.repoPath, branch != gitBranch, gitBranch != nil {
            let key = WorkspaceKey(repoPath: repoPath, branch: branch)
            activeBranch = branch
            activeWorkspaceKey = key.rawValue
            lastArenaAt = nil
            lastBranchSwitchAt = Date()
            tabResults = []
            contestants = []
            // Write active-session so the UI reflects immediately
            BundleStore.saveActiveSession(
                BundleStore.ActiveSessionInfo(branch: branch, repoPath: repoPath, workspaceKey: key)
            )
            loadSessionIndex()
        }
        gitBranch = ctx.branch
        gitRepoPath = ctx.repoPath
    }

    func refreshBundle() {
        if let bundle = BundleStore.loadBundle() {
            bundleGeneratedAt = bundle.generatedAt
        }
    }

    // MARK: - Safelist management

    func addToSafelist(_ domain: String) {
        let trimmed = domain.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !safelist.contains(trimmed) else { return }
        safelist.append(trimmed)
    }

    func removeFromSafelist(_ domain: String) {
        safelist.removeAll { $0 == domain }
    }

    // MARK: - Recently closed

    func recordClosed(_ item: TabDisplayItem) {
        recentlyClosed.insert(ClosedTabRecord(item: item), at: 0)
        if recentlyClosed.count > 20 { recentlyClosed.removeLast() }
    }

    // MARK: - Config persistence

    private func persistConfig() {
        let current = configManager.config.scoring
        let updated = ScoringConfig(
            sensitivity: sensitivity,
            closeThreshold: current.closeThreshold,
            keepThreshold: current.keepThreshold,
            safelist: safelist,
            stalenessThresholdSeconds: current.stalenessThresholdSeconds,
            retentionSeconds: current.retentionSeconds
        )
        configManager.apply(scoringUpdate: updated)
        try? configManager.save()
    }

    // MARK: - Arena history

    private func saveArenaRound() {
        let roundContestants: [ArenaRound.Contestant] = contestants.compactMap { c -> ArenaRound.Contestant? in
            guard case .decided(let decision, let score) = c.status else { return nil }
            return ArenaRound.Contestant(
                tabId: c.id,
                title: c.title,
                url: c.url,
                decision: decision,
                score: score,
                summary: c.summary
            )
        }
        guard !roundContestants.isEmpty else { return }

        let keepCount = roundContestants.filter { $0.decision == .keep }.count
        let closeCount = roundContestants.filter { $0.decision == .close }.count
        let flagCount = roundContestants.filter { $0.decision == .flag }.count

        let round = ArenaRound(
            category: .manual,
            contestants: roundContestants,
            tabCount: roundContestants.count,
            keepCount: keepCount,
            closeCount: closeCount,
            flagCount: flagCount
        )

        arenaHistory.insert(round, at: 0)
        if arenaHistory.count > 50 { arenaHistory = Array(arenaHistory.prefix(50)) }
        BundleStore.saveArenaRound(round)
    }

    // MARK: - Reset

    func resetAll() {
        BundleStore.resetAll()
        tabResults = []
        contestants = []
        arenaHistory = []
        arenaPhase = .idle
        lastArenaAt = nil
        recentlyClosed = []
        activeBranch = nil
        activeWorkspaceKey = nil
        sessionIndex = []
        gitBranch = nil
        bundleGeneratedAt = nil
    }

    // MARK: - Active session / branch tracking

    private func loadActiveSessionFromDisk() {
        guard let info = BundleStore.loadActiveSession() else { return }
        // Branch changed — clear stale arena results so loadTabsFromDisk can update
        if activeBranch != nil && activeBranch != info.branch {
            lastArenaAt = nil
            tabResults = []
            contestants = []
        }
        activeBranch = info.branch
        activeWorkspaceKey = info.workspaceKey.rawValue
    }

    private func loadSessionIndex() {
        sessionIndex = SessionStore.loadIndex()
    }

    func loadSessionTabs(for key: WorkspaceKey) -> [TabDisplayItem] {
        guard let session = SessionStore.load(key: key) else { return [] }
        return session.urlForTabId.compactMap { idStr, url -> TabDisplayItem? in
            guard let tabId = Int(idStr) else { return nil }
            let title = session.titleForTabId[idStr] ?? "Tab \(tabId)"
            let result = session.latestResults.first { $0.tabId == tabId }
            return TabDisplayItem(
                id: tabId,
                title: title,
                url: url,
                decision: result?.decision ?? .keep,
                score: result?.score ?? 0,
                reason: result?.reason ?? "Saved session",
                summary: result?.summary,
                insights: result?.insights
            )
        }.sorted { $0.title < $1.title }
    }

    // MARK: - Helpers

    private func scoreValue(_ status: TabArenaStatus) -> Double {
        switch status {
        case .waiting: return -1
        case .analyzing: return -0.5
        case .analyzed(let s): return s
        case .decided(_, let s): return s
        }
    }
}
