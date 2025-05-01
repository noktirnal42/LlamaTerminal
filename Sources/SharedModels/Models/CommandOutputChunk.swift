import Foundation

/// Represents a chunk of command output from a terminal session
public struct CommandOutputChunk: Codable, Equatable, Sendable {
    /// The source type of the output
    public enum OutputType: String, Codable, Equatable {
        /// Standard output stream
        case stdout
        /// Standard error stream
        case stderr
        /// System message (not from command execution)
        case system
        /// Control sequence or special terminal output
        case control
    }
    
    /// The raw content bytes of the output chunk
    public let data: Data
    
    /// The timestamp when the chunk was received
    public let timestamp: Date
    
    /// The type of output stream this chunk came from
    public let outputType: OutputType
    
    /// Additional metadata about this chunk
    public let metadata: [String: String]
    
    /// Whether this chunk contains ANSI/VT100 control sequences
    public let containsControlSequences: Bool
    
    /// Whether this chunk represents a completed command
    public let isCommandCompletion: Bool
    
    /// Create a new command output chunk
    /// - Parameters:
    ///   - data: The raw output bytes
    ///   - outputType: The type of output stream (stdout, stderr, etc.)
    ///   - timestamp: When the chunk was received (defaults to now)
    ///   - metadata: Additional context information about the output
    ///   - containsControlSequences: Whether the data contains terminal control sequences
    ///   - isCommandCompletion: Whether this chunk signifies command completion
    public init(
        data: Data,
        outputType: OutputType = .stdout,
        timestamp: Date = Date(),
        metadata: [String: String] = [:],
        containsControlSequences: Bool = false,
        isCommandCompletion: Bool = false
    ) {
        self.data = data
        self.outputType = outputType
        self.timestamp = timestamp
        self.metadata = metadata
        self.containsControlSequences = containsControlSequences
        self.isCommandCompletion = isCommandCompletion
    }
    
    /// Convenience initializer for creating a chunk from string content
    /// - Parameters:
    ///   - string: The string content of the output
    ///   - outputType: The type of output stream (stdout, stderr, etc.)
    ///   - timestamp: When the chunk was received (defaults to now)
    ///   - metadata: Additional context information about the output
    ///   - containsControlSequences: Whether the string contains terminal control sequences
    ///   - isCommandCompletion: Whether this chunk signifies command completion
    public init(
        string: String,
        outputType: OutputType = .stdout,
        timestamp: Date = Date(),
        metadata: [String: String] = [:],
        containsControlSequences: Bool = false,
        isCommandCompletion: Bool = false
    ) {
        self.init(
            data: Data(string.utf8),
            outputType: outputType,
            timestamp: timestamp,
            metadata: metadata,
            containsControlSequences: containsControlSequences,
            isCommandCompletion: isCommandCompletion
        )
    }
    
    /// The UTF-8 string representation of the output chunk
    public var stringValue: String? {
        String(data: data, encoding: .utf8)
    }
    
    /// Creates a system message chunk
    /// - Parameters:
    ///   - message: The system message
    ///   - timestamp: When the message was generated
    /// - Returns: A system message output chunk
    public static func systemMessage(_ message: String, timestamp: Date = Date()) -> CommandOutputChunk {
        CommandOutputChunk(
            string: message,
            outputType: .system,
            timestamp: timestamp,
            metadata: ["type": "system_message"]
        )
    }
    
    /// Creates an error message chunk
    /// - Parameters:
    ///   - message: The error message
    ///   - timestamp: When the error occurred
    /// - Returns: An error message output chunk
    public static func errorMessage(_ message: String, timestamp: Date = Date()) -> CommandOutputChunk {
        CommandOutputChunk(
            string: message,
            outputType: .stderr,
            timestamp: timestamp,
            metadata: ["type": "error_message"]
        )
    }
    
    /// Creates a command completion chunk
    /// - Parameters:
    ///   - exitCode: The command exit code
    ///   - timestamp: When the command completed
    /// - Returns: A command completion output chunk
    public static func commandCompletion(exitCode: Int, timestamp: Date = Date()) -> CommandOutputChunk {
        CommandOutputChunk(
            string: "",
            outputType: .control,
            timestamp: timestamp,
            metadata: ["exitCode": String(exitCode)],
            isCommandCompletion: true
        )
    }
}

