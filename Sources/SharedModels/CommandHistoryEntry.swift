import Foundation

/// A history entry representing a command executed in the terminal
/// with additional metadata for analysis and reference.
public struct CommandHistoryEntry: Codable, Equatable, Identifiable {
    /// Unique identifier for the entry
    public let id: UUID
    
    /// The command that was executed
    public let command: String
    
    /// Timestamp when the command was executed
    public let timestamp: Date
    
    /// Exit code of the command (nil if not available or command is still running)
    public let exitCode: Int?
    
    /// Optional output from the command execution
    public let output: String?
    
    /// Working directory when the command was executed
    public let workingDirectory: String?
    
    /// Flag indicating whether this was a command input (vs output entry)
    public let isCommand: Bool
    
    /// Initialize a new command history entry
    /// - Parameters:
    ///   - id: Unique identifier (defaults to a new UUID if not provided)
    ///   - command: The command that was executed
    ///   - timestamp: Timestamp when the command was executed (defaults to current time)
    ///   - exitCode: Exit code from the command (nil if not available)
    ///   - output: Optional output from the command
    ///   - workingDirectory: Working directory when the command was executed
    ///   - isCommand: Whether this entry represents a command input (vs output)
    public init(
        id: UUID = UUID(),
        command: String,
        timestamp: Date = Date(),
        exitCode: Int? = nil,
        output: String? = nil,
        workingDirectory: String? = nil,
        isCommand: Bool = true
    ) {
        self.id = id
        self.command = command
        self.timestamp = timestamp
        self.exitCode = exitCode
        self.output = output
        self.workingDirectory = workingDirectory
        self.isCommand = isCommand
    }
    
    /// Initialize a history entry from a command result
    /// - Parameters:
    ///   - result: The command result to create the entry from
    ///   - workingDirectory: Working directory when command was executed
    ///   - isCommand: Whether this entry represents a command input (vs output)
    public init(
        from result: CommandResult,
        workingDirectory: String? = nil,
        isCommand: Bool = true
    ) {
        self.id = UUID()
        self.command = result.command
        self.timestamp = result.timestamp
        self.exitCode = result.exitCode
        self.output = result.output
        self.workingDirectory = workingDirectory
        self.isCommand = isCommand
    }
}

/// Represents the result of a command execution
public struct CommandResult: Codable, Equatable {
    /// The command that was executed
    public let command: String
    
    /// Timestamp when the command was executed
    public let timestamp: Date
    
    /// Exit code of the command (nil if not available or command is still running)
    public let exitCode: Int?
    
    /// Output from the command execution
    public let output: String
    
    /// Flag indicating if the command completed successfully
    public var isSuccessful: Bool {
        exitCode == 0
    }
    
    /// Initialize a new command result
    /// - Parameters:
    ///   - command: The command that was executed
    ///   - timestamp: When the command was executed (defaults to current time)
    ///   - exitCode: Exit code from the command (nil if not available)
    ///   - output: Output from the command
    public init(
        command: String,
        timestamp: Date = Date(),
        exitCode: Int? = nil,
        output: String
    ) {
        self.command = command
        self.timestamp = timestamp
        self.exitCode = exitCode
        self.output = output
    }
}

