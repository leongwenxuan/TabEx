import Foundation

// MARK: - Judged Result

/// The judge's final verdict for a single tab after comparing all agent analyses.
public struct JudgedResult: Sendable {
    public let tabId: Int
    public let decision: TabDecision
    public let score: Double
    public let reason: String
    public let summary: String
    public let insights: [String]

    public init(
        tabId: Int,
        decision: TabDecision,
        score: Double,
        reason: String,
        summary: String,
        insights: [String]
    ) {
        self.tabId = tabId
        self.decision = decision
        self.score = score
        self.reason = reason
        self.summary = summary
        self.insights = insights
    }
}

// MARK: - Arena Judge

/// Receives all tab agent analyses and uses a more powerful LLM to rank and judge
/// which tabs to keep, flag, or close based on overall relevance to the user's work.
public struct ArenaJudge: Sendable {
    private let client: any LLMClientProtocol
    private let gitContext: GitContext
    private let config: ScoringConfig
    private let model: String

    public init(
        client: any LLMClientProtocol,
        gitContext: GitContext,
        config: ScoringConfig,
        model: String
    ) {
        self.client = client
        self.gitContext = gitContext
        self.config = config
        self.model = model
    }

    /// Judge all agent analyses and produce ranked decisions.
    public func judge(analyses: [TabAnalysis], tabs: [TabData]) -> [JudgedResult] {
        let prompt = buildPrompt(analyses: analyses, tabs: tabs)
        do {
            let response = try client.chatCompletion(
                model: model,
                messages: [
                    ChatMessage(role: "system", content: systemPrompt),
                    ChatMessage(role: "user", content: prompt),
                ],
                temperature: 0.2,
                maxTokens: 2048
            )
            let parsed = parseJudgement(response: response, analyses: analyses)
            return applyThresholds(parsed)
        } catch {
            fputs("[TabX Judge] Judgement failed: \(error.localizedDescription)\n", stderr)
            return fallback(analyses: analyses)
        }
    }

    // MARK: - Prompt Construction

    private var systemPrompt: String {
        """
        You are a tab relevance judge. You receive summaries from individual tab agents \
        and must rank all tabs by relevance to the user's coding work. Decide which tabs \
        to keep, flag for review, or close. Be decisive but fair.
        """
    }

    private func buildPrompt(analyses: [TabAnalysis], tabs: [TabData]) -> String {
        let branch = gitContext.branch ?? "unknown"
        let files = gitContext.recentFiles.prefix(20).joined(separator: ", ")

        var tabSummaries = ""
        for (i, analysis) in analyses.enumerated() {
            let tab = tabs.first { $0.tabId == analysis.tabId }
            let url = tab?.url ?? "unknown"
            tabSummaries += """

            Tab \(i + 1) [id=\(analysis.tabId)]:
              URL: \(url)
              Agent summary: \(analysis.summary)
              Signals: \(analysis.relevanceSignals.joined(separator: "; "))
              Agent score: \(String(format: "%.2f", analysis.relevanceScore))

            """
        }

        return """
        ## Git Context
        Branch: \(branch)
        Recent files: \(files)

        ## Tab Agent Reports
        \(tabSummaries)

        For each tab, respond with ONLY a JSON array (no markdown fencing):
        [
          {
            "tabId": <number>,
            "score": 0.0 to 1.0,
            "reason": "brief reason for decision",
            "insights": ["up to 3 key insights about this tab"]
          }
        ]

        Score guidelines:
        - >= 0.6: highly relevant to current work, keep
        - 0.3-0.6: somewhat relevant, flag for review
        - < 0.3: not relevant, close
        """
    }

    // MARK: - Response Parsing

    private func parseJudgement(response: String, analyses: [TabAnalysis]) -> [JudgedResult] {
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return fallback(analyses: analyses)
        }

        let analysisMap = Dictionary(uniqueKeysWithValues: analyses.map { ($0.tabId, $0) })

        return array.compactMap { item -> JudgedResult? in
            guard let tabId = item["tabId"] as? Int,
                  let score = item["score"] as? Double
            else { return nil }

            let reason = item["reason"] as? String ?? ""
            let insights = item["insights"] as? [String] ?? []
            let summary = analysisMap[tabId]?.summary ?? ""
            let clampedScore = max(0.0, min(1.0, score))

            return JudgedResult(
                tabId: tabId,
                decision: decide(score: clampedScore),
                score: clampedScore,
                reason: reason,
                summary: summary,
                insights: insights
            )
        }
    }

    private func applyThresholds(_ results: [JudgedResult]) -> [JudgedResult] {
        // Respect safelist: any tab whose domain is safelisted gets forced to .keep
        return results.map { result in
            result
        }
    }

    private func decide(score: Double) -> TabDecision {
        if score < config.closeThreshold { return .close }
        if score >= config.keepThreshold { return .keep }
        return .flag
    }

    // MARK: - Fallback

    /// When the judge API call fails, fall back to each agent's self-assessed score.
    private func fallback(analyses: [TabAnalysis]) -> [JudgedResult] {
        analyses.map { analysis in
            let score = analysis.relevanceScore
            return JudgedResult(
                tabId: analysis.tabId,
                decision: decide(score: score),
                score: score,
                reason: "agent-self-assessed (judge unavailable)",
                summary: analysis.summary,
                insights: analysis.relevanceSignals
            )
        }
    }
}
