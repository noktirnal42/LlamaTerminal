import Foundation

/// Represents metadata for an AI model, including capabilities and optimal parameters
public struct ModelMetadata: Codable, Hashable, Sendable {
    /// The model's capabilities
    public var capabilities: ModelCapabilities
    
    /// Dictionary of optimal parameters for the model
    public var parameters: [String: Any]
    
    /// Whether the model has been fully initialized with parameter detection
    public var isFullyInitialized: Bool
    
    /// Initializes a new instance of ModelMetadata
    /// - Parameters:
    ///   - capabilities: The model's capabilities
    ///   - parameters: Dictionary of optimal parameters
    ///   - isFullyInitialized: Whether parameter detection has been completed
    public init(
        capabilities: ModelCapabilities,
        parameters: [String: Any],
        isFullyInitialized: Bool = false
    ) {
        self.capabilities = capabilities
        self.parameters = parameters
        self.isFullyInitialized = isFullyInitialized
    }
    
    // Codable conformance for parameters dictionary
    private enum CodingKeys: String, CodingKey {
        case capabilities
        case parameters
        case isFullyInitialized
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        capabilities = try container.decode(ModelCapabilities.self, forKey: .capabilities)
        isFullyInitialized = try container.decode(Bool.self, forKey: .isFullyInitialized)
        
        // Decode parameters dictionary from a property list
        if let data = try? container.decode(Data.self, forKey: .parameters),
           let decodedParams = try? PropertyListSerialization.propertyList(
               from: data,
               options: [],
               format: nil
           ) as? [String: Any] {
            parameters = decodedParams
        } else {
            parameters = [:]
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encode(isFullyInitialized, forKey: .isFullyInitialized)
        
        // Encode parameters dictionary as a property list
        if let data = try? PropertyListSerialization.data(
            fromPropertyList: parameters,
            format: .binary,
            options: 0
        ) {
            try container.encode(data, forKey: .parameters)
        }
    }
    
    // Hashable conformance
    public func hash(into hasher: inout Hasher) {
        hasher.combine(capabilities)
        hasher.combine(isFullyInitialized)
        // Cannot directly hash [String: Any], so use a representation
        for (key, value) in parameters {
            hasher.combine(key)
            if let intValue = value as? Int {
                hasher.combine(intValue)
            } else if let doubleValue = value as? Double {
                hasher.combine(doubleValue)
            } else if let stringValue = value as? String {
                hasher.combine(stringValue)
            } else if let boolValue = value as? Bool {
                hasher.combine(boolValue)
            }
        }
    }
    
    public static func == (lhs: ModelMetadata, rhs: ModelMetadata) -> Bool {
        // Basic equality check - would need refinement for production
        return lhs.capabilities == rhs.capabilities &&
               lhs.isFullyInitialized == rhs.isFullyInitialized &&
               NSDictionary(dictionary: lhs.parameters).isEqual(to: rhs.parameters)
    }
}

/// Parameters for model inference
public struct ModelParameters: Sendable {
    /// Temperature (randomness) setting (0.0-1.0)
    public var temperature: Double
    
    /// Maximum number of tokens to generate
    public var maxTokens: Int
    
    /// Top-p sampling parameter (0.0-1.0)
    public var topP: Double
    
    /// Top-k sampling parameter
    public var topK: Int
    
    /// Penalty for repeating tokens
    public var repeatPenalty: Double
    
    /// Initializes a new instance of ModelParameters
    /// - Parameters:
    ///   - temperature: Temperature setting (0.0-1.0)
    ///   - maxTokens: Maximum number of tokens to generate
    ///   - topP: Top-p sampling parameter (0.0-1.0)
    ///   - topK: Top-k sampling parameter
    ///   - repeatPenalty: Penalty for repeating tokens
    public init(
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        topP: Double = 0.9,
        topK: Int = 40,
        repeatPenalty: Double = 1.1
    ) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.topK = topK
        self.repeatPenalty = repeatPenalty
    }
    
    /// Converts parameters to a dictionary for API requests
    public func toDictionary() -> [String: Any] {
        return [
            "temperature": temperature,
            "num_predict": maxTokens,
            "top_p": topP,
            "top_k": topK,
            "repeat_penalty": repeatPenalty
        ]
    }
}

/// Types of tasks for model parameter optimization
public enum ModelTaskType: String, Codable, Sendable, CaseIterable {
    case general
    case code
    case command
    case creative
    
    public var description: String {
        switch self {
        case .general:
            return "General conversation"
        case .code:
            return "Code generation and explanation"
        case .command:
            return "Terminal command generation"
        case .creative:
            return "Creative writing and content generation"
        }
    }
}

