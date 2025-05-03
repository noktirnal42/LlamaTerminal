import Foundation

/// Protocol defining the base requirements for task-specific data
public protocol TaskData: Codable, Equatable {
    /// Unique identifier for the task data type
    var dataType: String { get }
    
    /// Optional metadata dictionary
    var metadata: [String: String] { get }
}

/// Data for user-initiated command tasks
public struct UserCommandData: TaskData {
    public let command: String
    public let workingDirectory: String
    public let environment: [String: String]
    public let metadata: [String: String]
    
    public var dataType: String { "userCommand" }
    
    public init(
        command: String,
        workingDirectory: String,
        environment: [String: String] = [:],
        metadata: [String: String] = [:]
    ) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.metadata = metadata
    }
}

/// Data for AI-suggested command tasks
public struct AICommandData: TaskData {
    public let command: String
    public let explanation: String
    public let confidence: Double
    public let metadata: [String: String]
    
    public var dataType: String { "aiCommand" }
    
    public init(
        command: String,
        explanation: String,
        confidence: Double,
        metadata: [String: String] = [:]
    ) {
        self.command = command
        self.explanation = explanation
        self.confidence = confidence
        self.metadata = metadata
    }
}

/// Data for file operation tasks
public struct FileOperationData: TaskData {
    public enum Operation: String, Codable {
        case create, delete, move, copy, modify
    }
    
    public let operation: Operation
    public let sourcePath: String
    public let destinationPath: String?
    public let metadata: [String: String]
    
    public var dataType: String { "fileOperation" }
    
    public init(
        operation: Operation,
        sourcePath: String,
        destinationPath: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.operation = operation
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.metadata = metadata
    }
}

/// Data for session state tasks
public struct SessionStateData: TaskData {
    public let sessionId: String
    public let state: [String: String]
    public let metadata: [String: String]
    
    public var dataType: String { "sessionState" }
    
    public init(
        sessionId: String,
        state: [String: String],
        metadata: [String: String] = [:]
    ) {
        self.sessionId = sessionId
        self.state = state
        self.metadata = metadata
    }
}

