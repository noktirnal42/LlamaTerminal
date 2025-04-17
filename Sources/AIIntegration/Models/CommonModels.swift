import Foundation

/// Represents a message in a chat conversation
public struct ChatMessage: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable {
        case system, user, assistant
    }

    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

/// Represents a chunk of a chat message during streaming
public struct ChatMessageChunk: Equatable, Sendable {
    /// Content in the chunk
    public let content: String

    public init(content: String) {
        self.content = content
    }
}

/// Represents a chunk of a completion response during streaming
public struct CompletionChunk: Equatable, Decodable, Sendable {
    /// Content in the chunk
    public let content: String
    /// Whether this is the last chunk
    public let isComplete: Bool

    enum CodingKeys: String, CodingKey {
        case content = "response"
        case isComplete = "done"
    }

    public init(content: String, isComplete: Bool = false) {
        self.content = content
        self.isComplete = isComplete
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        isComplete = try container.decode(Bool.self, forKey: .isComplete)
    }
}

/// Protocol for chat completion services
public protocol ChatCompletionServiceProtocol: Sendable {
    /// Generates a chat completion with the given model and messages
    func generateChatCompletion(
        model: AIModel,
        messages: [ChatMessage],
        temperature: Double,
        stream: Bool
    ) async throws -> AsyncStream<ChatMessageChunk>
}

/// Protocol for command parsing services
public protocol CommandParsingServiceProtocol: Sendable {
    /// Preprocesses AI response text
    func preprocessResponse(_ response: String) async -> String

    /// Parses command suggestions from AI response
    func parseSuggestions(from response: String) async throws -> [CommandSuggestion]

    /// Parses AI actions from AI response
    func parseActions(from response: String) async throws -> [AIAction]
}

// Ollama API request/response models

/// Request for the Ollama chat completion API
internal struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let options: ChatCompletionOptions?
}

/// Options for the chat completion request
internal struct ChatCompletionOptions: Encodable {
    let temperature: Double?
}

/// Response from the chat completion API
internal struct ChatCompletionResponse: Decodable {
    let message: ChatMessage?
    let done: Bool

    enum CodingKeys: String, CodingKey {
        case message
        case done
    }
}

/// Filter for model capabilities
public enum ModelCapabilityFilter: String, Codable {
    case code
    case command
    case all
}
