import Foundation
import Alamofire

public actor OllamaModelService { // Changed from class to actor
    private let baseURL: URL
    private let session: Session
    // Duplicate baseURL removed
    
    /// Default timeout interval for network requests
    private let timeoutInterval: TimeInterval = 30.0
    
    /// Initializes a new instance of OllamaModelService
    /// - Parameter baseURLString: Base URL of the Ollama API, defaults to localhost
    public init(baseURLString: String = "http://localhost:11434") {
        self.baseURL = URL(string: baseURLString)!
        self.session = Session.default // Initialize the session property
    }
    
    /// Lists available models from the Ollama API
    /// - Returns: Array of AIModel objects
    /// - Throws: NetworkError or DecodingError
    public func listModels() async throws -> [AIModel] { // Removed nonisolated (implied actor isolation)
        let url = baseURL.appendingPathComponent("api/tags")
        let timeout = self.timeoutInterval // Capture timeout immutably
        
        let response: OllamaListResponse = try await AF.request(url, method: .get,
                                                        requestModifier: { $0.timeoutInterval = timeout })
            .validate()
            .serializingDecodable(OllamaListResponse.self)
            .value
            
        return response.models.map { model in
            // Determine model capabilities based on name
            let modelType = ModelType.determine(from: model.name)
            let capabilities = ModelCapabilities(
                isCodeCapable: modelType == .code,
                isMultimodal: modelType == .multimodal,
                isCommandOptimized: modelType == .command
            )
            
            // Parse the date if available, otherwise use current date
            let modified: Date
            if let modifiedAt = model.modifiedAt {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: modifiedAt) {
                    modified = date
                } else {
                    // Try without fractional seconds
                    formatter.formatOptions = [.withInternetDateTime]
                    modified = formatter.date(from: modifiedAt) ?? Date()
                }
            } else {
                modified = Date()
            }
            
            return AIModel(
                id: model.digest, // Use digest as the unique ID
                name: model.name,
                size: UInt64(model.size ?? 0),
                modified: modified,
                capabilities: capabilities
            )
        }
    }
    
    /// Pulls a model from Ollama registry
    /// - Parameter modelName: Name of the model to pull
    /// - Returns: Progress updates and completion status
    public func pullModel(modelName: String) async throws -> AsyncThrowingStream<PullProgress, Error> { // Removed nonisolated
        let url = baseURL.appendingPathComponent("api/pull")
        
        let parameters: [String: String] = [
            "name": modelName
        ]
        
        return AsyncThrowingStream { continuation in // Start AsyncThrowingStream closure
            Task { // Start Task inside the closure
                AF.streamRequest(url, method: .post,
                                 parameters: parameters,
                                 encoder: JSONParameterEncoder.default,
                                 requestModifier: { $0.timeoutInterval = 3600 }) // Long timeout
                    .validate()
                    .responseStreamDecodable(of: PullProgressResponse.self) { stream in
                        switch stream.event {
                        case .stream(let result):
                            switch result {
                            case .success(let progress):
                                continuation.yield(PullProgress(
                                    completed: progress.completed,
                                    total: progress.total,
                                    status: progress.status
                                ))
                                
                                if progress.status == "success" {
                                    continuation.finish()
                                }
                                
                            case .failure(let error):
                                continuation.finish(throwing: error)
                            }
                            
                        case .complete(let completion):
                            if let error = completion.error {
                                continuation.finish(throwing: error)
                            } else {
                                // If stream completes without 'success' status, ensure finish is called
                                continuation.finish()
                            }
                        }
                    } // End of responseStreamDecodable closure
            } // End of Task
        } // End of AsyncThrowingStream closure
    } // End of pullModel function
    
    /// Deletes a model from Ollama
    /// - Parameter modelName: Name of the model to delete
    public func deleteModel(modelName: String) async throws { // Removed nonisolated
        let url = baseURL.appendingPathComponent("api/delete")
        
        let parameters: [String: String] = [
            "name": modelName
        ]
        
        let timeout = self.timeoutInterval // Capture timeout immutably
        _ = try await AF.request(url, method: .delete,
                            parameters: parameters,
                            encoder: JSONParameterEncoder.default,
                            requestModifier: { $0.timeoutInterval = timeout })
            .validate()
             .serializingDecodable(DeleteModelResponse.self)
             .value // Assign to _ to silence warning
    } // End of deleteModel function
} // End of OllamaModelService class

// MARK: - Request and Response Models

/// Response from the Ollama list API
struct OllamaListResponse: Decodable {
    let models: [OllamaModel]
}

/// Individual model information from Ollama
struct OllamaModel: Decodable {
    let name: String
    let digest: String
    let modifiedAt: String?
    let size: Int?
    
    enum CodingKeys: String, CodingKey {
        case name
        case digest
        case modifiedAt = "modified_at"
        case size
    }
    
    /// Custom decoder to handle optional fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        digest = try container.decode(String.self, forKey: .digest)
        modifiedAt = try container.decodeIfPresent(String.self, forKey: .modifiedAt)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
    }
}

/// Progress information during model pull
public struct PullProgress: Sendable {
    public let completed: Int
    public let total: Int
    public let status: String
    
    public var progress: Double {
        return total > 0 ? Double(completed) / Double(total) : 0
    }
}

/// Pull progress response from the Ollama API
struct PullProgressResponse: Decodable {
    let completed: Int
    let total: Int
    let status: String
}

/// Response when deleting a model
struct DeleteModelResponse: Decodable {
    let status: String
}

/// Custom errors for the Ollama service
public enum OllamaError: Error, LocalizedError {
    case modelNotFound
    case connectionFailed
    case apiError(String)
    case decodingError
    
    public var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "The requested model was not found."
        case .connectionFailed:
            return "Failed to connect to Ollama. Make sure Ollama is running."
        case .apiError(let message):
            return "Ollama API error: \(message)"
        case .decodingError:
            return "Failed to decode the response from Ollama."
        }
    }
}
