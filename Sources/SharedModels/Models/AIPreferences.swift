import Foundation

/// User preferences for AI functionality
public struct AIPreferences: Codable {
    /// Whether AI features are enabled
    public var isEnabled: Bool
    
    /// Current AI mode
    public var mode: AIMode
    
    /// Selected model name
    public var modelName: String?
    
    /// Whether to automatically confirm safe actions
    public var autoConfirmSafeActions: Bool
    
    /// Maximum tokens per response
    public var maxTokens: Int
    
    /// Temperature for generation
    public var temperature: Double
    
    public init(
        isEnabled: Bool = false,
        mode: AIMode = .disabled,
        modelName: String? = nil,
        autoConfirmSafeActions: Bool = false,
        maxTokens: Int = 2048,
        temperature: Double = 0.7
    ) {
        self.isEnabled = isEnabled
        self.mode = mode
        self.modelName = modelName
        self.autoConfirmSafeActions = autoConfirmSafeActions
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

