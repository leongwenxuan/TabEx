import Foundation
@preconcurrency import NaturalLanguage

/// Computes relevance scores for browser tabs and emits close/keep/flag decisions.
///
/// Scoring model (weighted sum, 0.0–1.0):
///   • Git relevance  (35%) – branch name / touched file token overlap with tab content
///   • Recency        (20%) – exponential decay from last visit time
///   • Reading depth  (25%) – time spent + scroll depth + text selection
///   • Semantic sim   (20%) – NLEmbedding cosine similarity against branch tokens
public final class ScoringEngine {
    private var config: ScoringConfig
    private var gitContext: GitContext
    private let embedder: NLEmbedding?

    public init(config: ScoringConfig = .default) {
        self.config = config
        self.gitContext = GitContext.detect()
        self.embedder = NLEmbedding.wordEmbedding(for: .english)
    }

    // MARK: - Public API

    public func updateConfig(_ newConfig: ScoringConfig) {
        config = newConfig
    }

    public func refreshGitContext() {
        gitContext = GitContext.detect()
    }

    /// Scores each tab synchronously and returns one `TabResult` per tab.
    /// Must complete within NFR1's 5-second window for reasonable tab counts (< 200).
    public func score(tabs: [TabData]) -> [TabResult] {
        refreshGitContext()
        return tabs.map { scoreTab($0) }
    }

    // MARK: - Per-tab scoring

    private func scoreTab(_ tab: TabData) -> TabResult {
        if isSafelisted(tab) {
            return TabResult(tabId: tab.tabId, decision: .keep, score: 1.0, reason: "safelisted")
        }

        let git      = gitRelevanceScore(tab)
        let recency  = recencyScore(tab)
        let depth    = readingDepthScore(tab)
        let semantic = semanticScore(tab)

        let raw = git * 0.35 + recency * 0.20 + depth * 0.25 + semantic * 0.20

        // Higher sensitivity shifts effective score downward → more aggressive pruning.
        let adjusted = raw * (1.0 - config.sensitivity * 0.40)
        let score    = max(0.0, min(1.0, adjusted))
        let decision = decide(score: score)
        let reason   = buildReason(git: git, recency: recency, depth: depth, semantic: semantic)

        return TabResult(tabId: tab.tabId, decision: decision, score: score, reason: reason)
    }

    // MARK: - Signal functions

    private func gitRelevanceScore(_ tab: TabData) -> Double {
        guard let branch = gitContext.branch, !branch.isEmpty else { return 0.3 }
        let contextTokens = Set(
            tokenise(branch) + gitContext.recentFiles.flatMap { tokenise($0) }
        )
        guard !contextTokens.isEmpty else { return 0.3 }
        let tabText = [tab.title, tab.url, tab.contentDigest ?? "", tab.selectedText ?? ""]
            .joined(separator: " ").lowercased()
        let matchCount = contextTokens.filter { tabText.contains($0) }.count
        // Scale generously: even a few matches should push score up.
        return min(1.0, Double(matchCount) / Double(contextTokens.count) * 3.0)
    }

    private func recencyScore(_ tab: TabData) -> Double {
        let age       = max(0, Date().timeIntervalSince(tab.lastVisitedAt))
        let threshold = max(config.stalenessThresholdSeconds, 60)
        return exp(-age / threshold)
    }

    private func readingDepthScore(_ tab: TabData) -> Double {
        // Time: sigmoid-ish curve, ~0.7 at 120 s, ~1.0 at 300 s.
        let timeScore      = 1.0 - exp(-tab.timeSpentSeconds / 120.0)
        let scrollScore    = max(0.0, min(1.0, tab.scrollDepth))
        let selectionBonus = (tab.selectedText?.isEmpty == false) ? 0.2 : 0.0
        return min(1.0, timeScore * 0.5 + scrollScore * 0.3 + selectionBonus)
    }

    private func semanticScore(_ tab: TabData) -> Double {
        guard let embedder else { return 0.3 }
        guard let branch = gitContext.branch, !branch.isEmpty else { return 0.3 }

        let branchTokens = tokenise(branch).prefix(5)
        let tabTokens    = tokenise(
            [tab.title, tab.contentDigest ?? "", tab.selectedText ?? ""].joined(separator: " ")
        ).prefix(10)

        guard !branchTokens.isEmpty, !tabTokens.isEmpty else { return 0.3 }

        var total = 0.0
        var count = 0
        for bt in branchTokens {
            for tt in tabTokens {
                let dist = embedder.distance(between: bt, and: tt, distanceType: .cosine)
                total += 1.0 - Double(dist)
                count += 1
            }
        }
        guard count > 0 else { return 0.3 }
        return max(0.0, min(1.0, total / Double(count)))
    }

    // MARK: - Helpers

    private func decide(score: Double) -> TabDecision {
        if score < config.closeThreshold { return .close }
        if score >= config.keepThreshold { return .keep }
        return .flag
    }

    private func isSafelisted(_ tab: TabData) -> Bool {
        guard let host = URL(string: tab.url)?.host else { return false }
        return config.safelist.contains { pattern in
            host == pattern || host.hasSuffix("." + pattern)
        }
    }

    private func tokenise(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
    }

    private func buildReason(git: Double, recency: Double, depth: Double, semantic: Double) -> String {
        var tags: [String] = []
        if git      >  0.5 { tags.append("git-match") }
        if recency  <= 0.2 { tags.append("stale") }
        if depth    >  0.5 { tags.append("well-read") }
        if semantic >  0.6 { tags.append("semantic-match") }
        return tags.isEmpty ? "low-relevance" : tags.joined(separator: ",")
    }
}
