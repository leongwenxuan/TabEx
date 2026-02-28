import Foundation

/// Tracks the current branch and orchestrates session save/restore on branch switches.
public final class SessionManager {

    /// Minimum time a branch must be active before saving a session on switch-away.
    private static let minimumBranchDuration: TimeInterval = 10

    private var lastKnownBranch: String?
    private var lastKnownRepoPath: String?
    private var lastBranchStartedAt: Date?

    public init() {}

    // MARK: - Branch switch detection

    /// Information about a detected branch switch.
    public struct SwitchEvent {
        public let fromBranch: String
        public let toBranch: String
        public let repoPath: String
        public let outgoingKey: WorkspaceKey
        public let incomingKey: WorkspaceKey
        /// True if the outgoing branch was active long enough to warrant saving.
        public let shouldSaveOutgoing: Bool
    }

    /// Call on each `tab_update` with the current git context.
    /// Returns nil on the first call, when the branch hasn't changed, or when git context is unavailable.
    public func checkBranchSwitch(gitContext: GitContext) -> SwitchEvent? {
        guard let branch = gitContext.branch, let repoPath = gitContext.repoPath else {
            return nil
        }

        // First call — seed state.
        guard let previousBranch = lastKnownBranch, let previousRepo = lastKnownRepoPath else {
            lastKnownBranch = branch
            lastKnownRepoPath = repoPath
            lastBranchStartedAt = Date()
            return nil
        }

        // Same branch — no switch.
        if branch == previousBranch && repoPath == previousRepo {
            return nil
        }

        let now = Date()
        let duration = lastBranchStartedAt.map { now.timeIntervalSince($0) } ?? 0
        let shouldSave = duration >= Self.minimumBranchDuration

        let event = SwitchEvent(
            fromBranch: previousBranch,
            toBranch: branch,
            repoPath: repoPath,
            outgoingKey: WorkspaceKey(repoPath: previousRepo, branch: previousBranch),
            incomingKey: WorkspaceKey(repoPath: repoPath, branch: branch),
            shouldSaveOutgoing: shouldSave
        )

        // Update state for the new branch.
        lastKnownBranch = branch
        lastKnownRepoPath = repoPath
        lastBranchStartedAt = now

        return event
    }

    // MARK: - Session persistence

    public func saveSession(key: WorkspaceKey, repoPath: String, branch: String, state: BundleManagerState) {
        let compacted = Compactor.compact(state)
        let session = BranchSession(
            workspaceKey: key,
            repoPath: repoPath,
            branch: branch,
            capturedAt: Date(),
            state: compacted
        )
        SessionStore.save(session)
    }

    public func loadSession(key: WorkspaceKey) -> BranchSession? {
        SessionStore.load(key: key)
    }
}
