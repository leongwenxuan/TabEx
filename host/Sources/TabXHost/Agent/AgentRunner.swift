import Foundation

/// Drop-in replacement for `ScoringEngine` that uses AI agents to evaluate tab relevance.
///
/// Flow:
/// 1. Detect git context
/// 2. If no API key → fallback to simple token-matching heuristic
/// 3. Spawn TabAgent.analyze() per tab in parallel
/// 4. Skip safelisted tabs (auto-keep with score 1.0)
/// 5. Feed all TabAnalysis to ArenaJudge
/// 6. Map JudgedResult → TabResult
/// Callbacks for arena progress events, used by the SwiftUI menu bar app.
public struct ArenaCallbacks: Sendable {
    public var onArenaStarted: @Sendable ([TabData]) -> Void
    public var onAgentStarted: @Sendable (Int) -> Void
    public var onAgentCompleted: @Sendable (Int, Double, String?) -> Void
    public var onJudgeStarted: @Sendable () -> Void

    public init(
        onArenaStarted: @escaping @Sendable ([TabData]) -> Void = { _ in },
        onAgentStarted: @escaping @Sendable (Int) -> Void = { _ in },
        onAgentCompleted: @escaping @Sendable (Int, Double, String?) -> Void = { _, _, _ in },
        onJudgeStarted: @escaping @Sendable () -> Void = {}
    ) {
        self.onArenaStarted = onArenaStarted
        self.onAgentStarted = onAgentStarted
        self.onAgentCompleted = onAgentCompleted
        self.onJudgeStarted = onJudgeStarted
    }

    public static let noop = ArenaCallbacks()
}

public final class AgentRunner: @unchecked Sendable {
    private var config: ScoringConfig
    private var openaiConfig: OpenAIConfig
    private let client: any LLMClientProtocol
    public var arenaCallbacks: ArenaCallbacks = .noop

    public init(config: ScoringConfig = .default, openaiConfig: OpenAIConfig = .default) {
        self.config = config
        self.openaiConfig = openaiConfig
        self.client = OpenAIClient(config: openaiConfig)
    }

    /// Testable initializer that accepts a mock LLM client.
    public init(config: ScoringConfig = .default, openaiConfig: OpenAIConfig = .default, client: any LLMClientProtocol) {
        self.config = config
        self.openaiConfig = openaiConfig
        self.client = client
    }

    public func score(tabs: [TabData]) -> [TabResult] {
        let gitContext = GitContext.detect()

        // Separate safelisted tabs — they always get kept.
        var safeResults: [TabResult] = []
        var contestantTabs: [TabData] = []

        for tab in tabs {
            if isSafelisted(tab) {
                safeResults.append(TabResult(
                    tabId: tab.tabId, decision: .keep, score: 1.0,
                    reason: "safelisted", summary: nil, insights: nil
                ))
            } else {
                contestantTabs.append(tab)
            }
        }

        guard !contestantTabs.isEmpty else { return safeResults }

        // Notify arena started
        arenaCallbacks.onArenaStarted(contestantTabs)

        // No API key → use simple token-matching fallback.
        guard openaiConfig.hasAPIKey else {
            let fallbackResults = contestantTabs.map { tokenFallback($0, gitContext: gitContext) }
            return safeResults + fallbackResults
        }

        // Run tab agents in parallel.
        let analyses = runAgentsInParallel(tabs: contestantTabs, gitContext: gitContext)

        // Arena judge ranks all analyses.
        arenaCallbacks.onJudgeStarted()
        let judge = ArenaJudge(
            client: client,
            gitContext: gitContext,
            config: config,
            model: openaiConfig.judgeModel
        )
        let judged = judge.judge(analyses: analyses, tabs: contestantTabs)

        // Map judged results to TabResult.
        let judgedMap = Dictionary(uniqueKeysWithValues: judged.map { ($0.tabId, $0) })
        let agentResults = contestantTabs.map { tab -> TabResult in
            if let j = judgedMap[tab.tabId] {
                return TabResult(
                    tabId: j.tabId,
                    decision: j.decision,
                    score: j.score,
                    reason: j.reason,
                    summary: j.summary,
                    insights: j.insights
                )
            }
            // Tab not in judge output — neutral.
            return TabResult(
                tabId: tab.tabId, decision: .flag, score: 0.5,
                reason: "not-judged", summary: nil, insights: nil
            )
        }

        return safeResults + agentResults
    }

    public func updateConfig(_ newConfig: ScoringConfig) {
        config = newConfig
    }

    // MARK: - Parallel Agent Execution

    private func runAgentsInParallel(tabs: [TabData], gitContext: GitContext) -> [TabAnalysis] {
        let agent = TabAgent(client: client, gitContext: gitContext, model: openaiConfig.agentModel)
        var analyses = Array<TabAnalysis?>(repeating: nil, count: tabs.count)
        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)
        let lock = NSLock()

        for (i, tab) in tabs.enumerated() {
            group.enter()
            queue.async { [arenaCallbacks] in
                arenaCallbacks.onAgentStarted(tab.tabId)
                let result = agent.analyze(tab: tab)
                lock.lock()
                analyses[i] = result
                lock.unlock()
                arenaCallbacks.onAgentCompleted(tab.tabId, result.relevanceScore, result.summary)
                group.leave()
            }
        }

        group.wait()
        return analyses.compactMap { $0 }
    }

    // MARK: - Fallback Scoring

    /// Simple token-matching heuristic when no API key is configured.
    private func tokenFallback(_ tab: TabData, gitContext: GitContext) -> TabResult {
        guard let branch = gitContext.branch, !branch.isEmpty else {
            return TabResult(
                tabId: tab.tabId, decision: .flag, score: 0.5,
                reason: "no-git-context", summary: nil, insights: nil
            )
        }

        let contextTokens = Set(
            tokenise(branch) + gitContext.recentFiles.flatMap { tokenise($0) }
        )
        guard !contextTokens.isEmpty else {
            return TabResult(
                tabId: tab.tabId, decision: .flag, score: 0.5,
                reason: "no-context-tokens", summary: nil, insights: nil
            )
        }

        let tabText = [tab.title, tab.url, tab.contentDigest ?? "", tab.selectedText ?? ""]
            .joined(separator: " ").lowercased()
        let matchCount = contextTokens.filter { tabText.contains($0) }.count
        let score = min(1.0, Double(matchCount) / Double(contextTokens.count) * 3.0)
        let clamped = max(0.0, min(1.0, score))
        let decision: TabDecision = clamped < config.closeThreshold ? .close
            : clamped >= config.keepThreshold ? .keep : .flag

        return TabResult(
            tabId: tab.tabId, decision: decision, score: clamped,
            reason: "token-fallback", summary: nil, insights: nil
        )
    }

    private func tokenise(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
    }

    private func isSafelisted(_ tab: TabData) -> Bool {
        guard let host = URL(string: tab.url)?.host else { return false }
        return config.safelist.contains { pattern in
            host == pattern || host.hasSuffix("." + pattern)
        }
    }
}

// MARK: - Protocol Conformance

extension AgentRunner: ScoringEngineProtocol {}
