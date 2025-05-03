import Foundation
import SwiftTerm
import Darwin

/// Default implementation of process management
public class DefaultProcessManager: ProcessManager {
    
    // MARK: - Properties
    
    /// The underlying local process
    private var localProcess: LocalProcess?
    
    /// Process is running
    public private(set) var isRunning: Bool = false
    
    /// Delegate to notify of process events
    public weak var delegate: ProcessDelegate?
    
    /// Current terminal size
    private var currentSize: winsize = winsize(
        ws_row: 25,
        ws_col: 80,
        ws_xpixel: 0,
        ws_ypixel: 0
    )
    
    /// Internal queue for process operations
    private let processQueue = DispatchQueue(label: "com.llama-terminal.process", qos: .userInitiated)
    
    /// Input buffer for when process is not ready
    private var inputBuffer: Data = Data()
    
    /// Process startup lock
    private let processLock = NSLock()
    
    // MARK: - Initialization
    
    /// Initializes a new process manager
    public init() {}
    
    // MARK: - Process Management
    
    /// Starts a new process
    /// - Parameters:
    ///   - executable: Path to executable
    ///   - args: Arguments
    ///   - environment: Environment variables
    ///   - terminalSize: Terminal dimensions
    public func startProcess(executable: String, args: [String], environment: [String], terminalSize: winsize) {
        print("[ProcessManager] Starting process: \(executable) \(args.joined(separator: " "))")
        
        // Lock to prevent multiple simultaneous starts
        processLock.lock()
        defer { processLock.unlock() }
        
        // Clean up any existing process
        terminateProcess()
        
        // Update current size
        currentSize = terminalSize
        
        // Create new process
        localProcess = LocalProcess()
        guard let process = localProcess else {
            print("[ProcessManager] Error: Failed to create process")
            return
        }
        
        // Set delegate
        process.delegate = self
        
        // Update state
        isRunning = true
        
        // Log environment for debugging
        print("[ProcessManager] Environment: \(environment.count) variables")
        
        // Start the process
        processQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Start process
            process.startProcess(
                executable: executable,
                args: args,
                environment: environment
            )
            
            // Set initial size
            process.setSize(rows: terminalSize.ws_row, cols: terminalSize.ws_col)
            
            // Process any buffered input
            self.processQueue.async { [weak self] in
                guard let self = self, self.isRunning else { return }
                
                if !self.inputBuffer.isEmpty {
                    let buffer = self.inputBuffer
                    self.inputBuffer = Data()
                    process.send(data: ArraySlice(buffer))
                }
            }
        }
    }
    
    /// Terminates the process
    public func terminateProcess() {
        // Lock to prevent race conditions
        processLock.lock()
        defer { processLock.unlock() }
        
        guard isRunning, let process = localProcess else {
            return
        }
        
        print("[ProcessManager] Terminating process")
        
        // Terminate the process
        process.terminate()
        
        // Update state
        isRunning = false
        localProcess = nil
        
        // Clear buffer
        inputBuffer = Data()
    }
    
    /// Sends data to the process
    /// - Parameter data: Data to send
    public func sendToProcess(data: ArraySlice<UInt8>) {
        // Lock for thread safety
        processLock.lock()
        defer { processLock.unlock() }
        
        // Check if process is running
        guard isRunning, let process = localProcess else {
            // Buffer input if process is not ready
            print("[ProcessManager] Process not ready, buffering input")
            inputBuffer.append(contentsOf: data)
            return
        }
        
        // Send data to process
        process.send(data: data)
    }
    
    /// Updates the terminal size
    /// - Parameters:
    ///   - rows: Number of rows
    ///   - cols: Number of columns
    public func updateSize(rows: UInt16, cols: UInt16) {
        print("[ProcessManager] Updating terminal size to \(cols)x\(rows)")
        
        // Lock for thread safety
        processLock.lock()
        defer { processLock.unlock() }
        
        // Update current size
        currentSize.ws_row = rows
        currentSize.ws_col = cols
        
        // Update process size if running
        if isRunning, let process = localProcess {
            process.setSize(rows: rows, cols: cols)
        }
    }
    
    // MARK: - Utility Methods
    
    /// Creates default environment variables
    /// - Returns: Dictionary of environment variables
    public func createDefaultEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        
        // Terminal behavior variables
        environment["TERM"] = "xterm-256color"
        environment["TERMINFO"] = "/usr/share/terminfo"
        environment["COLORTERM"] = "truecolor"
        environment["INSIDE_LLAMA_TERMINAL"] = "1"
        
        // Colors and display variables
        environment["CLICOLOR"] = "1"
        environment["CLICOLOR_FORCE"] = "1"
        
        // Shell variables
        environment["SHELL"] = "/bin/zsh"
        environment["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["HOME"] = ProcessInfo.processInfo.environment["HOME"]
        environment["USER"] = ProcessInfo.processInfo.environment["USER"]
        environment["LOGNAME"] = ProcessInfo.processInfo.environment["USER"]
        
        // Use current directory
        environment["PWD"] = FileManager.default.currentDirectoryPath
        
        // Let shell handle its own initialization (don't override PS1)
        environment.removeValue(forKey: "ZDOTDIR")
        environment.removeValue(forKey: "PS1")
        
        return environment
    }
    
    /// Prepares environment variables for process
    /// - Parameter env: Dictionary of environment variables
    /// - Returns: Array of environment strings
    public func prepareEnvironment(_ env: [String: String]) -> [String] {
        return env.map { "\($0.key)=\($0.value)" }
    }
}

// MARK: - LocalProcessDelegate Implementation

extension DefaultProcessManager: LocalProcessDelegate {
    
    /// Gets the current window size
    public func getWindowSize() -> winsize {
        return currentSize
    }
    
    /// Called when data is received from the process
    /// - Parameter slice: Data received
    public func dataReceived(slice: ArraySlice<UInt8>) {
        // Forward to delegate
        delegate?.dataReceived(slice: slice)
    }
    
    /// Called when the process terminates
    /// - Parameters:
    ///   - process: The process that terminated
    ///   - exitCode: Exit code of the process
    public func processTerminated(_ process: LocalProcess, exitCode: Int32?) {
        print("[ProcessManager] Process terminated with exit code: \(exitCode ?? -1)")
        
        // Update state
        isRunning = false
        
        // Forward to delegate
        delegate?.processTerminated(process, exitCode: exitCode)
    }
}

/// Protocol for process delegation
public protocol ProcessDelegate: AnyObject {
    /// Called when data is received from the process
    /// - Parameter slice: Data received
    func dataReceived(slice: ArraySlice<UInt8>)
    
    /// Called when the process terminates
    /// - Parameters:
    ///   - process: The process that terminated
    ///   - exitCode: Exit code of the process
    func processTerminated(_ process: LocalProcess, exitCode: Int32?)
    
    /// Gets the current window size
    func getWindowSize() -> winsize
}

/// Protocol for terminal state management
public protocol TerminalStateManager: AnyObject {
    /// Current terminal state
    var state: TerminalState { get }
    
    /// Updates the terminal state
    /// - Parameter newState: New state
    func updateState(_ newState: TerminalState)
    
    /// Resets the terminal state
    func resetState()
}

/// Default implementation of terminal state management
public class DefaultTerminalStateManager: TerminalStateManager {
    /// Current terminal state
    public private(set) var state: TerminalState = TerminalState()
    
    /// Initializes a new terminal state manager
    public init() {}
    
    /// Updates the terminal state
    /// - Parameter newState: New state
    public func updateState(_ newState: TerminalState) {
        self.state = newState
    }
    
    /// Resets the terminal state
    public func resetState() {
        self.state = TerminalState()
    }
}

