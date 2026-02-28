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

// MARK: - AppState

/// Observable state shared between the menu bar UI and the native messaging service.
@Observable
final class AppState {
    var tabResults: [TabDisplayItem] = []
    var gitBranch: String? = nil
    var gitRepoPath: String? = nil
    var bundleGeneratedAt: Date? = nil
    var recentlyClosed: [ClosedTabRecord] = []

    var sensitivity: Double = 0.5 {
        didSet { persistConfig() }
    }
    var safelist: [String] = [] {
        didSet { persistConfig() }
    }

    private let configManager = ConfigManager()

    init() {
        let cfg = configManager.config
        sensitivity = cfg.scoring.sensitivity
        safelist = cfg.scoring.safelist
        refreshGitContext()
        refreshBundle()
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
                reason: result.reason
            )
        }.sorted { $0.score > $1.score }
        refreshGitContext()
        refreshBundle()
    }

    func refreshGitContext() {
        let ctx = GitContext.detect()
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
}
