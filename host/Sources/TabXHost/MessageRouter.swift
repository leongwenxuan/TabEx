import Foundation

// MARK: - Protocols

/// Abstraction for components that score tabs.
public protocol ScoringEngineProtocol: AnyObject {
    func score(tabs: [TabData]) -> [TabResult]
    func updateConfig(_ newConfig: ScoringConfig)
    func refreshGitContext()
}

/// Abstraction for components that generate context bundles.
public protocol BundleGeneratorProtocol: AnyObject {
    func ingest(_ tabs: [TabData])
    func ingest(_ tabs: [TabData], trackIds: Bool)
    func updateResults(_ results: [TabResult])
    func generateBundle() -> ContextBundle
}

// MARK: - Conformances

extension ScoringEngine: ScoringEngineProtocol {}
extension BundleManager: BundleGeneratorProtocol {}

// MARK: - Router

/// Routes incoming native-messaging messages to the appropriate handler and writes responses.
///
/// Lifecycle:
///   1. Receive `IncomingMessage` from `NativeMessagingIO.readMessage()`
///   2. Route to `handle(_:)` → produces an `OutgoingMessage`
///   3. Caller writes the response via `NativeMessagingIO.writeMessage(_:)`
public final class MessageRouter {
    private let scorer: ScoringEngineProtocol
    private let bundler: BundleGeneratorProtocol
    private let configManager: ConfigManager

    public init(
        scorer: ScoringEngineProtocol = ScoringEngine(),
        bundler: BundleGeneratorProtocol = BundleManager(),
        configManager: ConfigManager = .shared
    ) {
        self.scorer = scorer
        self.bundler = bundler
        self.configManager = configManager
    }

    /// Processes one incoming message and returns the response to send back.
    public func handle(_ message: IncomingMessage) -> OutgoingMessage {
        switch message.type {
        case .ping:
            return OutgoingMessage(type: .pong)

        case .tabUpdate:
            let tabs = message.tabs ?? []
            bundler.ingest(tabs, trackIds: true)
            let results = scorer.score(tabs: tabs)
            bundler.updateResults(results)
            return OutgoingMessage(type: .decisions, results: results)

        case .requestBundle:
            let bundle = bundler.generateBundle()
            try? BundleStore.shared.save(bundle)
            return OutgoingMessage(type: .bundle, bundle: bundle)

        case .configUpdate:
            if let newConfig = message.config {
                scorer.updateConfig(newConfig)
                try? configManager.updateScoring(newConfig)
            }
            return OutgoingMessage(type: .pong)
        }
    }
}
