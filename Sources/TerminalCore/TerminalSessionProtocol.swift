import Foundation
import SwiftTerm
import AIIntegration
import Darwin  // For winsize

/// Protocol defining the core interface for terminal sessions
public protocol TerminalSessionProtocol: AnyObject {
    // MARK: - Properties
    
    /// Whether the terminal session is running
    var isRunning: Bool { get }
    
    /// Last output received from the terminal
    var lastOutput: String { get }
    
    /// Current working directory
    var currentWorkingDirectory: String? { get }
    
    /// Current terminal dimensions
    var currentCols: Int { get }
    var currentRows: Int { get }
    
    /// Current theme for syntax highlighting
    var currentTheme: HighlightTheme { get }
    
    /// Whether syntax highlighting is enabled
    var syntaxHighlightingEnabled: Bool { get set }
    
    // MARK: - Terminal Control Methods
    
    /// Starts a new terminal session
    /// - Parameter terminalView: SwiftTerm terminal view to attach to
    func startSession(terminalView: SwiftTerm.TerminalView) async
    
    /// Terminates the current terminal session
    func terminateSession()
    
    /// Updates the terminal size
    /// - Parameters:
    ///   - cols: Number of columns
    ///   - rows: Number of rows
    func updateSize(cols: Int, rows: Int)
    
    /// Sends data to the terminal process
    /// - Parameter data: Data to send
    func sendToProcess(data: ArraySlice<UInt8>)
    
    /// Sends a command string to the terminal
    /// - Parameter command: Command to send
    func sendCommandToProcess(_ command: String)
    
    // MARK: - Input/Output Methods
    
    /// Handles input data
    /// - Parameter data: Input data
    func handleInput(data: ArraySlice<UInt8>)
    
    /// Processes output data
    /// - Parameter data: Output data
    func processOutput(data: ArraySlice<UInt8>)
    
    // MARK: - Window Management
    
    /// Ensures the terminal window is active and has focus
    func activateWindow()
    
    /// Refreshes the terminal state
    func refreshTerminalState()
    
    // MARK: - AI Integration
    
    /// Sets the AI mode
    /// - Parameter mode: Mode to set
    func setAIMode(_ mode: AIMode) async
    
    /// Sets the AI model to use
    /// - Parameter model: Model to use
    func setAIModel(_ model: AIModel) async
    
    /// Enables or disables AI features
    /// - Parameter enabled: Whether AI features should be enabled
    func toggleAI(_ enabled: Bool) async
    
    /// Refreshes the available models list
    func refreshModels() async
    
    /// Executes a suggested command
    /// - Parameter suggestion: Command suggestion to execute
    func executeSuggestion(_ suggestion: CommandSuggestion)
}

/// Protocol for terminal window management
public protocol TerminalWindowManager: AnyObject {
    /// Activates the terminal window and ensures it has focus
    func activateWindow(terminalView: SwiftTerm.TerminalView)
    
    /// Refreshes the terminal state
    func refreshTerminal(terminalView: SwiftTerm.TerminalView)
    
    /// Resets the terminal
    func resetTerminal(terminalView: SwiftTerm.TerminalView)
}

/// Protocol for terminal input handling
public protocol TerminalInputHandler: AnyObject {
    /// Handles input data
    /// - Parameters:
    ///   - data: Input data
    ///   - processManager: Process manager to send data to
    func handleInput(data: ArraySlice<UInt8>, processManager: ProcessManager)
    
    /// Prepares input for sending
    /// - Parameter input: Raw input
    /// - Returns: Processed input
    func prepareInput(_ input: String) -> String
}

/// Protocol for terminal output handling
public protocol TerminalOutputHandler: AnyObject {
    /// Processes output data
    /// - Parameters:
    ///   - data: Output data
    ///   - terminalView: Terminal view to display output on
    ///   - highlighter: Syntax highlighter for output
    func processOutput(data: ArraySlice<UInt8>, terminalView: SwiftTerm.TerminalView?, highlighter: SyntaxHighlighter?)
    
    /// Last processed output
    var lastOutput: String { get }
}

/// Protocol for process management
public protocol ProcessManager: AnyObject {
    /// Starts a process
    /// - Parameters:
    ///   - executable: Path to executable
    ///   - args: Arguments
    ///   - environment: Environment variables
    ///   - terminalSize: Terminal dimensions
    func startProcess(executable: String, args: [String], environment: [String], terminalSize: winsize)
    
    /// Terminates the process
    func terminateProcess()
    
    /// Sends data to the process
    /// - Parameter data: Data to send
    func sendToProcess(data: ArraySlice<UInt8>)
    
    /// Updates the terminal size
    /// - Parameters:
    ///   - rows: Number of rows
    ///   - cols: Number of columns
    func updateSize(rows: UInt16, cols: UInt16)
    
    /// Whether the process is running
    var isRunning: Bool { get }
}

/// Protocol for terminal configuration
public protocol TerminalConfiguration: AnyObject {
    /// Configures the terminal
    /// - Parameter terminalView: Terminal view to configure
    func configureTerminal(terminalView: SwiftTerm.TerminalView)
    
    /// Initializes the terminal
    /// - Parameter terminalView: Terminal view to initialize
    func initializeTerminal(terminalView: SwiftTerm.TerminalView)
    
    /// Resets the terminal
    /// - Parameter terminalView: Terminal view to reset
    func resetTerminal(terminalView: SwiftTerm.TerminalView)
    
    /// Updates the terminal
    /// - Parameters:
    ///   - terminalView: Terminal view to update
    ///   - rows: Number of rows
    ///   - cols: Number of columns
    func updateTerminalSize(terminalView: SwiftTerm.TerminalView, rows: Int, cols: Int)
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

/// Represents the terminal state
public struct TerminalState: Equatable {
    /// Whether the terminal is running
    public var isRunning: Bool
    
    /// Current working directory
    public var currentWorkingDirectory: String?
    
    /// Current terminal dimensions
    public var cols: Int
    public var rows: Int
    
    /// Whether syntax highlighting is enabled
    public var syntaxHighlightingEnabled: Bool
    
    /// Current theme
    public var theme: HighlightTheme
    
    /// Creates a new terminal state
    public init(
        isRunning: Bool = false,
        currentWorkingDirectory: String? = nil,
        cols: Int = 80,
        rows: Int = 25,
        syntaxHighlightingEnabled: Bool = true,
        theme: HighlightTheme = .dark
    ) {
        self.isRunning = isRunning
        self.currentWorkingDirectory = currentWorkingDirectory
        self.cols = cols
        self.rows = rows
        self.syntaxHighlightingEnabled = syntaxHighlightingEnabled
        self.theme = theme
    }
}

