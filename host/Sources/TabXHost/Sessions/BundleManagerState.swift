import Foundation

/// Value type capturing `BundleManager`'s private state for session persistence.
public struct BundleManagerState: Codable, Sendable {
    public let pageRecords: [String: PageRecord]
    public let latestResults: [TabResult]
    public let urlForTabId: [Int: String]
    public let titleForTabId: [Int: String]

    public init(
        pageRecords: [String: PageRecord],
        latestResults: [TabResult],
        urlForTabId: [Int: String],
        titleForTabId: [Int: String]
    ) {
        self.pageRecords = pageRecords
        self.latestResults = latestResults
        self.urlForTabId = urlForTabId
        self.titleForTabId = titleForTabId
    }

    public static let empty = BundleManagerState(
        pageRecords: [:],
        latestResults: [],
        urlForTabId: [:],
        titleForTabId: [:]
    )
}
