import Foundation
import CryptoKit

/// A stable, filesystem-safe identifier derived from `repoPath:branch`.
/// Uses the first 16 hex characters of SHA256.
public struct WorkspaceKey: Codable, Sendable, Hashable, CustomStringConvertible {
    public let rawValue: String

    public init(repoPath: String, branch: String) {
        let input = "\(repoPath):\(branch)"
        let digest = SHA256.hash(data: Data(input.utf8))
        self.rawValue = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
