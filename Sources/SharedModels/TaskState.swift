import Foundation

/// Represents the state of a task for persistence and recovery
public struct TaskState: Codable, Identifiable, Equatable {
    /// Unique identifier for the task
    public var id: UUID?
    
    /// Type of task
    public var type: TaskType
    
    /// Current status of the task
    public var status: TaskStatus
    
    /// Description of the task
    public var description: String
    
    /// Task-specific data
    public var data: TaskData?
    
    /// When the task was created
    public let createdAt: Date
    
    /// When the task was last updated
    public var updatedAt: Date
    
    /// When the task was completed or failed
    public var completedAt: Date?
    
    /// Number of retry attempts
    public var retryCount: Int = 0
    
    /// Error message if task failed
    public var error: String?
    
    /// Maximum retry count
    public let maxRetries: Int
    
    /// Additional context for the task
    public var context: [String: String]?
    
    /// Initializes a new task state
    /// - Parameters:
    ///   - id: Unique identifier (optional)
    ///   - type: Type of task
    ///   - description: Description of the task
    ///   - data: Task-specific data
    ///   - status: Initial status (default: pending)
    ///   - maxRetries: Maximum retry count (default: 3)
    ///   - context: Additional context information
    public init(
        id: UUID? = nil,
        type: TaskType,
        description: String,
        data: TaskData? = nil,
        status: TaskStatus = .pending,
        maxRetries: Int = 3,
        context: [String: String]? = nil
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.data = data
        self.status = status
        self.createdAt = Date()
        self.updatedAt = Date()
        self.maxRetries = maxRetries
        self.context = context
    }
}

/// Types of tasks that can be persisted
public enum TaskType: String, Codable {
    case aiCommand      // AI-generated command execution
    case userCommand    // User-entered command execution
    case fileOperation  // File manipulation operation
    case sessionState   // Terminal session state
    case aiTask         // General AI task
    case custom         // Custom task type
}

/// Status of a task
public enum TaskStatus: String, Codable {
    case pending      // Task is ready but not started
    case inProgress   // Task is currently executing
    case paused       // Task execution is paused
    case recovering   // Task is being recovered after a crash
    case completed    // Task completed successfully
    case failed       // Task failed
}

/// Protocol for task-specific data
public protocol TaskData: Codable, Equatable {
    /// Type of the task data
    var dataType: String { get }
}

/// Data for AI command execution
public struct AICommandData: TaskData, Codable, Equatable {
    public let dataType: String = "aiCommand"
    
    /// The command to execute
    public let command: String
    
    /// AI mode in use
    public let aiMode: String
    
    /// Model used for generation
    public let model: String?
    
    /// Context for command execution
    public let context: [String: String]?
    
    /// Whether command requires confirmation
    public let requiresConfirmation: Bool
    
    /// Initializes new AI command data
    public init(
        command: String,
        aiMode: String,
        model: String? = nil,
        context: [String: String]? = nil,
        requiresConfirmation: Bool = true
    ) {
        self.command = command
        self.aiMode = aiMode
        self.model = model
        self.context = context
        self.requiresConfirmation = requiresConfirmation
    }
}

/// Data for user command execution
public struct UserCommandData: TaskData, Codable, Equatable {
    public let dataType: String = "userCommand"
    
    /// The command to execute
    public let command: String
    
    /// Working directory for execution
    public let workingDirectory: String?
    
    /// Environment variables for execution
    public let environment: [String: String]?
    
    /// Initializes new user command data
    public init(
        command: String,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil
    ) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.environment = environment
    }
}

/// Data for file operation
public struct FileOperationData: TaskData, Codable, Equatable {
    public let dataType: String = "fileOperation"
    
    /// Type of file operation
    public let operation: FileOperationType
    
    /// Source file path
    public let sourcePath: String
    
    /// Destination file path (for move/copy)
    public let destinationPath: String?
    
    /// File content (for write operations)
    public let content: String?
    
    /// Initializes new file operation data
    public init(
        operation: FileOperationType,
        sourcePath: String,
        destinationPath: String? = nil,
        content: String? = nil
    ) {
        self.operation = operation
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.content = content
    }
    
    /// Types of file operations
    public enum FileOperationType: String, Codable {
        case read
        case write
        case append
        case delete
        case move
        case copy
        case createDirectory
    }
}

/// Data for terminal session state
public struct SessionStateData: TaskData, Codable, Equatable {
    public let dataType: String = "sessionState"
    
    /// Session identifier
    public let sessionId: UUID
    
    /// Terminal dimensions
    public let dimensions: TerminalDimensions
    
    /// Current working directory
    public let workingDirectory: String
    
    /// Additional session state
    public let state: [String: String]
    
    /// Initializes new session state data
    public init(
        sessionId: UUID,
        dimensions: TerminalDimensions,
        workingDirectory: String,
        state: [String: String] = [:]
    ) {
        self.sessionId = sessionId
        self.dimensions = dimensions
        self.workingDirectory = workingDirectory
        self.state = state
    }
    
    /// Terminal dimensions
    public struct TerminalDimensions: Codable, Equatable {
        public let columns: Int
        public let rows: Int
        
        public init(columns: Int, rows: Int) {
            self.columns = columns
            self.rows = rows
        }
    }
}

/// AI preferences for persistence
public struct AIPreferences: Codable, Equatable {
    /// Whether AI is enabled
    public var isEnabled: Bool = false
    
    /// Current AI mode
    public var mode: String = "disabled"
    
    /// Currently selected model
    public var modelName: String?
    
    /// Model preferences by mode
    public var modelPreferences: [String: String] = [:]
    
    /// Whether to automatically suggest commands
    public var autoSuggest: Bool = true
    
    /// Security level for AI operations
    public var securityLevel: String = "standard"
    
    /// Custom context for AI
    public var customContext: [String: String] = [:]
    
    /// Initializes with default preferences
    public init() {}
}

/// Terminal state for persistence
public struct TerminalState: Codable, Equatable {
    /// Terminal dimensions
    public var cols: Int = 80
    public var rows: Int = 25
    
    /// Current working directory
    public var workingDirectory: String?
    
    /// Theme settings
    public var themeName: String = "dark"
    
    /// Whether syntax highlighting is enabled
    public var syntaxHighlightingEnabled: Bool = true
    
    /// Font settings
    public var fontName: String = "Menlo"
    public var fontSize: Double = 13.0
    
    /// Whether to show line numbers
    public var showLineNumbers: Bool = false
    
    /// Initializes with default terminal state
    public init() {}
}

/// Priority for task recovery
public enum RecoveryPriority: Int, Comparable {
    case low = 0
    case medium = 1
    case high = 2
    case critical = 3
    
    public static func < (lhs: RecoveryPriority, rhs: RecoveryPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

extension TaskState {
    /// Recovery priority for this task
    public var recoveryPriority: RecoveryPriority {
        switch type {
        case .sessionState:
            return .critical
        case .aiCommand:
            return .high
        case .fileOperation:
            return .high
        case .userCommand:
            return .medium
        default:
            return .low
        }
    }
    
    /// Whether this task should be auto-recovered without user confirmation
    public var canAutoRecover: Bool {
        // Don't auto-recover potentially destructive commands
        if let commandData = data as? UserCommandData,
           commandData.command.contains("rm ") || commandData.command.contains("sudo ") {
            return false
        }
        
        // Don't auto-recover file operations except reads
        if let fileData = data as? FileOperationData,
           fileData.operation != .read {
            return false
        }
        
        // Safe operations can be auto-recovered
        switch type {
        case .sessionState:
            return true
        default:
            return false
        }
    }
}

