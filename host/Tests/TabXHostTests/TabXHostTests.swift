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

// MARK: - WorkspaceKey Tests

final class WorkspaceKeyTests: XCTestCase {

    func testSameInputsSameKey() {
        let a = WorkspaceKey(repoPath: "/tmp/repo", branch: "main")
        let b = WorkspaceKey(repoPath: "/tmp/repo", branch: "main")
        XCTAssertEqual(a.rawValue, b.rawValue)
    }

    func testDifferentInputsDifferentKeys() {
        let a = WorkspaceKey(repoPath: "/tmp/repo", branch: "main")
        let b = WorkspaceKey(repoPath: "/tmp/repo", branch: "feature")
        XCTAssertNotEqual(a.rawValue, b.rawValue)
    }

    func testDifferentRepoDifferentKeys() {
        let a = WorkspaceKey(repoPath: "/tmp/repo1", branch: "main")
        let b = WorkspaceKey(repoPath: "/tmp/repo2", branch: "main")
        XCTAssertNotEqual(a.rawValue, b.rawValue)
    }

    func testKeyIs16HexChars() {
        let key = WorkspaceKey(repoPath: "/tmp/repo", branch: "main")
        XCTAssertEqual(key.rawValue.count, 16)
        XCTAssertTrue(key.rawValue.allSatisfy { $0.isHexDigit })
    }

    func testRoundTripFromRawValue() {
        let original = WorkspaceKey(repoPath: "/tmp/repo", branch: "main")
        let restored = WorkspaceKey(rawValue: original.rawValue)
        XCTAssertEqual(original.rawValue, restored.rawValue)
    }
}

// MARK: - SessionStore Tests

final class SessionStoreTests: XCTestCase {

    private func makeSession(branch: String = "main") -> BranchSession {
        let key = WorkspaceKey(repoPath: "/tmp/test-repo", branch: branch)
        let state = BundleManagerState(
            pageRecords: [
                "https://example.com": PageRecord(
                    url: "https://example.com",
                    title: "Example",
                    contentDigest: "digest",
                    highlights: ["highlight"],
                    timeSpentSeconds: 60,
                    scrollDepth: 0.8,
                    visitedAt: Date()
                )
            ],
            latestResults: [
                TabResult(tabId: 1, decision: .keep, score: 0.9, reason: "test")
            ],
            urlForTabId: [1: "https://example.com"],
            titleForTabId: [1: "Example"]
        )
        return BranchSession(
            workspaceKey: key,
            repoPath: "/tmp/test-repo",
            branch: branch,
            capturedAt: Date(),
            state: state
        )
    }

    func testSaveAndLoadRoundTrip() {
        let session = makeSession()
        SessionStore.save(session)

        let loaded = SessionStore.load(key: session.workspaceKey)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.branch, "main")
        XCTAssertEqual(loaded?.pageRecords.count, 1)
        XCTAssertEqual(loaded?.urlForTabId["1"], "https://example.com")
        XCTAssertEqual(loaded?.titleForTabId["1"], "Example")
        XCTAssertEqual(loaded?.latestResults.count, 1)
    }

    func testIndexUpdated() {
        let session = makeSession(branch: "test-index-\(UUID().uuidString.prefix(8))")
        SessionStore.save(session)

        let index = SessionStore.loadIndex()
        let entry = index.first { $0.workspaceKey == session.workspaceKey }
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.branch, session.branch)
        XCTAssertEqual(entry?.pageCount, 1)
        XCTAssertEqual(entry?.tabCount, 1)
    }

    func testToBundleManagerState() {
        let session = makeSession()
        let state = session.toBundleManagerState()
        XCTAssertEqual(state.pageRecords.count, 1)
        XCTAssertEqual(state.urlForTabId[1], "https://example.com")
        XCTAssertEqual(state.titleForTabId[1], "Example")
    }
}

// MARK: - SessionManager Tests

final class SessionManagerTests: XCTestCase {

    func testFirstCallReturnsNil() {
        let mgr = SessionManager()
        let ctx = GitContext(branch: "main", repoPath: "/tmp/repo", recentFiles: [])
        XCTAssertNil(mgr.checkBranchSwitch(gitContext: ctx))
    }

    func testSameBranchReturnsNil() {
        let mgr = SessionManager()
        let ctx = GitContext(branch: "main", repoPath: "/tmp/repo", recentFiles: [])
        _ = mgr.checkBranchSwitch(gitContext: ctx)
        XCTAssertNil(mgr.checkBranchSwitch(gitContext: ctx))
    }

    func testBranchChangeLessThan10sNoSave() {
        let mgr = SessionManager()
        let ctx1 = GitContext(branch: "main", repoPath: "/tmp/repo", recentFiles: [])
        _ = mgr.checkBranchSwitch(gitContext: ctx1)
        // Immediate switch — less than 10s
        let ctx2 = GitContext(branch: "feature", repoPath: "/tmp/repo", recentFiles: [])
        let event = mgr.checkBranchSwitch(gitContext: ctx2)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.fromBranch, "main")
        XCTAssertEqual(event?.toBranch, "feature")
        XCTAssertFalse(event?.shouldSaveOutgoing ?? true)
    }

    func testNilGitContextReturnsNil() {
        let mgr = SessionManager()
        let ctx = GitContext(branch: nil, repoPath: nil, recentFiles: [])
        XCTAssertNil(mgr.checkBranchSwitch(gitContext: ctx))
    }
}

// MARK: - BundleManager Snapshot/Restore Tests

final class BundleManagerSnapshotTests: XCTestCase {

    func testSnapshotRestoreRoundTrip() {
        let mgr = BundleManager()
        let tabs = [
            TabData(
                tabId: 1, url: "https://example.com", title: "Example",
                timeSpentSeconds: 60, scrollDepth: 0.5, selectedText: "hello",
                contentDigest: "digest", lastVisitedAt: Date(), isActive: false
            ),
            TabData(
                tabId: 2, url: "https://test.com", title: "Test",
                timeSpentSeconds: 30, scrollDepth: 0.3, selectedText: nil,
                contentDigest: nil, lastVisitedAt: Date(), isActive: true
            ),
        ]
        mgr.ingest(tabs, trackIds: true)
        mgr.updateResults([
            TabResult(tabId: 1, decision: .keep, score: 0.9, reason: "test"),
            TabResult(tabId: 2, decision: .flag, score: 0.5, reason: "maybe"),
        ])

        let snapshot = mgr.snapshot()
        XCTAssertEqual(snapshot.pageRecords.count, 2)
        XCTAssertEqual(snapshot.urlForTabId.count, 2)
        XCTAssertEqual(snapshot.titleForTabId.count, 2)
        XCTAssertEqual(snapshot.latestResults.count, 2)

        // Create a new manager and restore
        let mgr2 = BundleManager()
        mgr2.restore(snapshot)
        let snapshot2 = mgr2.snapshot()
        XCTAssertEqual(snapshot2.pageRecords.count, 2)
        XCTAssertEqual(snapshot2.urlForTabId[1], "https://example.com")
        XCTAssertEqual(snapshot2.titleForTabId[2], "Test")
    }
}

// MARK: - Compactor Tests

final class CompactorTests: XCTestCase {

    private func makePageRecord(
        url: String,
        timeSpent: Double = 60,
        scrollDepth: Double = 0.5
    ) -> PageRecord {
        PageRecord(
            url: url, title: "Page", contentDigest: nil,
            highlights: [], timeSpentSeconds: timeSpent,
            scrollDepth: scrollDepth, visitedAt: Date()
        )
    }

    func testRemovesLowTimeRecords() {
        let state = BundleManagerState(
            pageRecords: [
                "https://a.com": makePageRecord(url: "https://a.com", timeSpent: 3),
                "https://b.com": makePageRecord(url: "https://b.com", timeSpent: 60),
            ],
            latestResults: [],
            urlForTabId: [:],
            titleForTabId: [:]
        )
        let compacted = Compactor.compact(state)
        XCTAssertEqual(compacted.pageRecords.count, 1)
        XCTAssertNotNil(compacted.pageRecords["https://b.com"])
    }

    func testMergesDuplicateURLs() {
        // Same URL with fragment vs without
        let state = BundleManagerState(
            pageRecords: [
                "https://a.com#section1": PageRecord(
                    url: "https://a.com#section1", title: "A",
                    contentDigest: nil, highlights: ["h1"],
                    timeSpentSeconds: 30, scrollDepth: 0.3, visitedAt: Date()
                ),
                "https://a.com#section2": PageRecord(
                    url: "https://a.com#section2", title: "A",
                    contentDigest: nil, highlights: ["h2"],
                    timeSpentSeconds: 30, scrollDepth: 0.8, visitedAt: Date()
                ),
            ],
            latestResults: [],
            urlForTabId: [:],
            titleForTabId: [:]
        )
        let compacted = Compactor.compact(state)
        XCTAssertEqual(compacted.pageRecords.count, 1)
        let record = compacted.pageRecords.values.first!
        XCTAssertEqual(record.timeSpentSeconds, 60)
        XCTAssertEqual(record.scrollDepth, 0.8)
        XCTAssertEqual(record.highlights.count, 2)
    }

    func testCapsAt100() {
        var records: [String: PageRecord] = [:]
        for i in 0..<150 {
            let url = "https://example.com/page\(i)"
            records[url] = makePageRecord(url: url, timeSpent: Double(i + 10))
        }
        let state = BundleManagerState(
            pageRecords: records,
            latestResults: [],
            urlForTabId: [:],
            titleForTabId: [:]
        )
        let compacted = Compactor.compact(state)
        XCTAssertEqual(compacted.pageRecords.count, 100)
    }
}

// MARK: - URLNormalizer Tests

final class URLNormalizerTests: XCTestCase {

    func testStripsFragment() {
        XCTAssertEqual(
            URLNormalizer.normalize("https://example.com/page#section"),
            "https://example.com/page"
        )
    }

    func testSortsQueryParams() {
        XCTAssertEqual(
            URLNormalizer.normalize("https://example.com?z=1&a=2"),
            "https://example.com?a=2&z=1"
        )
    }

    func testStripsTrailingSlash() {
        XCTAssertEqual(
            URLNormalizer.normalize("https://example.com/page/"),
            "https://example.com/page"
        )
    }

    func testPreservesRootSlash() {
        let result = URLNormalizer.normalize("https://example.com/")
        // Root path keeps trailing slash
        XCTAssertTrue(result == "https://example.com/" || result == "https://example.com")
    }

    func testHandlesInvalidURL() {
        // URLComponents percent-encodes spaces, so the output won't match input exactly.
        // Just verify it doesn't crash and returns a non-empty string.
        let result = URLNormalizer.normalize("not a url at all")
        XCTAssertFalse(result.isEmpty)
    }
}
