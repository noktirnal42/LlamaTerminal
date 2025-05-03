import Foundation

/// Represents the state of a task in the terminal
public struct TaskState: Identifiable, Codable, Equatable {
    /// Unique identifier for the task
    public let id: UUID?
    
    /// Type of task
    public let type: TaskType
    
    /// Description of the task
    public let description: String
    
    /// Current status
    public var status: TaskStatus
    
    /// When the task was created
    public let createdAt: Date
    
    /// When the task was last updated
    public var updatedAt: Date
    
    /// When the task was completed (if applicable)
    public var completedAt: Date?
    
    /// Task-specific data
    public var data: (any TaskData)?
    
    /// Additional context or metadata
    public var context: [String: String]?
    
    /// Number of retry attempts
    public var retryCount: Int
    
    /// Whether the task can be automatically recovered
    public var canAutoRecover: Bool
    
    /// Priority for recovery (higher = more important)
    public var recoveryPriority: Int
    
    private enum CodingKeys: String, CodingKey {
        case id, type, description, status, createdAt, updatedAt
        case completedAt, data, context, retryCount, canAutoRecover
        case recoveryPriority
    }
    
    public init(
        id: UUID? = UUID(),
        type: TaskType,
        description: String,
        status: TaskStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        data: (any TaskData)? = nil,
        context: [String: String]? = nil,
        retryCount: Int = 0,
        canAutoRecover: Bool = false,
        recoveryPriority: Int = 0
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.data = data
        self.context = context
        self.retryCount = retryCount
        self.canAutoRecover = canAutoRecover
        self.recoveryPriority = recoveryPriority
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(description, forKey: .description)
        try container.encode(status, forKey: .status)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(context, forKey: .context)
        try container.encode(retryCount, forKey: .retryCount)
        try container.encode(canAutoRecover, forKey: .canAutoRecover)
        try container.encode(recoveryPriority, forKey: .recoveryPriority)
        
        if let taskData = data {
            var dataContainer = container.nestedContainer(keyedBy: TaskDataCodingKeys.self, forKey: .data)
            try dataContainer.encode(taskData.dataType, forKey: .type)
            try dataContainer.encode(taskData, forKey: .value)
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID?.self, forKey: .id)
        type = try container.decode(TaskType.self, forKey: .type)
        description = try container.decode(String.self, forKey: .description)
        status = try container.decode(TaskStatus.self, forKey: .status)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        context = try container.decodeIfPresent([String: String].self, forKey: .context)
        retryCount = try container.decode(Int.self, forKey: .retryCount)
        canAutoRecover = try container.decode(Bool.self, forKey: .canAutoRecover)
        recoveryPriority = try container.decode(Int.self, forKey: .recoveryPriority)
        
        if container.contains(.data) {
            let dataContainer = try container.nestedContainer(keyedBy: TaskDataCodingKeys.self, forKey: .data)
            let dataType = try dataContainer.decode(String.self, forKey: .type)
            
            switch dataType {
            case "userCommand":
                data = try dataContainer.decode(UserCommandData.self, forKey: .value)
            case "aiCommand":
                data = try dataContainer.decode(AICommandData.self, forKey: .value)
            case "fileOperation":
                data = try dataContainer.decode(FileOperationData.self, forKey: .value)
            case "sessionState":
                data = try dataContainer.decode(SessionStateData.self, forKey: .value)
            default:
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: dataContainer.codingPath,
                        debugDescription: "Unknown task data type: \(dataType)"
                    )
                )
            }
        } else {
            data = nil
        }
    }
    
    private enum TaskDataCodingKeys: String, CodingKey {
        case type, value
    }
}

// Equatable conformance for TaskState
extension TaskState {
    public static func == (lhs: TaskState, rhs: TaskState) -> Bool {
        guard lhs.id == rhs.id,
              lhs.type == rhs.type,
              lhs.description == rhs.description,
              lhs.status == rhs.status,
              lhs.createdAt == rhs.createdAt,
              lhs.updatedAt == rhs.updatedAt,
              lhs.completedAt == rhs.completedAt,
              lhs.context == rhs.context,
              lhs.retryCount == rhs.retryCount,
              lhs.canAutoRecover == rhs.canAutoRecover,
              lhs.recoveryPriority == rhs.recoveryPriority else {
            return false
        }
        
        // Compare TaskData if present
        switch (lhs.data, rhs.data) {
        case (.none, .none):
            return true
        case (.some(let lhsData), .some(let rhsData)):
            return lhsData.dataType == rhsData.dataType &&
                   lhsData.metadata == rhsData.metadata
        default:
            return false
        }
    }
}

/// Types of tasks that can be managed
public enum TaskType: String, Codable {
    case userCommand
    case aiCommand
    case fileOperation
    case sessionState
}

/// Status of a task
public enum TaskStatus: String, Codable {
    case pending
    case inProgress
    case completed
    case failed
    case paused
    case recovering
}

