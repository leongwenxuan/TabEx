import XCTest
@testable import TabXHostLib

// MARK: - Mock LLM Client

/// Returns predetermined JSON responses for testing the agent pipeline.
final class MockLLMClient: LLMClientProtocol, @unchecked Sendable {
    var responses: [String] = []
    private var callIndex = 0
    var callCount = 0
    var shouldThrow = false

    func chatCompletion(
        model: String,
        messages: [ChatMessage],
        temperature: Double,
        maxTokens: Int
    ) throws -> String {
        callCount += 1
        if shouldThrow {
            throw OpenAIError.noAPIKey
        }
        guard callIndex < responses.count else {
            return "{}"
        }
        let response = responses[callIndex]
        callIndex += 1
        return response
    }
}

// MARK: - Test Helpers

private func makeTab(
    tabId: Int = 1,
    url: String = "https://example.com",
    title: String = "Example",
    contentDigest: String? = "Some page content about swift programming",
    timeSpent: Double = 60
) -> TabData {
    TabData(
        tabId: tabId,
        url: url,
        title: title,
        timeSpentSeconds: timeSpent,
        scrollDepth: 0.5,
        selectedText: nil,
        contentDigest: contentDigest,
        lastVisitedAt: Date(),
        isActive: false
    )
}

private func makeBundle() -> ContextBundle {
    ContextBundle(
        generatedAt: Date(),
        gitBranch: "main",
        gitRepoPath: "/tmp/repo",
        pagesRead: [],
        survivingTabs: [],
        openFiles: ["Sources/main.swift"],
        taskDescription: "test task"
    )
}

// MARK: - AgentRunner Tests

final class AgentRunnerTests: XCTestCase {

    func testFallbackWhenNoAPIKey() {
        // AgentRunner with no API key should use token-matching fallback.
        let runner = AgentRunner(
            config: .default,
            openaiConfig: OpenAIConfig(apiKey: "")
        )
        let tabs = [makeTab(tabId: 1), makeTab(tabId: 2)]
        let results = runner.score(tabs: tabs)
        XCTAssertEqual(results.count, 2)
        for result in results {
            // Should still produce valid results via fallback.
            XCTAssertGreaterThanOrEqual(result.score, 0.0)
            XCTAssertLessThanOrEqual(result.score, 1.0)
        }
    }

    func testSafelistedTabsAlwaysKeep() {
        let config = ScoringConfig(safelist: ["example.com"])
        let runner = AgentRunner(
            config: config,
            openaiConfig: OpenAIConfig(apiKey: "")
        )
        let tab = makeTab(tabId: 1, url: "https://example.com/page")
        let results = runner.score(tabs: [tab])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].decision, .keep)
        XCTAssertEqual(results[0].score, 1.0)
        XCTAssertEqual(results[0].reason, "safelisted")
    }

    func testAgentRunnerWithMockClient() {
        let mock = MockLLMClient()
        // Agent response for 1 tab
        mock.responses = [
            // Tab agent analysis
            """
            {
              "summary": "Swift programming tutorial",
              "codePatterns": ["Swift", "UIKit"],
              "relevanceSignals": ["Directly related to current branch"],
              "relevanceScore": 0.8
            }
            """,
            // Judge response
            """
            [
              {
                "tabId": 1,
                "score": 0.85,
                "reason": "Highly relevant to current work",
                "insights": ["Swift tutorial", "UIKit patterns", "Relevant to branch"]
              }
            ]
            """,
        ]

        let runner = AgentRunner(
            config: .default,
            openaiConfig: OpenAIConfig(apiKey: "test-key"),
            client: mock
        )
        let results = runner.score(tabs: [makeTab(tabId: 1)])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].tabId, 1)
        XCTAssertEqual(results[0].decision, .keep)
        XCTAssertGreaterThan(results[0].score, 0.6)
        XCTAssertNotNil(results[0].summary)
        XCTAssertNotNil(results[0].insights)
        XCTAssertEqual(mock.callCount, 2) // 1 agent + 1 judge
    }
}

// MARK: - TabAgent Tests

final class TabAgentTests: XCTestCase {

    func testAnalyzeReturnsStructuredResult() {
        let mock = MockLLMClient()
        mock.responses = [
            """
            {
              "summary": "React hooks documentation",
              "codePatterns": ["React", "useState", "useEffect"],
              "relevanceSignals": ["Frontend framework docs"],
              "relevanceScore": 0.7
            }
            """,
        ]

        let agent = TabAgent(
            client: mock,
            gitContext: GitContext(branch: "feature/hooks", repoPath: "/tmp", recentFiles: []),
            model: "gpt-4o-mini"
        )
        let tab = makeTab(title: "React Hooks Docs", contentDigest: "React hooks documentation page")
        let analysis = agent.analyze(tab: tab)
        XCTAssertEqual(analysis.tabId, tab.tabId)
        XCTAssertEqual(analysis.summary, "React hooks documentation")
        XCTAssertFalse(analysis.codePatterns.isEmpty)
        XCTAssertEqual(analysis.relevanceScore, 0.7, accuracy: 0.01)
    }

    func testAnalyzeHandlesInvalidJSON() {
        let mock = MockLLMClient()
        mock.responses = ["This is not JSON at all"]

        let agent = TabAgent(
            client: mock,
            gitContext: GitContext(branch: "main", repoPath: "/tmp", recentFiles: []),
            model: "gpt-4o-mini"
        )
        let analysis = agent.analyze(tab: makeTab())
        // Should return neutral analysis
        XCTAssertEqual(analysis.summary, "Analysis unavailable")
        XCTAssertEqual(analysis.relevanceScore, 0.5, accuracy: 0.01)
    }

    func testAnalyzeHandlesAPIError() {
        let mock = MockLLMClient()
        mock.shouldThrow = true

        let agent = TabAgent(
            client: mock,
            gitContext: GitContext(branch: "main", repoPath: "/tmp", recentFiles: []),
            model: "gpt-4o-mini"
        )
        let analysis = agent.analyze(tab: makeTab())
        XCTAssertEqual(analysis.summary, "Analysis unavailable")
        XCTAssertEqual(analysis.relevanceScore, 0.5, accuracy: 0.01)
    }

    func testAnalyzeStripsMarkdownFencing() {
        let mock = MockLLMClient()
        mock.responses = [
            """
            ```json
            {
              "summary": "API documentation",
              "codePatterns": [],
              "relevanceSignals": [],
              "relevanceScore": 0.6
            }
            ```
            """,
        ]

        let agent = TabAgent(
            client: mock,
            gitContext: GitContext(branch: "main", repoPath: "/tmp", recentFiles: []),
            model: "gpt-4o-mini"
        )
        let analysis = agent.analyze(tab: makeTab())
        XCTAssertEqual(analysis.summary, "API documentation")
        XCTAssertEqual(analysis.relevanceScore, 0.6, accuracy: 0.01)
    }
}

// MARK: - ArenaJudge Tests

final class ArenaJudgeTests: XCTestCase {

    func testJudgeReturnsRankedResults() {
        let mock = MockLLMClient()
        mock.responses = [
            """
            [
              {"tabId": 1, "score": 0.9, "reason": "Direct match", "insights": ["Key resource"]},
              {"tabId": 2, "score": 0.2, "reason": "Unrelated", "insights": ["Not relevant"]}
            ]
            """,
        ]

        let judge = ArenaJudge(
            client: mock,
            gitContext: GitContext(branch: "main", repoPath: "/tmp", recentFiles: []),
            config: .default,
            model: "gpt-4o"
        )
        let analyses = [
            TabAnalysis(tabId: 1, summary: "Swift docs", codePatterns: [], relevanceSignals: [], relevanceScore: 0.8),
            TabAnalysis(tabId: 2, summary: "Cooking recipes", codePatterns: [], relevanceSignals: [], relevanceScore: 0.2),
        ]
        let tabs = [makeTab(tabId: 1), makeTab(tabId: 2, url: "https://cooking.com")]
        let results = judge.judge(analyses: analyses, tabs: tabs)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].decision, .keep)
        XCTAssertEqual(results[1].decision, .close)
    }

    func testJudgeFallbackOnAPIError() {
        let mock = MockLLMClient()
        mock.shouldThrow = true

        let judge = ArenaJudge(
            client: mock,
            gitContext: GitContext(branch: "main", repoPath: "/tmp", recentFiles: []),
            config: .default,
            model: "gpt-4o"
        )
        let analyses = [
            TabAnalysis(tabId: 1, summary: "Test", codePatterns: [], relevanceSignals: ["signal"], relevanceScore: 0.8),
        ]
        let results = judge.judge(analyses: analyses, tabs: [makeTab()])
        XCTAssertEqual(results.count, 1)
        // Fallback uses agent's self-assessed score
        XCTAssertEqual(results[0].score, 0.8, accuracy: 0.01)
        XCTAssertEqual(results[0].decision, .keep)
        XCTAssertTrue(results[0].reason.contains("judge unavailable"))
    }

    func testJudgeHandlesInvalidJSON() {
        let mock = MockLLMClient()
        mock.responses = ["not json"]

        let judge = ArenaJudge(
            client: mock,
            gitContext: GitContext(branch: "main", repoPath: "/tmp", recentFiles: []),
            config: .default,
            model: "gpt-4o"
        )
        let analyses = [
            TabAnalysis(tabId: 1, summary: "Test", codePatterns: [], relevanceSignals: [], relevanceScore: 0.4),
        ]
        let results = judge.judge(analyses: analyses, tabs: [makeTab()])
        XCTAssertEqual(results.count, 1)
        // Falls back to agent's self-assessed score
        XCTAssertEqual(results[0].score, 0.4, accuracy: 0.01)
        XCTAssertEqual(results[0].decision, .flag) // 0.4 is between close(0.3) and keep(0.6)
    }
}

// MARK: - Existing Tests (Preserved)

final class DecisionThresholdTests: XCTestCase {

    func testDecisionThresholdsClose() {
        let t = DecisionThresholds(close: 0.3, keep: 0.6)
        XCTAssertEqual(t.decide(score: 0.1), .close)
    }

    func testDecisionThresholdsKeep() {
        let t = DecisionThresholds(close: 0.3, keep: 0.6)
        XCTAssertEqual(t.decide(score: 0.8), .keep)
    }

    func testDecisionThresholdsFlag() {
        let t = DecisionThresholds(close: 0.3, keep: 0.6)
        XCTAssertEqual(t.decide(score: 0.45), .flag)
    }
}

final class SignalWeightsTests: XCTestCase {

    func testSignalWeightsDefaultSumToOne() {
        let w = SignalWeights.default
        XCTAssertTrue(w.isValid)
    }
}

final class BundleFormatterTests: XCTestCase {

    func testBundleFormatterJSON() throws {
        let bundle = makeBundle()
        let json = try BundleFormatter.json(bundle)
        XCTAssertTrue(json.contains("generatedAt"))
    }

    func testBundleFormatterMarkdown() {
        let bundle = makeBundle()
        let md = BundleFormatter.markdown(bundle)
        XCTAssertTrue(md.contains("# TabX Context Bundle"))
    }
}

final class CLIHandlerTests: XCTestCase {

    func testCLIHandlerHelpReturnsZero() {
        var handler = CLIHandler()
        XCTAssertEqual(handler.run(arguments: ["--help"]), 0)
    }

    func testCLIHandlerVersionReturnsZero() {
        var handler = CLIHandler()
        XCTAssertEqual(handler.run(arguments: ["--version"]), 0)
    }

    func testCLIHandlerUnknownReturnsOne() {
        var handler = CLIHandler()
        XCTAssertEqual(handler.run(arguments: ["--unknown-flag"]), 1)
    }

    func testCLIHandlerSetKeyRequiresArg() {
        var handler = CLIHandler()
        XCTAssertEqual(handler.run(arguments: ["--set-key"]), 1)
    }
}

// MARK: - TabResult Tests

final class TabResultTests: XCTestCase {

    func testTabResultBackwardCompat() throws {
        // TabResult with nil summary/insights should encode without those keys
        let result = TabResult(tabId: 1, decision: .keep, score: 0.8, reason: "test")
        let encoder = JSONEncoder()
        let data = try encoder.encode(result)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["tabId"] as? Int, 1)
    }

    func testTabResultWithAgentFields() throws {
        let result = TabResult(
            tabId: 1, decision: .keep, score: 0.9, reason: "agent",
            summary: "Test summary", insights: ["insight1", "insight2"]
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(result)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["summary"] as? String, "Test summary")
        XCTAssertEqual((json?["insights"] as? [String])?.count, 2)
    }
}
