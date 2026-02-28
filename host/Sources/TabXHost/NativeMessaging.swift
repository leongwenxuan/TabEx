import Foundation

/// Implements the Chrome native messaging protocol:
/// each message = 4-byte little-endian UInt32 length prefix + UTF-8 JSON payload.
///
/// Reference: https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging
public final class NativeMessagingIO {
    private let inputHandle: FileHandle
    private let outputHandle: FileHandle
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(
        input: FileHandle = .standardInput,
        output: FileHandle = .standardOutput
    ) {
        self.inputHandle = input
        self.outputHandle = output

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        self.encoder = enc
    }

    // MARK: - Reading

    /// Blocks until a complete message arrives on stdin. Returns nil on EOF or oversized message.
    public func readMessage() -> IncomingMessage? {
        guard let lengthData = readExactly(4), lengthData.count == 4 else { return nil }
        let length = lengthData.withUnsafeBytes { ptr in
            ptr.load(as: UInt32.self).littleEndian
        }
        // Sanity cap: Chrome limits native messages to 1 MB.
        guard length > 0, length <= 1_048_576 else { return nil }
        guard let payload = readExactly(Int(length)) else { return nil }
        if let decoded = try? decoder.decode(IncomingMessage.self, from: payload) {
            return decoded
        }

        // Be lenient with message formats so a single malformed payload doesn't kill the host.
        if let fallback = decodeLenient(payload: payload) {
            return fallback
        }

        // Keep the process alive instead of forcing Chrome to reconnect in a loop.
        fputs("tabx-host: received malformed native message; responding with pong fallback\n", stderr)
        return IncomingMessage(type: .ping)
    }

    // MARK: - Writing

    /// Encodes `message` and writes it with the 4-byte length prefix to stdout.
    public func writeMessage(_ message: OutgoingMessage) throws {
        let payload = try encoder.encode(message)
        guard payload.count <= 1_048_576 else {
            throw NativeMessagingError.messageTooLarge(payload.count)
        }
        var length = UInt32(payload.count).littleEndian
        let lengthData = Data(bytes: &length, count: 4)
        outputHandle.write(lengthData)
        outputHandle.write(payload)
    }

    // MARK: - Private helpers

    private func readExactly(_ count: Int) -> Data? {
        var buffer = Data()
        buffer.reserveCapacity(count)
        while buffer.count < count {
            let chunk = inputHandle.readData(ofLength: count - buffer.count)
            guard !chunk.isEmpty else { return nil }    // EOF
            buffer.append(chunk)
        }
        return buffer
    }

    private func decodeLenient(payload: Data) -> IncomingMessage? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: payload),
            let dict = obj as? [String: Any],
            let type = dict["type"] as? String
        else {
            return nil
        }

        switch type {
        case "ping":
            return IncomingMessage(type: .ping)

        case "request_bundle", "get_context_bundle":
            return IncomingMessage(type: .requestBundle)

        case "config_update":
            return IncomingMessage(type: .configUpdate)

        case "tab_update", "tab_data":
            guard let rawTabs = dict["tabs"] as? [[String: Any]] else {
                return IncomingMessage(type: .tabUpdate, tabs: [])
            }
            let tabs = rawTabs.compactMap(parseTabData)
            return IncomingMessage(type: .tabUpdate, tabs: tabs)

        default:
            return nil
        }
    }

    private func parseTabData(_ raw: [String: Any]) -> TabData? {
        guard
            let tabId = raw["tabId"] as? Int,
            let url = raw["url"] as? String,
            let title = raw["title"] as? String
        else {
            return nil
        }

        let timeSpentSeconds: Double = {
            if let v = raw["timeSpentSeconds"] as? Double { return v }
            if let v = raw["timeSpentSeconds"] as? Int { return Double(v) }
            if let ms = raw["timeSpentMs"] as? Double { return ms / 1000.0 }
            if let ms = raw["timeSpentMs"] as? Int { return Double(ms) / 1000.0 }
            return 0
        }()

        let scrollDepth: Double = {
            if let v = raw["scrollDepth"] as? Double { return v }
            if let v = raw["scrollDepth"] as? Int { return Double(v) }
            return 0
        }()

        let selectedText: String? = {
            if let v = raw["selectedText"] as? String { return v.isEmpty ? nil : v }
            if let arr = raw["selections"] as? [String], let last = arr.last, !last.isEmpty { return last }
            return nil
        }()

        let contentDigest: String? = {
            if let v = raw["contentDigest"] as? String { return v.isEmpty ? nil : v }
            if let v = raw["digest"] as? String { return v.isEmpty ? nil : v }
            return nil
        }()

        let lastVisitedAt: Date = {
            if let iso = raw["lastVisitedAt"] as? String {
                if let d = ISO8601DateFormatter().date(from: iso) { return d }
            }
            if let ts = raw["lastVisitedAt"] as? Double { return Date(timeIntervalSince1970: ts / 1000.0) }
            if let ts = raw["lastVisitedAt"] as? Int { return Date(timeIntervalSince1970: Double(ts) / 1000.0) }
            if let ts = raw["timestamp"] as? Double { return Date(timeIntervalSince1970: ts / 1000.0) }
            if let ts = raw["timestamp"] as? Int { return Date(timeIntervalSince1970: Double(ts) / 1000.0) }
            return Date()
        }()

        let isActive = raw["isActive"] as? Bool ?? false

        return TabData(
            tabId: tabId,
            url: url,
            title: title,
            timeSpentSeconds: max(0, timeSpentSeconds),
            scrollDepth: max(0, min(1, scrollDepth)),
            selectedText: selectedText,
            contentDigest: contentDigest,
            lastVisitedAt: lastVisitedAt,
            isActive: isActive
        )
    }
}

public enum NativeMessagingError: Error, CustomStringConvertible {
    case messageTooLarge(Int)

    public var description: String {
        switch self {
        case .messageTooLarge(let size):
            return "Message too large: \(size) bytes (max 1 MB)"
        }
    }
}
