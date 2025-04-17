import Alamofire
import Foundation

/// Service for chat completions using Ollama models
public actor ChatCompletionService: ChatCompletionServiceProtocol {
    /// Base URL for the Ollama API
    private let baseURL: URL

    /// Timeout interval for network requests
    private let timeoutInterval: TimeInterval

    /// Initializes the chat completion service
    /// - Parameters:
    ///   - baseURL: Base URL for the Ollama API
    ///   - timeout: Timeout interval for network requests
    public init(
        baseURL: URL = URL(string: "http://localhost:11434")!,
        timeout: TimeInterval = 30
    ) {
        self.baseURL = baseURL
        self.timeoutInterval = timeout
    }

    /// Generates a chat completion with the given model and messages
    /// - Parameters:
    ///   - model: The model to use for completion
    ///   - messages: Array of messages in the conversation
    ///   - temperature: Temperature for sampling (higher = more random)
    ///   - stream: Whether to stream the response
    /// - Returns: A stream of response chunks
    public func generateChatCompletion(
        model: AIModel,
        messages: [ChatMessage],
        temperature: Double = 0.7,
        stream: Bool = true
    ) async throws -> AsyncStream<ChatMessageChunk> {
        // Create the stream
        return AsyncStream { continuation in
            Task {
                do {
                    // Create the request
                    let url = baseURL.appendingPathComponent("api/chat")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = self.timeoutInterval

                    // Create request body
                    let requestBody = ChatCompletionRequest(
                        model: model.name,
                        messages: messages,
                        stream: stream,
                        options: ChatCompletionOptions(temperature: temperature)
                    )

                    // Encode the request
                    let encoder = JSONEncoder()
                    request.httpBody = try encoder.encode(requestBody)

                    // Make the request
                    let (data, response) = try await URLSession.shared.data(for: request)

                    // Process response
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw NSError(
                            domain: "AIIntegration", code: 0,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                    }

                    guard httpResponse.statusCode == 200 else {
                        throw NSError(
                            domain: "AIIntegration",
                            code: httpResponse.statusCode,
                            userInfo: [
                                NSLocalizedDescriptionKey: "Error: \(httpResponse.statusCode)"
                            ]
                        )
                    }

                    // Process the data
                    let decoder = JSONDecoder()
                    if let responseData = try? decoder.decode(
                        ChatCompletionResponse.self, from: data)
                    {
                        if let message = responseData.message {
                            continuation.yield(ChatMessageChunk(content: message.content))
                        }
                    }

                    // Finish the stream
                    continuation.finish()
                } catch {
                    // Handle error
                    continuation.finish()
                }
            }
        }
    }

    /// Generates a text completion
    /// - Parameters:
    ///   - model: Model to use
    ///   - prompt: Text prompt
    ///   - temperature: Sampling temperature
    ///   - stream: Whether to stream the response
    /// - Returns: An async stream of completion chunks
    public func generateCompletion(
        model: AIModel,
        prompt: String,
        temperature: Double = 0.7,
        stream: Bool = true
    ) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let url = baseURL.appendingPathComponent("api/generate")
        let timeout = self.timeoutInterval  // Capture timeout immutably

        // Create parameters dictionary directly
        let modelName = model.name
        let paramDict: [String: Any] = [
            "model": modelName,
            "prompt": prompt,
            "stream": stream,
            "options": [
                "temperature": temperature
            ],
        ]
        
        // Convert parameters to JSON outside the task
        let jsonData = try JSONSerialization.data(withJSONObject: paramDict)

        // Create the stream
        return AsyncThrowingStream { continuation in
            Task {
                AF.streamRequest(
                    url,
                    method: .post,
                    headers: ["Content-Type": "application/json"]
                ) { request in
                    request.timeoutInterval = timeout
                    request.httpBody = jsonData 
                }
                .validate()
                .responseStream { stream in
                    switch stream.event {
                    case .stream(let result):
                        switch result {
                        case .success(let data):
                            // Decode the chunk manually to avoid type conflicts
                            if let jsonObject = try? JSONSerialization.jsonObject(with: data)
                                as? [String: Any],
                                let response = jsonObject["response"] as? String
                            {
                                let done = (jsonObject["done"] as? Bool) ?? false
                                let chunk = CompletionChunk(content: response, isComplete: done)
                                continuation.yield(chunk)

                                // Check if we're done
                                if done {
                                    continuation.finish()
                                }
                            }

                        case .failure(let error):
                            continuation.finish(throwing: error)
                        }

                    case .complete(let completion):
                        if let error = completion.error {
                            continuation.finish(throwing: error)
                        } else {
                            // If stream completes without 'done' signal
                            continuation.finish()
                        }
                    }
                }
            }
        }
    }
} 