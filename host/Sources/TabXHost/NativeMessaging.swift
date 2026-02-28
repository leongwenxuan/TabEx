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
        return try? decoder.decode(IncomingMessage.self, from: payload)
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
