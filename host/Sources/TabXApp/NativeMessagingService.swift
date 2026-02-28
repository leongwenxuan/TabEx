import Foundation
import Darwin
import TabXHostLib

/// Runs the Chrome native-messaging loop on a background thread.
/// Activates only when stdin is a pipe (i.e., launched by Chrome, not interactively).
final class NativeMessagingService {
    private let appState: AppState
    private let router: MessageRouter

    init(appState: AppState) {
        self.appState = appState
        let configManager = ConfigManager()
        let runner = AgentRunner(
            config: configManager.config.scoring,
            openaiConfig: configManager.config.openai
        )

        // Wire arena progress callbacks to the UI state.
        runner.arenaCallbacks = ArenaCallbacks(
            onArenaStarted: { [weak appState] tabs in
                DispatchQueue.main.async { appState?.arenaStarted(tabs: tabs) }
            },
            onAgentStarted: { [weak appState] tabId in
                DispatchQueue.main.async { appState?.agentStarted(tabId: tabId) }
            },
            onAgentCompleted: { [weak appState] tabId, score, summary in
                DispatchQueue.main.async { appState?.agentCompleted(tabId: tabId, score: score, summary: summary) }
            },
            onJudgeStarted: { [weak appState] in
                DispatchQueue.main.async { appState?.judgeStarted() }
            }
        )

        let r = MessageRouter(scorer: runner, configManager: configManager)
        r.onDecisions = { [weak appState] results, tabs in
            DispatchQueue.main.async {
                appState?.applyDecisions(results, tabs: tabs)
            }
        }
        self.router = r
    }

    /// Starts the messaging loop only if stdin is a pipe (Chrome-invoked scenario).
    func startIfPiped() {
        guard isatty(STDIN_FILENO) == 0 else { return }
        start()
    }

    /// Unconditionally starts the messaging loop on a background thread.
    func start() {
        let thread = Thread { [weak self] in self?.runLoop() }
        thread.name = "tabx-native-messaging"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    // MARK: - Private

    private func runLoop() {
        let io = NativeMessagingIO()
        while true {
            guard let message = io.readMessage() else {
                // EOF — Chrome closed the pipe. Leave the menu bar running.
                break
            }
            let reply = router.handle(message)
            do {
                try io.writeMessage(reply)
            } catch {
                fputs("TabXApp: native-messaging write error: \(error)\n", stderr)
                break
            }
        }
    }
}
