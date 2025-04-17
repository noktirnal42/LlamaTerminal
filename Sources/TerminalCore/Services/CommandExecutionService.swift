import Foundation

/// Service responsible for safely executing shell commands
public actor CommandExecutionService {
    /// Current working directory for command execution
    private var workingDirectory: URL
    
    /// Environment variables for command execution
    private var environment: [String: String]
    
    /// Default timeout for command execution (in seconds)
    private let defaultTimeout: TimeInterval = 300 // 5 minutes
    
    /// Shell executable path
    private let shellPath: String
    
    /// Initializes a new CommandExecutionService
    /// - Parameters:
    ///   - workingDirectory: Initial working directory (defaults to user's home)
    ///   - environment: Initial environment variables (defaults to current process environment)
    ///   - shellPath: Path to shell executable (defaults to /bin/zsh)
    public init(
        workingDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        shellPath: String = "/bin/zsh"
    ) {
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.shellPath = shellPath
    }
    
    /// Executes a command and returns the complete result
    /// - Parameters:
    ///   - command: Command to execute
    ///   - timeout: Optional timeout duration (defaults to 5 minutes)
    /// - Returns: CommandResult containing output and status
    public func executeCommand(
        _ command: String,
        timeout: TimeInterval? = nil
    ) async throws -> CommandResult {
        let startTime = Date()
        
        // Create process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-c", command]
        process.currentDirectoryURL = workingDirectory
        process.environment = environment
        
        // Setup output pipes
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Track output asynchronously
        var outputData = Data()
        var errorData = Data()
        
        let outputTask = Task {
            for try await line in outputPipe.fileHandleForReading.bytes {
                outputData.append(line)
            }
        }
        
        let errorTask = Task {
            for try await line in errorPipe.fileHandleForReading.bytes {
                errorData.append(line)
            }
        }
        
        // Start process with error handling
        do {
            try process.run()
        } catch {
            throw CommandExecutionError.processCreationFailed(error.localizedDescription)
        }
        
        // Setup timeout if specified
        let actualTimeout = timeout ?? defaultTimeout
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(actualTimeout * 1_000_000_000))
            if process.isRunning {
                process.terminate()
                throw CommandExecutionError.timeout(command: command, duration: actualTimeout)
            }
        }
        
        // Wait for process to complete with cancellation handling
        try await withTaskCancellationHandler {
            try await process.waitUntilExit()
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
        
        // Cancel timeout task since process completed
        timeoutTask.cancel()
        
        // Wait for output and error handling to complete
        try await outputTask.value
        try await errorTask.value
        
        // Combine output and error streams
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        let combinedOutput = [output, error].filter { !$0.isEmpty }.joined(separator: "\n")
        
        let duration = Date().timeIntervalSince(startTime)
        
        return CommandResult(
            command: command,
            output: combinedOutput,
            exitCode: Int(process.terminationStatus),
            duration: duration
        )
    }
    
    /// Executes a command and streams the output in real-time
    /// - Parameters:
    ///   - command: Command to execute
    ///   - timeout: Optional timeout duration
    /// - Returns: An asynchronous stream of command output chunks
    public func executeCommandWithStreaming(
        _ command: String,
        timeout: TimeInterval? = nil
    ) -> AsyncThrowingStream<CommandOutputChunk, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                let startTime = Date()
                
                // Create process
                let process = Process()
                process.executableURL = URL(fileURLWithPath: shellPath)
                process.arguments = ["-c", command]
                process.currentDirectoryURL = workingDirectory
                process.environment = environment
                
                // Setup output pipes
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                
                // Setup file handles for reading
                let outputHandle = outputPipe.fileHandleForReading
                let errorHandle = errorPipe.fileHandleForReading
                
                // Start process
                do {
                    try process.run()
                } catch {
                    continuation.finish(throwing: CommandExecutionError.processCreationFailed(error.localizedDescription))
                    return
                }
                
                // Setup timeout
                let actualTimeout = timeout ?? defaultTimeout
                let timeoutTask = Task {
                    try await Task.sleep(nanoseconds: UInt64(actualTimeout * 1_000_000_000))
                    if process.isRunning {
                        process.terminate()
                        continuation.finish(throwing: CommandExecutionError.timeout(command: command, duration: actualTimeout))
                    }
                }
                
                // Handle cancellation
                continuation.onTermination = { @Sendable _ in
                    timeoutTask.cancel()
                    if process.isRunning {
                        process.terminate()
                    }
                }
                
                // Process output in parallel
                Task {
                    do {
                        var buffer = Data()
                        for try await byte in outputHandle.bytes {
                            buffer.append(byte)
                            
                            // If we get a newline or buffer gets too large, yield the content
                            if byte == 10 || buffer.count > 1024 {
                                if let output = String(data: buffer, encoding: .utf8) {
                                    continuation.yield(CommandOutputChunk(
                                        content: output,
                                        type: .standardOutput,
                                        isComplete: false
                                    ))
                                }
                                buffer = Data()
                            }
                        }
                        
                        // Handle any remaining bytes
                        if !buffer.isEmpty, let output = String(data: buffer, encoding: .utf8) {
                            continuation.yield(CommandOutputChunk(
                                content: output,
                                type: .standardOutput,
                                isComplete: false
                            ))
                        }
                    } catch {
                        // Handle read errors but don't terminate the stream yet
                        // as the error pipe might still have data
                    }
                }
                
                Task {
                    do {
                        var buffer = Data()
                        for try await byte in errorHandle.bytes {
                            buffer.append(byte)
                            
                            // If we get a newline or buffer gets too large, yield the content
                            if byte == 10 || buffer.count > 1024 {
                                if let error = String(data: buffer, encoding: .utf8) {
                                    continuation.yield(CommandOutputChunk(
                                        content: error,
                                        type: .standardError,
                                        isComplete: false
                                    ))
                                }
                                buffer = Data()
                            }
                        }
                        
                        // Handle any remaining bytes
                        if !buffer.isEmpty, let error = String(data: buffer, encoding: .utf8) {
                            continuation.yield(CommandOutputChunk(
                                content: error,
                                type: .standardError,
                                isComplete: false
                            ))
                        }
                    } catch {
                        // Handle read errors but don't terminate the stream yet
                    }
                }
                
                // Wait for process to complete
                do {
                    try await process.waitUntilExit()
                     
                    // Cancel timeout task
                    timeoutTask.cancel()
                    
                    let exitCode = Int(process.terminationStatus)
                    let duration = Date().timeIntervalSince(startTime)
                    
                    // Send completion chunk
                    continuation.yield(CommandOutputChunk(
                        content: "",
                        type: .complete,
                        isComplete: true,
                        exitCode: exitCode,
                        duration: duration
                    ))
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Changes the current working directory
    /// - Parameter path: New working directory path (absolute or relative)
    /// - Returns: Previous working directory path
    @discardableResult
    public func changeWorkingDirectory(_ path: String) throws -> URL {
        let previousDirectory = workingDirectory
        let expandedPath = NSString(string: path).expandingTildeInPath
        
        // Determine if path is absolute or relative
        let newURL: URL
        if path.starts(with: "/") || path.starts(with: "~") {
            newURL = URL(fileURLWithPath: expandedPath)
        } else {
            newURL = workingDirectory.appendingPathComponent(path)
        }
        
        // Verify directory exists
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: newURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw CommandExecutionError.invalidDirectory(path)
        }
        
        workingDirectory = newURL
        return previousDirectory
    }
    
    /// Gets the current working directory
    /// - Returns: URL of the current working directory
    public func getCurrentWorkingDirectory() -> URL {
        return workingDirectory
    }
    
    /// Updates environment variables
    /// - Parameter variables: Dictionary of variables to update
    public func updateEnvironment(_ variables: [String: String]) {
        environment.merge(variables) { _, new in new }
    }
    
    /// Gets the current environment variables
    /// - Returns: Dictionary of environment variables
    public func getEnvironment() -> [String: String] {
        return environment
    }
    
    /// Removes environment variables
    /// - Parameter names: Array of variable names to remove
    public func removeEnvironmentVariables(_ names: [String]) {
        for name in names {
            environment.removeValue(forKey: name)
        }
    }
    
    /// Resets environment variables to system defaults
    public func resetEnvironment() {
        environment = ProcessInfo.processInfo.environment
    }
}

/// Represents a chunk of command output for streaming
public struct CommandOutputChunk: Sendable, Equatable {
    /// The content of this chunk
    public let content: String
    
    /// The type of output
    public let type: OutputType
    
    /// Whether this is the final chunk
    public let isComplete: Bool
    
    /// Exit code (only present in final chunk)
    public let exitCode: Int?
    
    /// Command duration (only present in final chunk)
    public let duration: TimeInterval?
    
    /// Types of command output
    public enum OutputType: String, Sendable, Equatable {
        case standardOutput
        case standardError
        case complete
    }
    
    public init(
        content: String,
        type: OutputType,
        isComplete: Bool,
        exitCode: Int? = nil,
        duration: TimeInterval? = nil
    ) {
        self.content = content
        self.type = type
        self.isComplete = isComplete
        self.exitCode = exitCode
        self.duration = duration
    }
}

/// Result of a command execution (used in AIIntegration module as well)
public struct CommandResult: Sendable, Equatable {
    /// The command that was executed
    public let command: String
    
    /// The combined output (stdout and stderr)
    public let output: String
    
    /// The exit code of the command
    public let exitCode: Int
    
    /// The duration of the command execution
    public let duration: TimeInterval
    
    public init(
        command: String,
        output: String,
        exitCode: Int,
        duration: TimeInterval
    ) {
        self.command = command
        self.output = output
        self.exitCode = exitCode
        self.duration = duration
    }
    
    /// Whether the command was successful
    public var isSuccessful: Bool {
        return exitCode == 0
    }
}

/// Errors that can occur during command execution
public enum CommandExecutionError: Error, LocalizedError {
    case timeout(command: String, duration: TimeInterval)
    case invalidDirectory(String)
    case processCreationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .timeout(let command, let duration):
            return "Command timed out after \(duration) seconds: \(command)"
        case .invalidDirectory(let path):
            return "Invalid directory path: \(path)"
        case .processCreationFailed(let reason):
            return "Failed to create process: \(reason)"
        }
    }
}

