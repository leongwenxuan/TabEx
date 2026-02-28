import Foundation

/// Full snapshot of a branch's tab session, persisted to disk.
public struct BranchSession: Codable, Sendable {
    public let workspaceKey: WorkspaceKey
    public let repoPath: String
    public let branch: String
    public let capturedAt: Date
    public let pageRecords: [String: PageRecord]
    public let latestResults: [TabResult]
    /// Tab ID -> URL mapping. Uses `[String: String]` for JSON dict key encoding.
    public let urlForTabId: [String: String]
    /// Tab ID -> title mapping. Uses `[String: String]` for JSON dict key encoding.
    public let titleForTabId: [String: String]

    public init(
        workspaceKey: WorkspaceKey,
        repoPath: String,
        branch: String,
        capturedAt: Date,
        state: BundleManagerState
    ) {
        self.workspaceKey = workspaceKey
        self.repoPath = repoPath
        self.branch = branch
        self.capturedAt = capturedAt
        self.pageRecords = state.pageRecords
        self.latestResults = state.latestResults
        // Convert [Int: String] -> [String: String] for JSON compatibility.
        self.urlForTabId = Dictionary(uniqueKeysWithValues: state.urlForTabId.map { (String($0.key), $0.value) })
        self.titleForTabId = Dictionary(uniqueKeysWithValues: state.titleForTabId.map { (String($0.key), $0.value) })
    }

    /// Reconstitutes a `BundleManagerState` from the persisted string-keyed dictionaries.
    public func toBundleManagerState() -> BundleManagerState {
        let intUrlMap = Dictionary(uniqueKeysWithValues: urlForTabId.compactMap { k, v -> (Int, String)? in
            guard let id = Int(k) else { return nil }
            return (id, v)
        })
        let intTitleMap = Dictionary(uniqueKeysWithValues: titleForTabId.compactMap { k, v -> (Int, String)? in
            guard let id = Int(k) else { return nil }
            return (id, v)
        })
        return BundleManagerState(
            pageRecords: pageRecords,
            latestResults: latestResults,
            urlForTabId: intUrlMap,
            titleForTabId: intTitleMap
        )
    }
}

/// Lightweight index entry for listing saved sessions without loading full data.
public struct SessionIndexEntry: Codable, Sendable {
    public let workspaceKey: WorkspaceKey
    public let repoPath: String
    public let branch: String
    public let capturedAt: Date
    public let pageCount: Int
    public let tabCount: Int

    public init(from session: BranchSession) {
        self.workspaceKey = session.workspaceKey
        self.repoPath = session.repoPath
        self.branch = session.branch
        self.capturedAt = session.capturedAt
        self.pageCount = session.pageRecords.count
        self.tabCount = session.urlForTabId.count
    }

    public init(
        workspaceKey: WorkspaceKey,
        repoPath: String,
        branch: String,
        capturedAt: Date,
        pageCount: Int,
        tabCount: Int
    ) {
        self.workspaceKey = workspaceKey
        self.repoPath = repoPath
        self.branch = branch
        self.capturedAt = capturedAt
        self.pageCount = pageCount
        self.tabCount = tabCount
    }
}
