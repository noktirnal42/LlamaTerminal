import Foundation

/// Represents an AI model available through Ollama
public struct AIModel: Identifiable, Hashable, Codable, Sendable {
    public var id: String

    /// Display name of the model
    public var name: String

    /// Size of the model in bytes
    public var size: UInt64

    /// Last modification timestamp
    public var modified: Date

    /// Capabilities of the model
    public var capabilities: ModelCapabilities

    public init(
        id: String, name: String, size: UInt64, modified: Date,
        capabilities: ModelCapabilities = .init()
    ) {
        self.id = id
        self.name = name
        self.size = size
        self.modified = modified
        self.capabilities = capabilities
    }

    /// Creates a user-friendly size string (e.g., "4.7 GB")
    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    /// Creates a user-friendly date string
    public var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: modified, relativeTo: Date())
    }

    // Easy comparison implementation
    public static func == (lhs: AIModel, rhs: AIModel) -> Bool {
        return lhs.id == rhs.id
    }

    // Hashing implementation for Hashable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Represents the different capabilities of a model
public struct ModelCapabilities: Codable, Hashable, Sendable {
    /// Whether the model is suitable for code generation
    public var isCodeCapable: Bool

    /// Whether the model can process images (multimodal)
    public var isMultimodal: Bool

    /// Whether the model is optimized for terminal commands
    public var isCommandOptimized: Bool

    public init(
        isCodeCapable: Bool = false, isMultimodal: Bool = false, isCommandOptimized: Bool = false
    ) {
        self.isCodeCapable = isCodeCapable
        self.isMultimodal = isMultimodal
        self.isCommandOptimized = isCommandOptimized
    }
}

/// Represents the model type based on naming conventions
public enum ModelType {
    case code
    case general
    case multimodal
    case command
    case unknown

    /// Determines the model type based on name heuristics
    public static func determine(from name: String) -> ModelType {
        let lowercasedName = name.lowercased()

        if lowercasedName.contains("code") || lowercasedName.contains("llama:13b")
            || lowercasedName.contains("deepseek")
        {
            return .code
        } else if lowercasedName.contains("vision") || lowercasedName.contains("llava") {
            return .multimodal
        } else if lowercasedName.contains("command") || lowercasedName.contains("terminal") {
            return .command
        } else if lowercasedName.contains("llama") || lowercasedName.contains("mistral")
            || lowercasedName.contains("gemma")
        {
            return .general
        } else {
            return .unknown
        }
    }
}
