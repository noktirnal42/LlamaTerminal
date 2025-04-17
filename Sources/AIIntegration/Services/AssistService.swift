import Foundation

/// Protocol for assistance services
public protocol AssistServiceProtocol {
    /// Generates assistance response for user input
    /// - Parameters:
    ///   - input: User input to generate assistance for
    ///   - model: AI model to use
    /// - Returns: Generated assistance text
    func generateAssistance(for input: String, model: AIModel) async throws -> String

    /// Analyzes command execution results
    /// - Parameters:
    ///   - result: Result of command execution
    ///   - model: AI model to use
    /// - Returns: Analysis of the command result
    func analyzeCommandResult(result: CommandResult, model: AIModel) async throws -> String
}

/// Implementation of the assist service
public actor AssistService: AssistServiceProtocol {
    nonisolated private let chatService: ChatCompletionServiceProtocol

    public init(chatService: ChatCompletionServiceProtocol = ChatCompletionService()) {
        self.chatService = chatService
    }

    public func generateAssistance(for input: String, model: AIModel) async throws -> String {
        let systemPrompt = """
            You are an AI assistant helping with terminal usage. 
            Provide clear, concise explanations and helpful information related to the user's query.
            Focus on being informative and practical.
            """

        let messages: [ChatMessage] = [
            ChatMessage(role: .system, content: systemPrompt),
            ChatMessage(role: .user, content: input),
        ]

        var completeResponse = ""
        let responseStream = try await chatService.generateChatCompletion(
            model: model,
            messages: messages,
            temperature: 0.7,
            stream: true
        )

        for await chunk in responseStream {
            completeResponse += chunk.content
        }

        return completeResponse
    }

    public func analyzeCommandResult(result: CommandResult, model: AIModel) async throws -> String {
        let systemPrompt = """
            You are an AI assistant analyzing terminal command results.
            Provide a brief, helpful analysis of the command output.
            For successful commands, highlight key information.
            For errors, suggest possible causes and solutions.
            """

        let userMessage = """
            Command: \(result.command)
            Exit code: \(result.exitCode)
            Output:
            \(result.output)

            Please analyze this result.
            """

        let messages: [ChatMessage] = [
            ChatMessage(role: .system, content: systemPrompt),
            ChatMessage(role: .user, content: userMessage),
        ]

        var completeResponse = ""
        let responseStream = try await chatService.generateChatCompletion(
            model: model,
            messages: messages,
            temperature: 0.7,
            stream: true
        )

        for await chunk in responseStream {
            completeResponse += chunk.content
        }

        return completeResponse
    }
}
