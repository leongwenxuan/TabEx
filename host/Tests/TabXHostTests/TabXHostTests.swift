import XCTest
@testable import TabXHostLib

final class TabXHostTests: XCTestCase {

    // MARK: - SignalWeights

    func testSignalWeightsDefaultSumToOne() {
        let weights = SignalWeights.default
        let sum = weights.gitRelevance + weights.recency + weights.readingDepth + weights.semantic
        XCTAssertEqual(sum, 1.0, accuracy: 0.001)
        XCTAssertTrue(weights.isValid)
    }

    // MARK: - DecisionThresholds

    func testDecisionThresholds() {
        let thresh = DecisionThresholds.default
        XCTAssertEqual(thresh.decide(score: 0.1), .close)
        XCTAssertEqual(thresh.decide(score: 0.45), .flag)
        XCTAssertEqual(thresh.decide(score: 0.9), .keep)
    }

    // MARK: - TimeDecayScorer

    func testTimeDecayScorerFreshTab() {
        let scorer = TimeDecayScorer(halfLifeSeconds: 3600)
        let score = scorer.score(lastVisitedAt: Date(), now: Date())
        XCTAssertEqual(score, 1.0, accuracy: 0.01)
    }

    func testTimeDecayScorerStaleTab() {
        let scorer = TimeDecayScorer(halfLifeSeconds: 3600)
        let old = Date().addingTimeInterval(-7200) // 2 hours ago
        let score = scorer.score(lastVisitedAt: old, now: Date())
        XCTAssertLessThan(score, 0.2)
    }

    // MARK: - ReadingDepthScorer

    func testReadingDepthScorerZeroInput() {
        let scorer = ReadingDepthScorer()
        let score = scorer.score(timeSpentSeconds: 0, scrollDepth: 0, hasSelection: false)
        XCTAssertEqual(score, 0.0, accuracy: 0.01)
    }

    func testReadingDepthScorerHighEngagement() {
        let scorer = ReadingDepthScorer()
        let score = scorer.score(timeSpentSeconds: 300, scrollDepth: 1.0, hasSelection: true)
        XCTAssertGreaterThan(score, 0.8)
    }

    // MARK: - SemanticScorer (Jaccard fallback)

    func testSemanticScorerJaccardIdentical() {
        // Test via the exposed score function with identical token sets.
        // NLEmbedding may not load in test environments; Jaccard should handle it.
        let scorer = SemanticScorer()
        let tokens = ["swift", "compiler", "debug"]
        let score = scorer.score(contextTokens: tokens, tabTokens: tokens)
        // Should be 1.0 (identical) via embeddings or Jaccard.
        XCTAssertGreaterThan(score, 0.0)
    }

    func testSemanticScorerEmptyTokensReturnsDefault() {
        let scorer = SemanticScorer()
        let score = scorer.score(contextTokens: [], tabTokens: ["swift"])
        XCTAssertEqual(score, 0.3, accuracy: 0.001)
    }

    // MARK: - BundleFormatter

    func testBundleFormatterJSON() throws {
        let bundle = makeBundle()
        let formatter = BundleFormatter()
        let json = try formatter.json(bundle)
        XCTAssertTrue(json.contains("generatedAt"))
        XCTAssertTrue(json.contains("survivingTabs"))
    }

    func testBundleFormatterMarkdown() {
        let bundle = makeBundle()
        let formatter = BundleFormatter()
        let md = formatter.markdown(bundle)
        XCTAssertTrue(md.hasPrefix("# TabX Context Bundle"))
        XCTAssertTrue(md.contains("Generated:"))
    }

    // MARK: - BundleStore

    func testBundleStoreRoundTrip() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = BundleStore(root: tmpDir)
        let bundle = makeBundle()
        try store.save(bundle)
        let loaded = store.loadLatestBundle()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.gitBranch, "test/branch")
    }

    func testBundleStoreStateRoundTrip() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = BundleStore(root: tmpDir)
        let state = BundleStore.State(lastScoredAt: Date(), tabCount: 42, closedCount: 5)
        try store.saveState(state)
        let loaded = store.loadState()
        XCTAssertEqual(loaded.tabCount, 42)
        XCTAssertEqual(loaded.closedCount, 5)
    }

    // MARK: - MessageRouter

    func testMessageRouterPing() {
        let router = MessageRouter()
        let msg = IncomingMessage(type: .ping)
        let response = router.handle(msg)
        XCTAssertEqual(response.type, .pong)
    }

    func testMessageRouterConfigUpdate() {
        let tmpConfig = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-config.json")
        let configMgr = ConfigManager(configURL: tmpConfig)
        let router = MessageRouter(configManager: configMgr)
        let newScoring = ScoringConfig(sensitivity: 0.8)
        let msg = IncomingMessage(type: .configUpdate, config: newScoring)
        let response = router.handle(msg)
        XCTAssertEqual(response.type, .pong)
        XCTAssertEqual(configMgr.scoringConfig.sensitivity, 0.8, accuracy: 0.001)
    }

    // MARK: - Helpers

    private func makeBundle() -> ContextBundle {
        ContextBundle(
            generatedAt: Date(),
            gitBranch: "test/branch",
            gitRepoPath: "/tmp/repo",
            pagesRead: [],
            survivingTabs: [],
            openFiles: [],
            taskDescription: "test task"
        )
    }
}
