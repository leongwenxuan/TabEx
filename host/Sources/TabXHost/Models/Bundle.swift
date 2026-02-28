import Foundation

/// A page the user has visited and (partially) read.
public struct PageRecord: Codable, Sendable {
    public let url: String
    public let title: String
    public let contentDigest: String?
    /// Text snippets the user selected on this page.
    public let highlights: [String]
    public let timeSpentSeconds: Double
    public let scrollDepth: Double
    public let visitedAt: Date

    public init(
        url: String,
        title: String,
        contentDigest: String?,
        highlights: [String],
        timeSpentSeconds: Double,
        scrollDepth: Double,
        visitedAt: Date
    ) {
        self.url = url
        self.title = title
        self.contentDigest = contentDigest
        self.highlights = highlights
        self.timeSpentSeconds = timeSpentSeconds
        self.scrollDepth = scrollDepth
        self.visitedAt = visitedAt
    }
}

/// A tab that survived the scoring round (decision = keep or flag).
public struct SurvivingTab: Codable, Sendable {
    public let tabId: Int
    public let url: String
    public let title: String
    public let score: Double
    public let decision: TabDecision

    public init(tabId: Int, url: String, title: String, score: Double, decision: TabDecision) {
        self.tabId = tabId
        self.url = url
        self.title = title
        self.score = score
        self.decision = decision
    }
}

/// The context bundle handed off to coding agents.
public struct ContextBundle: Codable, Sendable {
    public let generatedAt: Date
    /// Current git branch at time of generation.
    public let gitBranch: String?
    /// Absolute path to the detected git repository root.
    public let gitRepoPath: String?
    /// All pages the user has read in the retention window.
    public let pagesRead: [PageRecord]
    /// Tabs still open after the last scoring round.
    public let survivingTabs: [SurvivingTab]
    /// Recently-touched source files (from git diff).
    public let openFiles: [String]
    /// Optional free-text task description (derived from branch name or user-supplied).
    public let taskDescription: String?

    public init(
        generatedAt: Date,
        gitBranch: String?,
        gitRepoPath: String?,
        pagesRead: [PageRecord],
        survivingTabs: [SurvivingTab],
        openFiles: [String],
        taskDescription: String?
    ) {
        self.generatedAt = generatedAt
        self.gitBranch = gitBranch
        self.gitRepoPath = gitRepoPath
        self.pagesRead = pagesRead
        self.survivingTabs = survivingTabs
        self.openFiles = openFiles
        self.taskDescription = taskDescription
    }
}
