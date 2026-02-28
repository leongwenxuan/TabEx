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
    func snapshot() -> BundleManagerState
    func restore(_ state: BundleManagerState)
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
    private let sessionManager: SessionManager

    /// Called on the messaging thread after each tab-update scoring round.
    /// Receives the scored results and the original tab data.
    public var onDecisions: (([TabResult], [TabData]) -> Void)?

    public init(
        scorer: (any ScoringEngineProtocol)? = nil,
        bundleGen: (any BundleGeneratorProtocol)? = nil,
        configManager: ConfigManager = ConfigManager(),
        sessionManager: SessionManager = SessionManager()
    ) {
        self.scorer = scorer ?? AgentRunner(
            config: configManager.config.scoring,
            openaiConfig: configManager.config.openai
        )
        self.bundleGen = bundleGen ?? BundleManager(
            config: configManager.config.scoring,
            repoPath: configManager.config.repoPath
        )
        self.configManager = configManager
        self.sessionManager = sessionManager
    }

    /// Processes a single incoming message and returns the reply to send back.
    public func handle(_ message: IncomingMessage) -> OutgoingMessage {
        switch message.type {
        case .ping:
            return OutgoingMessage(type: .pong)

        case .tabUpdate:
            let tabs = message.tabs ?? []
            bundleGen.ingest(tabs, trackIds: true)

            // Detect branch switches via git context embedded in the bundle.
            let bundle = bundleGen.generateBundle()
            let gitContext = GitContext(
                branch: bundle.gitBranch,
                repoPath: bundle.gitRepoPath,
                recentFiles: bundle.openFiles
            )

            var switchPayload: SessionSwitchPayload? = nil
            let event = sessionManager.checkBranchSwitch(gitContext: gitContext)

            if let event {
                // Save outgoing session if the branch was active long enough.
                if event.shouldSaveOutgoing {
                    sessionManager.saveSession(
                        key: event.outgoingKey,
                        repoPath: event.repoPath,
                        branch: event.fromBranch,
                        state: bundleGen.snapshot()
                    )
                }

                // Check if incoming branch has a saved session.
                let incoming = sessionManager.loadSession(key: event.incomingKey)
                switchPayload = SessionSwitchPayload(
                    fromBranch: event.fromBranch,
                    toBranch: event.toBranch,
                    repoPath: event.repoPath,
                    hasSavedSession: incoming != nil,
                    incomingKey: event.incomingKey.rawValue
                )
            }

            // Only score tabs when a branch switch is detected.
            if event != nil {
                let results = scorer.score(tabs: tabs)
                bundleGen.updateResults(results)
                let freshBundle = bundleGen.generateBundle()
                try? BundleStore.saveBundle(freshBundle)
                BundleStore.saveResults(results, tabs: tabs)
                onDecisions?(results, tabs)
                return OutgoingMessage(type: .decisions, results: results, sessionSwitch: switchPayload)
            }

            // No branch switch — persist bundle and raw tab data, no scoring.
            try? BundleStore.saveBundle(bundle)
            BundleStore.saveTabs(tabs)
            return OutgoingMessage(type: .pong)

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

        case .restoreSession:
            guard let keyStr = message.sessionKey else {
                return OutgoingMessage(type: .error, error: "Missing sessionKey")
            }
            let key = WorkspaceKey(rawValue: keyStr)
            guard let session = sessionManager.loadSession(key: key) else {
                return OutgoingMessage(type: .error, error: "Session not found for key \(keyStr)")
            }
            bundleGen.restore(session.toBundleManagerState())
            return OutgoingMessage(type: .pong)

        case .getSessions:
            let index = SessionStore.loadIndex()
            return OutgoingMessage(type: .sessions, sessions: index)
        }
    }
}
