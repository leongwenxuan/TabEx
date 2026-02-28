import Foundation

// MARK: - Configuration

/// Configuration for the OpenAI API connection.
public struct OpenAIConfig: Codable, Sendable {
    public var apiKey: String
    public var agentModel: String
    public var judgeModel: String
    public var baseURL: String
    public var timeoutSeconds: Double

    public init(
        apiKey: String = "",
        agentModel: String = "gpt-4o-mini",
        judgeModel: String = "gpt-4o",
        baseURL: String = "https://api.openai.com/v1",
        timeoutSeconds: Double = 30
    ) {
        self.apiKey = apiKey
        self.agentModel = agentModel
        self.judgeModel = judgeModel
        self.baseURL = baseURL
        self.timeoutSeconds = timeoutSeconds
    }

    public static let `default` = OpenAIConfig()

    public var hasAPIKey: Bool { !apiKey.isEmpty }
}

// MARK: - Chat Message

public struct ChatMessage: Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

// MARK: - Protocol

/// Abstraction over LLM chat completion for testability.
public protocol LLMClientProtocol: Sendable {
    func chatCompletion(
        model: String,
        messages: [ChatMessage],
        temperature: Double,
        maxTokens: Int
    ) throws -> String
}

// MARK: - OpenAI Client

public final class OpenAIClient: LLMClientProtocol, @unchecked Sendable {
    private let config: OpenAIConfig
    private let session: URLSession

    public init(config: OpenAIConfig) {
        self.config = config
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = config.timeoutSeconds
        self.session = URLSession(configuration: sessionConfig)
    }

    public func chatCompletion(
        model: String,
        messages: [ChatMessage],
        temperature: Double = 0.3,
        maxTokens: Int = 1024
    ) throws -> String {
        guard config.hasAPIKey else {
            throw OpenAIError.noAPIKey
        }

        let url = URL(string: "\(config.baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": temperature,
            "max_tokens": maxTokens,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Synchronous HTTP via semaphore (native messaging is already on a background thread).
        var result: Result<String, Error> = .failure(OpenAIError.timeout)
        let semaphore = DispatchSemaphore(value: 0)

        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                result = .failure(error)
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String
            else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "no body"
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                result = .failure(OpenAIError.badResponse(status: status, body: body))
                return
            }
            result = .success(content)
        }
        task.resume()
        semaphore.wait()

        return try result.get()
    }
}

// MARK: - Errors

public enum OpenAIError: Error, LocalizedError {
    case noAPIKey
    case timeout
    case badResponse(status: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No OpenAI API key configured"
        case .timeout: return "OpenAI request timed out"
        case .badResponse(let status, let body): return "OpenAI error \(status): \(body)"
        }
    }
}
