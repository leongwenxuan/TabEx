import Foundation

// MARK: - Tab Analysis Result

/// The output of a single tab agent's analysis.
public struct TabAnalysis: Sendable {
    public let tabId: Int
    public let summary: String
    public let codePatterns: [String]
    public let relevanceSignals: [String]
    public let relevanceScore: Double

    public init(
        tabId: Int,
        summary: String,
        codePatterns: [String],
        relevanceSignals: [String],
        relevanceScore: Double
    ) {
        self.tabId = tabId
        self.summary = summary
        self.codePatterns = codePatterns
        self.relevanceSignals = relevanceSignals
        self.relevanceScore = relevanceScore
    }

    /// Neutral fallback when analysis fails.
    public static func neutral(tabId: Int) -> TabAnalysis {
        TabAnalysis(
            tabId: tabId,
            summary: "Analysis unavailable",
            codePatterns: [],
            relevanceSignals: [],
            relevanceScore: 0.5
        )
    }
}

// MARK: - Tab Agent

/// An AI agent assigned to a single tab. Researches the tab's content and
/// produces a structured analysis including relevance to the user's git context.
public struct TabAgent: Sendable {
    private let client: any LLMClientProtocol
    private let gitContext: GitContext
    private let model: String

    public init(client: any LLMClientProtocol, gitContext: GitContext, model: String) {
        self.client = client
        self.gitContext = gitContext
        self.model = model
    }

    /// Analyze a single tab's content and return a structured analysis.
    public func analyze(tab: TabData) -> TabAnalysis {
        let prompt = buildPrompt(tab: tab)
        do {
            let response = try client.chatCompletion(
                model: model,
                messages: [
                    ChatMessage(role: "system", content: systemPrompt),
                    ChatMessage(role: "user", content: prompt),
                ],
                temperature: 0.2,
                maxTokens: 512
            )
            return parseAnalysis(tabId: tab.tabId, response: response)
        } catch {
            fputs("[TabX Agent] Analysis failed for tab \(tab.tabId): \(error.localizedDescription)\n", stderr)
            return .neutral(tabId: tab.tabId)
        }
    }

    // MARK: - Prompt Construction

    private var systemPrompt: String {
        """
        You are a tab relevance analyst. Given a browser tab's content and the user's \
        git repository context, produce a JSON analysis. Be concise and precise.
        """
    }

    private func buildPrompt(tab: TabData) -> String {
        let branch = gitContext.branch ?? "unknown"
        let files = gitContext.recentFiles.prefix(20).joined(separator: ", ")
        let digest = tab.contentDigest ?? "(no content)"
        let selected = tab.selectedText ?? ""

        return """
        Analyze this browser tab for relevance to the user's current coding work.

        ## Git Context
        Branch: \(branch)
        Recent files: \(files)

        ## Tab
        Title: \(tab.title)
        URL: \(tab.url)
        Content: \(digest)
        Selected text: \(selected)
        Time spent: \(Int(tab.timeSpentSeconds))s
        Scroll depth: \(String(format: "%.0f", tab.scrollDepth * 100))%

        Respond with ONLY a JSON object (no markdown fencing):
        {
          "summary": "1-2 sentence summary of what this tab contains",
          "codePatterns": ["up to 5 code patterns/technologies found"],
          "relevanceSignals": ["up to 5 reasons this tab is or isn't relevant"],
          "relevanceScore": 0.0 to 1.0
        }
        """
    }

    // MARK: - Response Parsing

    private func parseAnalysis(tabId: Int, response: String) -> TabAnalysis {
        // Strip markdown code fences if present
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .neutral(tabId: tabId)
        }

        let summary = json["summary"] as? String ?? "Analysis unavailable"
        let codePatterns = json["codePatterns"] as? [String] ?? []
        let relevanceSignals = json["relevanceSignals"] as? [String] ?? []
        let score = json["relevanceScore"] as? Double ?? 0.5

        return TabAnalysis(
            tabId: tabId,
            summary: summary,
            codePatterns: codePatterns,
            relevanceSignals: relevanceSignals,
            relevanceScore: max(0.0, min(1.0, score))
        )
    }
}
