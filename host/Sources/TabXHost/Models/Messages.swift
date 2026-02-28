import Foundation

// MARK: - Incoming messages from the Chrome extension

public enum MessageType: String, Codable {
    case tabUpdate = "tab_update"
    case requestBundle = "request_bundle"
    case ping = "ping"
    case configUpdate = "config_update"
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

    public init(type: MessageType, tabs: [TabData]? = nil, config: ScoringConfig? = nil) {
        self.type = type
        self.tabs = tabs
        self.config = config
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

    public init(tabId: Int, decision: TabDecision, score: Double, reason: String) {
        self.tabId = tabId
        self.decision = decision
        self.score = score
        self.reason = reason
    }
}

public enum OutgoingMessageType: String, Codable, Sendable {
    case decisions
    case bundle
    case pong
    case error
}

public struct OutgoingMessage: Codable, Sendable {
    public let type: OutgoingMessageType
    public let results: [TabResult]?
    public let bundle: ContextBundle?
    public let error: String?

    public init(
        type: OutgoingMessageType,
        results: [TabResult]? = nil,
        bundle: ContextBundle? = nil,
        error: String? = nil
    ) {
        self.type = type
        self.results = results
        self.bundle = bundle
        self.error = error
    }
}
