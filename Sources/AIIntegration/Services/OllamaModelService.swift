import Foundation
import Alamofire

/// Service for interacting with Ollama models, providing enhanced capabilities for model management
public actor OllamaModelService {
    /// Base URL for the Ollama API
    private let baseURL: URL
    
    /// Network session for API requests
    private let session: Session
    
    /// Cache of model metadata for quick access
    private var modelMetadataCache: [String: ModelMetadata] = [:]
    
    /// Default timeout interval for network requests
    private let timeoutInterval: TimeInterval = 30.0
    
    /// Last time the models were refreshed
    private var lastModelRefresh: Date?
    
    /// Flag to track if Ollama is running
    private var isOllamaRunning: Bool = false
    
    /// Initializes a new instance of OllamaModelService
    /// Initializes a new instance of OllamaModelService
    /// - Parameters:
    ///   - baseURLString: Base URL of the Ollama API, defaults to localhost
    ///   - session: Alamofire session for network requests
    ///   - initialModels: Optional pre-populated model list for testing
    public init(
        baseURLString: String = "http://localhost:11434",
        session: Session = .default,
        initialModels: [AIModel]? = nil
    ) {
        self.baseURL = URL(string: baseURLString)!
        self.session = session
        
        // If we have initial models, populate the cache
        if let models = initialModels {
            for model in models {
                let metadata = ModelMetadata(capabilities: model.capabilities, parameters: [:])
                modelMetadataCache[model.name] = metadata
            }
            lastModelRefresh = Date()
            isOllamaRunning = true
        }
    }
    /// Lists available models from the Ollama API with enhanced metadata
    /// - Parameter forceRefresh: Whether to force a refresh even if the cache is recent
    /// - Returns: Array of AIModel objects with enhanced capabilities
    /// - Throws: OllamaError
    public func listModels(forceRefresh: Bool = false) async throws -> [AIModel] {
        // Check if we need to refresh (cache expired or forced)
        let shouldRefresh = forceRefresh || 
                            lastModelRefresh == nil || 
                            Date().timeIntervalSince(lastModelRefresh!) > 300 // 5 minute cache
        
        if shouldRefresh {
            do {
                return try await refreshModels()
            } catch {
                if let ollamaError = error as? OllamaError {
                    throw ollamaError
                } else if let afError = error as? AFError, afError.isSessionTaskError {
                    isOllamaRunning = false
                    throw OllamaError.connectionFailed
                } else {
                    throw OllamaError.apiError("Failed to list models: \(error.localizedDescription)")
                }
            }
        } else {
            // Use cached models if we have them
            if !modelMetadataCache.isEmpty {
                return try await convertCacheToModels()
            } else {
                return try await refreshModels()
            }
        }
    }
    
    /// Refreshes the model list from the Ollama API
    /// - Returns: Array of AIModel objects
    /// - Throws: NetworkError or DecodingError
    private func refreshModels() async throws -> [AIModel] {
        let url = baseURL.appendingPathComponent("api/tags")
        let timeout = self.timeoutInterval // Capture timeout immutably
        
        let response: OllamaListResponse = try await AF.request(url, method: .get,
                                                        requestModifier: { $0.timeoutInterval = timeout })
            .validate()
            .serializingDecodable(OllamaListResponse.self)
            .value
            
        // Update the last refresh time and Ollama status
        lastModelRefresh = Date()
        isOllamaRunning = true
        
        // Clear existing cache and rebuild
        modelMetadataCache.removeAll()
        
        // Process the models with enhanced capability detection
        let models = await processModelResponse(response.models)
        
        // Cache model capabilities for future use
        for model in models {
            let metadata = ModelMetadata(
                capabilities: model.capabilities,
                parameters: await detectOptimalParameters(for: model.name)
            )
            modelMetadataCache[model.name] = metadata
        }
        
        return models
    }
    
    /// Processes model response and enhances capabilities detection
    /// - Parameter models: Raw model data from Ollama API
    /// - Returns: Enhanced AIModel objects
    private func processModelResponse(_ models: [OllamaModel]) async -> [AIModel] {
        return await withTaskGroup(of: AIModel.self) { group in
            for model in models {
                group.addTask {
                    // Determine model capabilities based on name and additional probing
                    let capabilities = await self.detectModelCapabilities(modelName: model.name)
                    
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
            
            var result: [AIModel] = []
            for await model in group {
                result.append(model)
            }
            
            return result
        }
    }
    
    /// Converts the cache to AIModel objects
    /// - Returns: Array of AIModel objects from cache
    private func convertCacheToModels() async throws -> [AIModel] {
        // Query model info from Ollama to get latest sizes and digests
        do {
            let url = baseURL.appendingPathComponent("api/tags")
            let timeout = self.timeoutInterval
            
            let response: OllamaListResponse = try await AF.request(url, method: .get,
                                                          requestModifier: { $0.timeoutInterval = timeout })
                .validate()
                .serializingDecodable(OllamaListResponse.self)
                .value
            
            // Ollama is running if we get here
            isOllamaRunning = true
            
            return response.models.compactMap { model in
                // Use cached capabilities if available
                guard let metadata = modelMetadataCache[model.name] else {
                    return nil
                }
                
                // Parse date
                let modified: Date
                if let modifiedAt = model.modifiedAt {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = formatter.date(from: modifiedAt) {
                        modified = date
                    } else {
                        formatter.formatOptions = [.withInternetDateTime]
                        modified = formatter.date(from: modifiedAt) ?? Date()
                    }
                } else {
                    modified = Date()
                }
                
                return AIModel(
                    id: model.digest,
                    name: model.name,
                    size: UInt64(model.size ?? 0),
                    modified: modified,
                    capabilities: metadata.capabilities
                )
            }
        } catch {
            // If error, use directly from the cache with less accurate info
            return modelMetadataCache.map { name, metadata in
                AIModel(
                    id: name, // Use name as ID since we don't have the digest
                    name: name,
                    size: 0, // Unknown size
                    modified: Date(), // Current date since we don't know
                    capabilities: metadata.capabilities
                )
            }
        }
    }

    // MARK: - Model Capability Detection
    
    /// Detects model capabilities through testing and metadata analysis
    /// - Parameter modelName: Name of the model to detect capabilities for
    /// - Returns: ModelCapabilities object with detected capabilities
    private func detectModelCapabilities(modelName: String) async -> ModelCapabilities {
        // Start with basic capabilities based on name
        let modelType = ModelType.determine(from: modelName)
        var capabilities = ModelCapabilities(
            isCodeCapable: modelType == .code,
            isMultimodal: modelType == .multimodal,
            isCommandOptimized: modelType == .command
        )
        
        // For better accuracy, probe the model if Ollama is running
        if isOllamaRunning {
            do {
                // Test code capabilities
                if !capabilities.isCodeCapable {
                    capabilities.isCodeCapable = try await testCodeCapabilities(modelName: modelName)
                }
                
                // Test command optimization
                if !capabilities.isCommandOptimized {
                    capabilities.isCommandOptimized = try await testCommandCapabilities(modelName: modelName)
                }
                
                // Test for multimodal capabilities - this could be inferred from model tags
                // or by checking if the model accepts image inputs in Ollama
                if modelName.lowercased().contains("vision") || 
                   modelName.lowercased().contains("llava") ||
                   modelName.lowercased().contains("multimodal") {
                    capabilities.isMultimodal = true
                }
                
                // Advanced capabilities detection
                let tokenLimit = try await detectTokenLimit(modelName: modelName)
                if tokenLimit > 8000 {
                    capabilities.hasLongContext = true
                }
                
            } catch {
                // If probing fails, just use the basic capabilities from the name
                print("Warning: Could not probe model capabilities: \(error.localizedDescription)")
            }
        }
        
        return capabilities
    }
    
    /// Tests if a model has good code generation capabilities
    /// - Parameter modelName: Name of the model to test
    /// - Returns: True if the model is good at code generation
    private func testCodeCapabilities(modelName: String) async throws -> Bool {
        // Simple code generation test
        let prompt = "Write a simple function that calculates the factorial of a number in Swift."
        let parameters = ModelParameters(temperature: 0.1, maxTokens: 300)
        
        do {
            let response = try await quickModelCompletion(modelName: modelName, prompt: prompt, parameters: parameters)
            
            // Check for code markers and Swift syntax
            let hasCodeBlocks = response.contains("```swift") || response.contains("```") || response.contains("func ")
            let hasFactorialFunction = response.contains("func factorial") || 
                                      response.contains("func calculate") || 
                                      response.contains("return n *")
            
            return hasCodeBlocks && hasFactorialFunction
        } catch {
            // If test fails, assume no code capabilities
            print("Code capability test failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Tests if a model is optimized for terminal commands
    /// - Parameter modelName: Name of the model to test
    /// - Returns: True if the model is good at generating commands
    private func testCommandCapabilities(modelName: String) async throws -> Bool {
        // Simple command generation test
        let prompt = "How do I list all files in a directory, including hidden ones, with detailed information?"
        let parameters = ModelParameters(temperature: 0.1, maxTokens: 200)
        
        do {
            let response = try await quickModelCompletion(modelName: modelName, prompt: prompt, parameters: parameters)
            
            // Check for common command patterns
            let hasLsCommand = response.contains("ls -la") || response.contains("ls -al") || response.contains("ls --all")
            let hasCommandExplanation = response.contains("list") && response.contains("file")
            
            return hasLsCommand && hasCommandExplanation
        } catch {
            // If test fails, assume no special command capabilities
            print("Command capability test failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Detects approximate token limit for a model
    /// - Parameter modelName: Name of the model to test
    /// - Returns: Approximate token limit
    private func detectTokenLimit(modelName: String) async throws -> Int {
        // Try to extract from model name first
        if modelName.contains("32k") {
            return 32000
        } else if modelName.contains("16k") {
            return 16000
        } else if modelName.contains("8k") {
            return 8000
        } else if modelName.contains("4k") {
            return 4000
        } else if modelName.contains("2k") {
            return 2000
        }
        
        // Common model families and their typical token limits
        if modelName.contains("llama3:70b") {
            return 8192
        } else if modelName.contains("llama3") || modelName.contains("llama3:8b") {
            return 8192
        } else if modelName.contains("llama2:70b") {
            return 4096
        } else if modelName.contains("llama2") {
            return 4096
        } else if modelName.contains("mistral") {
            return 8192
        } else if modelName.contains("dolphin") {
            return 8192
        } else if modelName.contains("phi") {
            return 2048
        } else if modelName.contains("gemma:7b") {
            return 8192
        } else if modelName.contains("gemma:2b") {
            return 8192
        }
        
        // Default fallback
        return 4096
    }
    
    /// Performs a quick completion to test model capabilities
    /// - Parameters:
    ///   - modelName: Name of the model to use
    ///   - prompt: Prompt to test with
    ///   - parameters: Model parameters
    /// - Returns: Completion response
    private func quickModelCompletion(
        modelName: String, 
        prompt: String,
        parameters: ModelParameters
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("api/generate")
        let timeout = self.timeoutInterval
        
        // Create parameters dictionary
        let paramDict: [String: Any] = [
            "model": modelName,
            "prompt": prompt,
            "stream": false,
            "options": [
                "temperature": parameters.temperature,
                "num_predict": parameters.maxTokens
            ],
        ]
        
        // Convert parameters to JSON
        let jsonData = try JSONSerialization.data(withJSONObject: paramDict)
        
        // Create URLRequest
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        
        // Perform request with a short timeout for quick testing
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let response = jsonResponse["response"] as? String {
                return response
            } else {
                throw OllamaError.decodingError
            }
        } catch {
            throw OllamaError.apiError("Quick completion failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Parameter Tuning and Optimization
    
    /// Detects optimal parameters for a specific model
    /// - Parameter modelName: Name of the model
    /// - Returns: Dictionary of optimal parameters
    private func detectOptimalParameters(for modelName: String) async -> [String: Any] {
        var parameters: [String: Any] = [:]
        
        // Base temperature settings based on model family
        if modelName.contains("llama3") {
            parameters["defaultTemperature"] = 0.7
            parameters["codeTemperature"] = 0.2
            parameters["commandTemperature"] = 0.3
        } else if modelName.contains("mistral") || modelName.contains("mixtral") {
            parameters["defaultTemperature"] = 0.7
            parameters["codeTemperature"] = 0.3
            parameters["commandTemperature"] = 0.4
        } else if modelName.contains("phi") {
            parameters["defaultTemperature"] = 0.8
            parameters["codeTemperature"] = 0.4
            parameters["commandTemperature"] = 0.5
        } else if modelName.contains("gemma") {
            parameters["defaultTemperature"] = 0.7
            parameters["codeTemperature"] = 0.3
            parameters["commandTemperature"] = 0.4
        } else {
            // Default values for unknown models
            parameters["defaultTemperature"] = 0.8
            parameters["codeTemperature"] = 0.4
            parameters["commandTemperature"] = 0.5
        }
        
        // Set other parameters like top-p, top-k based on model size
        if modelName.contains("70b") || modelName.contains("instruct") {
            parameters["top_p"] = 0.9
            parameters["top_k"] = 40
            parameters["repeat_penalty"] = 1.1
        } else if modelName.contains("34b") || modelName.contains("13b") {
            parameters["top_p"] = 0.8
            parameters["top_k"] = 40
            parameters["repeat_penalty"] = 1.1
        } else {
            parameters["top_p"] = 0.7
            parameters["top_k"] = 40
            parameters["repeat_penalty"] = 1.05
        }
        
        return parameters
    }
    
    /// Gets optimal parameters for a specific task type
    /// - Parameters:
    ///   - modelName: Name of the model
    ///   - taskType: Type of task
    /// - Returns: Optimized model parameters
    public func getOptimalParameters(
        for modelName: String,
        taskType: ModelTaskType
    ) async -> ModelParameters {
        // Get cached parameters if available
        guard let metadata = modelMetadataCache[modelName] else {
            // Use default parameters if not cached
            return getDefaultParameters(for: taskType)
        }
        
        // Extract parameters from cache
        let params = metadata.parameters
        
        // Apply task-specific adjustments
        switch taskType {
        case .general:
            return ModelParameters(
                temperature: params["defaultTemperature"] as? Double ?? 0.7,
                maxTokens: 4000,
                topP: params["top_p"] as? Double ?? 0.9,
                topK: params["top_k"] as? Int ?? 40,
                repeatPenalty: params["repeat_penalty"] as? Double ?? 1.1
            )
            
        case .code:
            return ModelParameters(
                temperature: params["codeTemperature"] as? Double ?? 0.2,
                maxTokens: 4000,
                topP: params["top_p"] as? Double ?? 0.95,
                topK: params["top_k"] as? Int ?? 40,
                repeatPenalty: params["repeat_penalty"] as? Double ?? 1.2
            )
            
        case .command:
            return ModelParameters(
                temperature: params["commandTemperature"] as? Double ?? 0.3,
                maxTokens: 1000,
                topP: params["top_p"] as? Double ?? 0.9,
                topK: params["top_k"] as? Int ?? 50,
                repeatPenalty: params["repeat_penalty"] as? Double ?? 1.1
            )
            
        case .creative:
            return ModelParameters(
                temperature: params["defaultTemperature"] as? Double ?? 0.9,
                maxTokens: 4000,
                topP: params["top_p"] as? Double ?? 0.9,
    
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
