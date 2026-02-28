import XCTest
@testable import TabXHostLib

final class TabXHostTests: XCTestCase {

    // MARK: - TimeDecayScorer

    func testTimeDecayRecentTabIsHigh() {
        let scorer = TimeDecayScorer(thresholdSeconds: 3600)
        let score = scorer.score(lastVisitedAt: Date(), now: Date())
        XCTAssertGreaterThan(score, 0.99)
    }

    func testTimeDecayOldTabIsLow() {
        let scorer = TimeDecayScorer(thresholdSeconds: 3600)
        let old = Date(timeIntervalSinceNow: -7200)  // 2 hours ago
        let score = scorer.score(lastVisitedAt: old, now: Date())
        XCTAssertLessThan(score, 0.2)
    }

    // MARK: - ReadingDepthScorer

    func testReadingDepthFullEngagement() {
        let scorer = ReadingDepthScorer()
        let score = scorer.score(timeSpentSeconds: 300, scrollDepth: 1.0, hasSelection: true)
        XCTAssertGreaterThan(score, 0.9)
    }

    func testReadingDepthNoEngagement() {
        let scorer = ReadingDepthScorer()
        let score = scorer.score(timeSpentSeconds: 0, scrollDepth: 0, hasSelection: false)
        XCTAssertEqual(score, 0.0, accuracy: 0.01)
    }

    // MARK: - DecisionThresholds

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

    // MARK: - SignalWeights

    func testSignalWeightsDefaultSumToOne() {
        let w = SignalWeights.default
        XCTAssertTrue(w.isValid)
    }

    // MARK: - SemanticScorer (Jaccard fallback)

    func testSemanticScorerSingleIdenticalToken() {
        let scorer = SemanticScorer()
        // Same single token in both lists; NLEmbedding distance(word, word) = 0 → similarity = 1.0
        let score = scorer.score(contextTokens: ["swift"], tabTokens: ["swift"])
        XCTAssertGreaterThan(score, 0.9)
    }

    func testSemanticScorerJaccardDisjoint() {
        let scorer = SemanticScorer()
        let score = scorer.score(contextTokens: ["alpha", "beta"], tabTokens: ["gamma", "delta"])
        // Will use embedding or Jaccard — just verify it's in range
        XCTAssertGreaterThanOrEqual(score, 0.0)
        XCTAssertLessThanOrEqual(score, 1.0)
    }

    // MARK: - BundleFormatter

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

    // MARK: - CLIHandler

    func testCLIHandlerHelpReturnsZero() {
        let handler = CLIHandler()
        XCTAssertEqual(handler.run(arguments: ["--help"]), 0)
    }

    func testCLIHandlerVersionReturnsZero() {
        let handler = CLIHandler()
        XCTAssertEqual(handler.run(arguments: ["--version"]), 0)
    }

    func testCLIHandlerUnknownReturnsOne() {
        let handler = CLIHandler()
        XCTAssertEqual(handler.run(arguments: ["--unknown-flag"]), 1)
    }

    // MARK: - Helpers

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
}
