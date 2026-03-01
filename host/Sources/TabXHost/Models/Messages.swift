import Foundation

// MARK: - Incoming messages from the Chrome extension

public enum MessageType: String, Codable {
    case tabUpdate = "tab_update"
    case requestBundle = "request_bundle"
    case ping = "ping"
    case configUpdate = "config_update"
    case restoreSession = "restore_session"
    case getSessions = "get_sessions"
}

public struct TabData: Codable, Sendable {
    public let tabId: Int
    public let url: String
    public let title: String
    public let timeSpentSeconds: Double
    /// 0.0 (top) … 1.0 (bottom reached)
    public let scrollDepth: Double
    public let selectedText: String?
    /// Short plain-text excerpt of page body used for semantic scoring.
    public let contentDigest: String?
    public let lastVisitedAt: Date
    public let isActive: Bool

    public init(
        tabId: Int,
        url: String,
        title: String,
        timeSpentSeconds: Double,
        scrollDepth: Double,
        selectedText: String?,
        contentDigest: String?,
        lastVisitedAt: Date,
        isActive: Bool
    ) {
        self.tabId = tabId
        self.url = url
        self.title = title
        self.timeSpentSeconds = timeSpentSeconds
        self.scrollDepth = scrollDepth
        self.selectedText = selectedText
        self.contentDigest = contentDigest
        self.lastVisitedAt = lastVisitedAt
        self.isActive = isActive
    }
}

public struct IncomingMessage: Codable, Sendable {
    public let type: MessageType
    public let tabs: [TabData]?
    public let config: ScoringConfig?
    public let sessionKey: String?

    public init(
        type: MessageType,
        tabs: [TabData]? = nil,
        config: ScoringConfig? = nil,
        sessionKey: String? = nil
    ) {
        self.type = type
        self.tabs = tabs
        self.config = config
        self.sessionKey = sessionKey
    }
}

// MARK: - Outgoing messages to the Chrome extension

public enum TabDecision: String, Codable, Sendable {
    case close
    case keep
    case flag
}

public struct TabResult: Codable, Sendable {
    public let tabId: Int
    public let decision: TabDecision
    /// Normalised score 0.0–1.0.
    public let score: Double
    public let reason: String
    /// Agent-generated summary of the tab's content.
    public let summary: String?
    /// Agent-generated insights about the tab's relevance.
    public let insights: [String]?

    public init(
        tabId: Int,
        decision: TabDecision,
        score: Double,
        reason: String,
        summary: String? = nil,
        insights: [String]? = nil
    ) {
        self.tabId = tabId
        self.decision = decision
        self.score = score
        self.reason = reason
        self.summary = summary
        self.insights = insights
    }
}

public enum OutgoingMessageType: String, Codable, Sendable {
    case decisions
    case bundle
    case pong
    case error
    case sessionSwitch = "session_switch"
    case sessions
}

public struct TabToOpen: Codable, Sendable {
    public let url: String
    public let title: String

    public init(url: String, title: String) {
        self.url = url
        self.title = title
    }
}

public struct SessionSwitchPayload: Codable, Sendable {
    public let fromBranch: String?
    public let toBranch: String?
    public let repoPath: String?
    public let hasSavedSession: Bool
    public let incomingKey: String?
    public let tabsToOpen: [TabToOpen]?

    public init(
        fromBranch: String?,
        toBranch: String?,
        repoPath: String?,
        hasSavedSession: Bool,
        incomingKey: String?,
        tabsToOpen: [TabToOpen]? = nil
    ) {
        self.fromBranch = fromBranch
        self.toBranch = toBranch
        self.repoPath = repoPath
        self.hasSavedSession = hasSavedSession
        self.incomingKey = incomingKey
        self.tabsToOpen = tabsToOpen
    }
}

public struct OutgoingMessage: Codable, Sendable {
    public let type: OutgoingMessageType
    public let results: [TabResult]?
    public let bundle: ContextBundle?
    public let error: String?
    public let sessionSwitch: SessionSwitchPayload?
    public let sessions: [SessionIndexEntry]?

    public init(
        type: OutgoingMessageType,
        results: [TabResult]? = nil,
        bundle: ContextBundle? = nil,
        error: String? = nil,
        sessionSwitch: SessionSwitchPayload? = nil,
        sessions: [SessionIndexEntry]? = nil
    ) {
        self.type = type
        self.results = results
        self.bundle = bundle
        self.error = error
        self.sessionSwitch = sessionSwitch
        self.sessions = sessions
    }
}
