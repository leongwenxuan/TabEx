import Foundation

// MARK: - Protocols

/// Abstracts the scoring subsystem for testing / mocking.
public protocol ScoringEngineProtocol: Sendable {
    func score(tabs: [TabData]) -> [TabResult]
    func updateConfig(_ config: ScoringConfig)
}

/// Abstracts the bundle generation subsystem.
public protocol BundleGeneratorProtocol: Sendable {
    func ingest(_ tabs: [TabData], trackIds: Bool)
    func updateResults(_ results: [TabResult])
    func generateBundle() -> ContextBundle
}

// MARK: - Conformances

extension BundleManager: BundleGeneratorProtocol {}

// MARK: - MessageRouter

/// Dispatches incoming native-messaging messages to the appropriate subsystem
/// and returns the outgoing reply.
public final class MessageRouter {
    private let scorer: any ScoringEngineProtocol
    private let bundleGen: any BundleGeneratorProtocol
    private let configManager: ConfigManager

    /// Called on the messaging thread after each tab-update scoring round.
    /// Receives the scored results and the original tab data.
    public var onDecisions: (([TabResult], [TabData]) -> Void)?

    public init(
        scorer: (any ScoringEngineProtocol)? = nil,
        bundleGen: any BundleGeneratorProtocol = BundleManager(),
        configManager: ConfigManager = ConfigManager()
    ) {
        self.scorer = scorer ?? AgentRunner(
            config: configManager.config.scoring,
            openaiConfig: configManager.config.openai
        )
        self.bundleGen = bundleGen
        self.configManager = configManager
    }

    /// Processes a single incoming message and returns the reply to send back.
    public func handle(_ message: IncomingMessage) -> OutgoingMessage {
        switch message.type {
        case .ping:
            return OutgoingMessage(type: .pong)

        case .tabUpdate:
            let tabs = message.tabs ?? []
            bundleGen.ingest(tabs, trackIds: true)
            let results = scorer.score(tabs: tabs)
            bundleGen.updateResults(results)
            // Persist bundle and results after each scoring round.
            let bundle = bundleGen.generateBundle()
            try? BundleStore.saveBundle(bundle)
            BundleStore.saveResults(results, tabs: tabs)
            onDecisions?(results, tabs)
            return OutgoingMessage(type: .decisions, results: results)

        case .requestBundle:
            let bundle = bundleGen.generateBundle()
            try? BundleStore.saveBundle(bundle)
            return OutgoingMessage(type: .bundle, bundle: bundle)

        case .configUpdate:
            if let newConfig = message.config {
                scorer.updateConfig(newConfig)
                configManager.apply(scoringUpdate: newConfig)
                try? configManager.save()
            }
            return OutgoingMessage(type: .pong)
        }
    }
}
