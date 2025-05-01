import AIIntegration
import Combine
import Darwin  // For ioctl and winsize
import Foundation
@preconcurrency import SwiftTerm
import AppKit
import os.log
import SharedModels

/// Security context for command execution
public struct SecurityContext {
    let level: CommandSandbox.SecurityLevel
    let isAIGenerated: Bool
    let timestamp: Date
    var violations: [String]
    var lastCheck: Date
    
    var asDictionary: [String: String] {
        [
            "level": String(describing: level),
            "isAIGenerated": String(isAIGenerated),
            "timestamp": String(describing: timestamp),
            "violations": violations.joined(separator: ","),
            "lastCheck": String(describing: lastCheck)
        ]
    }
}

/// Security manager for terminal operations
@MainActor public class TerminalSecurityManager {
    /// Logger for security events
    private let logger = Logger(subsystem: "com.llamaterminal", category: "SecurityManager")
    
    /// Last security check timestamp
    private var lastCheck: Date = Date()
    
    /// Security violations detected in this session
    private var violations: [SecurityViolation] = []
    
    /// A security violation record
    struct SecurityViolation {
        let timestamp: Date
        let command: String
        let reason: String
        let level: CommandSandbox.SecurityLevel
        let isAIGenerated: Bool
    }
    
    /// Initialize the security manager
    init() {
        logger.info("Terminal security manager initialized")
    }
    
    /// Get current security context
    func executeCommandWithValidation(
        command: String,
        isAIGenerated: Bool = false,
        taskId: UUID = UUID()
    ) async {
        // First update task state to in-progress
        await taskPersistenceManager.startTask(taskId, command: command, isAIGenerated: isAIGenerated)
        
        // Validate command for security concerns
        if let validationError = await securityValidator.validateCommand(command, isAIGenerated: isAIGenerated) {
            // Handle security validation failure
            await handleCommandFailure(
                taskId: taskId,
                error: validationError,
                errorMessage: "Security validation failed",
                logMessage: "Security validation failed for command: \(command), error: \(validationError)",
                command: command,
                isAIGenerated: isAIGenerated,
                securityEventType: "command_rejected"
            )
            return
        }
        
        // Begin sandboxing if validation passes
        do {
            let sandboxedCommand = try await commandSandboxer.sandboxCommand(command)
            
            // Execute the sandboxed command
            do {
                // Send the command to the process
                try await process.send(text: sandboxedCommand + "\n")
                
                // Update history after successful execution
                await commandHistoryManager.addCommandToHistory(CommandHistoryEntry(
                    command: command,
                    timestamp: Date(),
                    isAIGenerated: isAIGenerated
                ))
                
                // Mark task as completed
                await taskPersistenceManager.completeTask(taskId)
            } catch {
                await handleCommandFailure(
                    taskId: taskId,
                    error: error,
                    errorMessage: "Failed to execute command",
                    logMessage: "Failed to execute command: \(command), error: \(error)",
                    command: command,
                    isAIGenerated: isAIGenerated,
                    securityEventType: "command_execution_failed"
                )
            }
        } catch {
            // Handle sandboxing failure
            await handleCommandFailure(
                taskId: taskId,
                error: error,
                errorMessage: "Command sandboxing failed",
                logMessage: "Sandboxing failed for command: \(command), error: \(error)",
                command: command,
                isAIGenerated: isAIGenerated,
                securityEventType: "sandboxing_failed"
            )
        }
    }
    /// Whether syntax highlighting is enabled
    @Published @MainActor public var syntaxHighlightingEnabled: Bool = true
    
    /// Current theme
    @Published @MainActor public private(set) var currentTheme: HighlightTheme
    
    /// AI terminal coordinator
    private let aiCoordinator: AITerminalCoordinator
    
    /// AI mode
    @Published public private(set) var aiMode: AIMode = .disabled
    
    /// AI model
    @Published public private(set) var currentAIModel: AIModel?
    
    /// Available AI models
    @Published public private(set) var availableModels: [AIModel] = []
    
    /// AI enabled
    @Published public private(set) var aiEnabled: Bool = false
    
    /// AI is processing
    @Published public private(set) var isProcessingAI: Bool = false
    
    /// AI suggestions
    @Published public private(set) var aiSuggestions: [CommandSuggestion] = []
    
    /// Last AI context
    @Published public private(set) var lastAIContext: String?
    
    /// Whether security monitoring is enabled
    @Published public private(set) var securityMonitoringEnabled: Bool = true
    
    /// Command execution service
    private let commandExecutionService: CommandExecutionService
    
    /// Command highlighter
    private let commandHighlighter: ShellCommandHighlighter
    
    /// Code highlighter
    private let codeHighlighter: CodeHighlighter
    
    /// Command sandbox for security
    private let commandSandbox: CommandSandbox
    
    /// Audit logger for security logging
    private let auditLogger: AuditLogger
    
    /// Task persistence manager
    /// Task persistence manager
    private let taskPersistenceManager = TaskPersistenceManager.shared
    
    /// Logger for terminal session
    private let logger = Logger(subsystem: "com.llamaterminal", category: "TerminalSession")
    
    /// State manager for terminal state
    private var stateManager: TerminalStateManager!
    /// Current active tasks
    @Published public private(set) var activeTasks: [UUID: TaskState] = [:]
    
    /// Current recovery tasks
    @Published public private(set) var recoveryTasks: [TaskState] = []
    
    /// Session identifier
    private let sessionId = UUID()
    
    /// Time when session started
    private let sessionStartTime = Date()
    
    /// Current error
    @Published public private(set) var error: Error?
    
    /// Status message
    @Published public private(set) var statusMessage: String = "Initializing..."
    
    /// Terminal-specific error types
    @MainActor public enum TerminalError: Error, LocalizedError {
        case processTerminated(_ process: LocalProcess, exitCode: Int32?)
        case processNotInitialized
        case processNotRunning
        case invalidCommand
        case securityViolation(String)
        case taskRecoveryFailed(String)
        case invalidState(String)
        case sandboxViolation(String)
        
        public var errorDescription: String? {
            switch self {
            case .processTerminated(_, let exitCode):
                if let code = exitCode {
                    return "Terminal process terminated with exit code: \(code)"
                } else {
                    return "Terminal process terminated"
                }
            case .processNotInitialized:
                return "Terminal process not initialized"
            case .processNotRunning:
                return "Terminal process not running"
            case .invalidCommand:
                return "Invalid command format"
            case .securityViolation(let details):
                return "Security violation: \(details)"
            case .taskRecoveryFailed(let reason):
                return "Task recovery failed: \(reason)"
            case .invalidState(let details):
                return "Invalid terminal state: \(details)"
            case .sandboxViolation(let details):
                return "Command sandbox violation: \(details)"
            }
        }
    }
    
    /// SwiftTerm terminal view reference
    @MainActor private weak var terminalView: SwiftTerm.TerminalView?
    
    /// Process manager for terminal processes
    private var processManager: ProcessManager?
    
    /// Shell executable path
    private var shell: String = "/bin/zsh"  // Default shell
    
    /// Current working directory
    private var currentWorkingDirectory: String?
    
    /// Last time we saved session state
    private var lastSessionStateSave: Date?
    
    /// Local process for terminal
    private var localProcess: LocalProcess?
    
    /// Security manager for enhanced terminal security
    private let securityManager = TerminalSecurityManager()
    
    /// Recovery context for task preservation
    private var recoveryContext: [String: Any] = [:]
    
    /// Last security event timestamp
    private var lastSecurityEvent: Date?
    
    /// Command history with enhanced tracking
    private var commandHistory: [CommandHistoryEntry] = []
    
    /// Current terminal dimensions
    private var currentCols: Int = 80
    private var currentRows: Int = 25
    
    /// Whether the terminal process is running
    @Published public private(set) var isRunning: Bool = false
    
    /// Last output received from the terminal
    @Published public private(set) var lastOutput: String = ""
    
    /// Window manager for terminal windows
    private var windowManager: TerminalWindowManager!
    
    /// Input handler for terminal input
    private var inputHandler: TerminalInputHandler!
    
    /// Output handler for terminal output
    private var outputHandler: TerminalOutputHandler!
    
    /// Terminal configuration
    private var terminalConfiguration: TerminalConfiguration!
    
    /// Command sandboxer for security
    private var commandSandboxer: CommandSandbox!
    
    /// Security validator for command security
    private var securityValidator: CommandSecurityValidator!
    // MARK: - Initialization
    
    @MainActor public init(theme: HighlightTheme = .dark) {
        print("[TerminalSession] Initializing with theme: \(theme.name)")
        
        // Initialize basic properties
        self.currentWorkingDirectory = FileManager.default.currentDirectoryPath
        self.currentTheme = theme
        
        // Initialize highlighters
        self.commandHighlighter = ShellCommandHighlighter()
        self.codeHighlighter = CodeHighlighter()
        
        // Initialize AI coordinator
        self.aiCoordinator = AITerminalCoordinator()
        
        // Initialize command execution service
        self.commandExecutionService = CommandExecutionService()
        
        // Initialize security components
        self.commandSandboxer = DefaultCommandSandbox()
        self.securityValidator = DefaultCommandSecurityValidator()
        
        // Initialize components in correct order
        self.terminalConfiguration = DefaultTerminalConfiguration()
        self.windowManager = DefaultTerminalWindowManager(terminalConfiguration: terminalConfiguration)
        self.inputHandler = DefaultTerminalInputHandler(windowManager: windowManager)
        self.outputHandler = DefaultTerminalOutputHandler()
        self.stateManager = DefaultTerminalStateManager()
        
        // Set up delegates
        self.windowManager.configurationDelegate = self
        self.terminalConfiguration.shellCommandDelegate = self
        self.outputHandler.outputProcessingDelegate = self
        
        // Set up initial state
        self.stateManager.updateState(TerminalState(
            isRunning: false,
            currentWorkingDirectory: self.currentWorkingDirectory,
            cols: self.currentCols,
            rows: self.currentRows,
            syntaxHighlightingEnabled: self.syntaxHighlightingEnabled,
            theme: self.currentTheme
        ))
        
        // Set up safety confirmation handler for AI
        Task {
            await self.aiCoordinator.setSafetyConfirmationHandler {
                @Sendable
                action, completion in
                Task { @MainActor [weak self] in
                    guard let self = self else {
                        completion(false)
                        return
                    }
                    self.requestActionConfirmation(action, completion: completion)
                }
            }
        }
    }  // End of init method

    
    // MARK: - Terminal View Management
    
    /// Ensures the terminal view has proper focus
    public func refreshTerminalState() {
        guard let view = terminalView else { return }
        
        print("[TerminalSession] Refreshing terminal state...")
        
        // Force terminal to refresh cursor and input mode
        // The order of these commands is important for proper terminal behavior
        let refreshSequence = [
            "\u{1b}[?25h",    // Show cursor
            "\u{1b}[?7h",     // Enable line wrapping
            "\u{1b}[?2004h",  // Enable bracketed paste mode
            "\u{1b}[?12l",    // Disable local echo (crucial for proper echo behavior)
            "\u{1b}[4l",      // Reset insert mode (crucial for proper cursor behavior)
            "\u{1b}[20h",     // Set newline mode (LNM)
            "\u{1b}]0;LlamaTerminal\u{7}" // Reset window title (helps with focus issues)
        ].joined()
        
        // Set proper terminal options through the terminal object if available
        if let terminal = view.terminal {
            // These options are crucial for proper terminal behavior
            if let options = terminal.options {
                options.insert(.cursorBlink)
                options.insert(.cursorVisible)
                options.insert(.bracketedPaste)
                options.insert(.allowMouseReporting)
            }
        }
        // Send control sequences to terminal
        print("[TerminalSession] Sending terminal control sequences")
        view.feed(text: refreshSequence)
        
        // If we have a running process, also send some stty commands to ensure proper echo
        if isRunning, let proc = localProcess {
            // These are the most critical settings for proper echo behavior
            // Send each command separately with small delays for better reliability
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard self != nil else { return }
                
                // Commands to execute with brief pauses between them
                let sttyCommands = [
                    "stty sane",              // Get terminal into a clean state 
                    "stty echo",              // Explicitly enable echo
                    "stty echoe echok echoke",// Enhanced echo control
                    "stty -echoctl",          // Don't echo control chars as ^X
                    "stty icrnl onlcr",       // Handle line endings properly (crucial for echo)
                    "stty intr '^C'",         // Set interrupt character
                    "stty erase '^?'"         // Set backspace character
                ]
                
                print("[TerminalSession] Sending critical stty commands for echo")
                for cmd in sttyCommands {
                    proc.send(data: ArraySlice((cmd + "\n").utf8))
                    Thread.sleep(forTimeInterval: 0.05) // Small delay between commands
                }
            }
        }
    }
    
    /// Initializes and configures the terminal view
    private func initializeTerminalView(_ view: SwiftTerm.TerminalView) {
        print("[TerminalSession] Initializing terminal view")
        self.terminalView = view
        
        // Configure colors
        view.configureNativeColors()
        
        // Clear screen and ensure clean state
        view.feed(text: "\u{1b}[2J\u{1b}[H")  // Clear screen and home cursor
        
        // Set initial size
        self.currentCols = 80
        self.currentRows = 25
        // Initialize terminal with options
        if let terminal = view.terminal {
            terminal.resetToInitialState()
            if let options = terminal.options {
                options.insert(.allowMouseReporting)
                options.insert(.bracketedPaste)
                options.insert(.cursorBlink)
                options.insert(.cursorVisible)
            }
        }
        
        
        // Set initial window state
        if let window = view.window {
            DispatchQueue.main.sync {
                window.makeKeyAndOrderFront(self)
                window.makeFirstResponder(view)
                let _ = view.becomeFirstResponder()
            }
        }
    }
    
    /// Performs a thorough terminal reset and initialization
    private func performFullTerminalReset(_ view: SwiftTerm.TerminalView) {
        print("[TerminalSession] Performing full terminal reset sequence")
        
        // First, use the SwiftTerm built-in reset capabilities
        if let terminal = view.terminal {
            terminal.resetToInitialState()
            
            // Set essential terminal options
            if let options = terminal.options {
                options.insert(.cursorBlink)
                options.insert(.cursorVisible)
                options.insert(.bracketedPaste)
                options.insert(.allowMouseReporting)
            }
        }
        // The order of these commands is critical for proper terminal behavior
        let resetSequence = [
            "\u{1b}c",         // RIS - Full terminal reset
            "\u{1b}[!p",       // DECSTR - Soft reset
            "\u{1b}[?47l",     // Use normal screen buffer
            "\u{1b}[?1049l",   // Use normal screen buffer (alternate method)
            "\u{1b}[2J",       // Clear screen
            "\u{1b}[H",        // Home cursor
            "\u{1b}[?25h",     // Show cursor
            "\u{1b}[?7h",      // Enable line wrapping
            "\u{1b}[?12l",     // Disable local echo
            "\u{1b}[4l",       // Reset insert mode
            "\u{1b}[20h",      // Set newline mode
            "\u{1b}]0;LlamaTerminal\u{7}" // Set window title
        ].joined()
        
        // Send the reset sequence
        view.feed(text: resetSequence)
        
        // Give terminal a moment to process, then clear screen once more
    }
    
    // MARK: - TerminalSessionProtocol Methods
    
    /// Starts a new terminal session
    /// - Parameter terminalView: Terminal view to attach to
    @MainActor public func startSession(terminalView: SwiftTerm.TerminalView) async {
        logger.info("Starting new terminal session \(sessionId.uuidString)")
        
        // Reset component state
        resetAllComponents()
        
        // Save terminal view reference
        self.terminalView = terminalView
        
        // Set up terminal view delegate
        terminalView.delegate = self
        
        // Check for recovery tasks
        await checkForRecoveryTasks()
        
        // STEP 1: Initialize terminal view with proper configuration
        terminalConfiguration.initializeTerminal(terminalView: terminalView)
        
        // STEP 2: Set up input handler with terminal view
        inputHandler.setTerminalView(terminalView)
        
        // STEP 3: Ensure window has focus
        windowManager.activateWindow(terminalView: terminalView)
        
        // Wait for window activation to take effect
        try? await Task.sleep(for: .milliseconds(100))
        
        // STEP 4: Initialize process management
        do {
            try await initializeProcessManagement(for: terminalView)
        } catch {
            print("[TerminalSession] Error initializing process: \(error.localizedDescription)")
            
            // Display error in terminal view
            terminalView.feed(text: "\r\nFailed to initialize terminal process: \(error.localizedDescription)\r\n")
            self.lastOutput = "Failed to initialize terminal process: \(error.localizedDescription)"
            return
        }

        // STEP 5: Configure terminal and initialize process
        await configureTerminalForProcess(terminalView)
    }
    
    /// Configures the terminal for process
    /// - Parameter terminalView: Terminal view to configure
    @MainActor private func configureTerminalForProcess(_ terminalView: SwiftTerm.TerminalView) async {
        // Initialize terminal view with proper settings
        performFullTerminalReset(terminalView)
        
        // Ensure proper focus
        ensureWindowActive()
        
        // Set up any additional terminal-specific configurations
        terminalConfiguration.configureTerminal(terminalView: terminalView)
        
        // Additional setup code as needed
        refreshTerminalState()
    }
    
    /// Initializes process management components
    /// - Parameter terminalView: The terminal view to attach to
    /// - Throws: Any error encountered during process initialization
    @MainActor private func initializeProcessManagement(for terminalView: SwiftTerm.TerminalView) throws {
        // Initialize process management
        let shell = self.shell
        let workingDir = self.currentWorkingDirectory ?? FileManager.default.currentDirectoryPath
        
        // Create the process manager if needed
        if processManager == nil {
            processManager = ProcessManager()
        }
        
        // Create and start the process
        logger.info("Initializing terminal process with shell: \(shell)")
        let process = LocalProcess(shellPath: shell, 
                                   workingDirectory: workingDir,
                                   environment: ProcessInfo.processInfo.environment)
        
        // Set up process size
        process.setSize(rows: UInt16(currentRows), cols: UInt16(currentCols))
        
        // Store the process
        self.localProcess = process
        
        // Set us as the delegate
        process.delegate = self
        
        // Start the process
        try process.start()
        
        // Mark as running
        isRunning = true
        // Configure terminal with minimal settings in a separate task
        // Configure terminal with essential settings in a separate task
        Task {
            // Helper function to safely send commands with validation and retries
            func sendSetupCommands(_ commands: [String], delay: UInt64 = 100_000_000, retries: Int = 3) async throws {
                for command in commands {
                    var attempts = 0
                    var success = false
                    
                    while attempts < retries && !success {
                        do {
                            if let proc = self.localProcess, self.isRunning {
                                // Validate command before sending
                                guard command.allSatisfies({ $0.isASCII }) else {
                                    throw TerminalError.invalidCommand
                                }
                                
                                // Send command with proper line ending
                                proc.send(data: ArraySlice((command + "\n").utf8))
                                
                                // Wait for command to take effect
                                try await Task.sleep(nanoseconds: delay)
                                success = true
                            } else {
                                throw TerminalError.processNotRunning
                            }
                        } catch {
                            attempts += 1
                            if attempts >= retries {
                                logger.error("Failed to execute setup command after \(retries) attempts: \(command)")
                                throw error
                            }
                            // Exponential backoff for retries
                            try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempts))) * 100_000_000)
                        }
                    }
                }
            }
            
            do {
                // Wait for process to be fully started
                try await Task.sleep(nanoseconds: 500_000_000)  // 500ms initial delay
                
                // Define command sets with proper grouping and dependencies
                let terminalResetCommands = [
                    "stty sane",              // Primary terminal reset
                    "stty -echo",             // Temporarily disable echo for clean setup
                ]
                
                let basicSetupCommands = [
                    "stty echo",              // Re-enable echo
                    "stty icrnl onlcr",       // Handle line endings
                    "stty icanon",            // Enable canonical mode
                    "stty isig",              // Enable signals
                    "stty ixon",              // Enable flow control
                ]
                
                let advancedSetupCommands = [
                    "stty echoe echok echoke", // Enhanced echo control
                    "stty erase '^?'",         // Set erase character
                    "stty intr '^C'",          // Set interrupt character
                    "stty susp '^Z'",          // Set suspend character
                    "stty werase '^W'",        // Set word erase
                    "stty kill '^U'",          // Set line kill
                    "stty -tostop",            // Prevent background process stopping
                    "stty -echoctl",           // Don't echo control chars
                ]
                
                let shellOptimizationCommands = [
                    "bindkey -e",                 // Emacs key bindings
                    "setopt PROMPT_SUBST",        // Enable prompt substitution
                    "setopt INTERACTIVE_COMMENTS", // Allow comments
                    "export TERM=xterm-256color", // Ensure proper terminal type
                ]
                
                // Execute command groups with appropriate delays and error handling
                logger.info("Initializing terminal with basic settings")
                try await sendSetupCommands(terminalResetCommands, delay: 200_000_000)
                
                logger.info("Configuring basic terminal functionality")
                try await sendSetupCommands(basicSetupCommands, delay: 100_000_000)
                
                logger.info("Applying advanced terminal settings")
                try await sendSetupCommands(advancedSetupCommands, delay: 75_000_000)
                
                logger.info("Optimizing shell environment")
                try await sendSetupCommands(shellOptimizationCommands, delay: 50_000_000)
                
                // Final delay for settings to take effect
                try await Task.sleep(nanoseconds: 200_000_000)
                
                // Ensure window activation only if needed
                await MainActor.run {
                    if let view = self.terminalView,
                       let window = view.window,
                       !window.isKeyWindow || window.firstResponder !== view {
                        view.feed(text: "\u{1b}[?25h")  // Ensure cursor is visible
                        self.ensureWindowActive()
                    }
                }
                
                logger.info("Terminal initialization completed successfully")
                
            } catch {
                logger.error("Error during terminal configuration: \(error)")
                
                // Attempt basic recovery
                if let proc = self.localProcess, self.isRunning {
                    // Send minimal safe configuration
                    proc.send(data: ArraySlice("stty sane\n".utf8))
                    proc.send(data: ArraySlice("stty echo\n".utf8))
                }
                
                await MainActor.run {
                    if let view = self.terminalView {
                        view.feed(text: "\r\n\u{1b}[31mWarning: Some terminal settings may not be optimal\u{1b}[0m\r\n")
                    }
                }
            }
        }  // End of Task block
    }  // End of startSession function
    
    /// Helper to send a command string to the process with security validation
    public func sendCommandToProcess(_ command: String) {
        let commandWithNewline = command + "\n"
        
        // Create a task ID for tracking
        let taskId = UUID()
        
        // Log the command execution intention
        Task {
            await auditLogger.logCommandExecution(
                command: command,
                isAIGenerated: false,
                workingDirectory: currentWorkingDirectory
            )
            
            // Save command state for potential recovery
            let taskData = UserCommandData(
                command: command,
                workingDirectory: currentWorkingDirectory,
                environment: nil // Could get from process.environment if needed
            )
            
            let taskState = TaskState(
                id: taskId,
                type: .userCommand,
                description: "Execute command: \(command)",
                data: taskData,
                status: .pending
            )
            
            // Save task state
            let _ = await taskPersistenceManager.saveTaskState(taskState)
            
            // Track active task
            await MainActor.run {
                activeTasks[taskId] = taskState
            }
        }
        
        // Apply security checks and sandboxing if enabled
        if securityMonitoringEnabled {
            // Determine security level based on AI mode
            let securityLevel: CommandSandbox.SecurityLevel = 
                aiMode == .disabled ? .standard : .strict
            
            // Sandbox the command
            guard let sandboxedCommand = commandSandbox.sandboxCommand(
                command, 
                securityLevel: securityLevel,
                isAIGenerated: false
            ) else {
                // Command rejected by security sandbox
                if let view = terminalView {
                    view.feed(text: "\r\n\u{1b}[31mCommand rejected by security sandbox\u{1b}[0m\r\n")
                }
                
                // Update task status to failed
                Task {
                    await taskPersistenceManager.failTask(taskId, error: "Command rejected by security sandbox")
                    
                    // Remove from active tasks
                    await MainActor.run {
                        activeTasks.removeValue(forKey: taskId)
                    }
                }
                
                return
            }
            
            // Update task to in-progress
            Task {
                await taskPersistenceManager.updateTaskState(taskId) { task in
                    task.status = .inProgress
                }
            }
            
            // Use sandboxed command instead
            if let data = (sandboxedCommand + "\n").data(using: .utf8) {
                sendToProcess(data: ArraySlice(data))
            }
        } else {
            // If security is disabled, send original command
            if let data = commandWithNewline.data(using: .utf8) {
                sendToProcess(data: ArraySlice(data))
            }
            
            // Update task to in-progress
            Task {
                await taskPersistenceManager.updateTaskState(taskId) { task in
                    task.status = .inProgress
                }
            }
        }
    }
    
    /// Sends data to the process
    /// - Parameter data: Data to send
    public func sendToProcess(data: ArraySlice<UInt8>) {
        guard let localProcess = localProcess, isRunning else {
            print("[TerminalSession] Cannot send to process: process not running")
            return
        }
        
        // Debug logging
        if let str = String(bytes: data, encoding: .utf8) {
            let safeStr = str.replacingOccurrences(of: "\n", with: "\\n")
                            .replacingOccurrences(of: "\r", with: "\\r")
                            .replacingOccurrences(of: "\u{1b}", with: "\\e")
            print("[TerminalSession] Sending data to process: \(safeStr)")
        } else {
            print("[TerminalSession] Sending non-UTF8 data to process: \(data.count) bytes")
        }
        
        // Send data to process
        localProcess.send(data: data)
        
        // Ensure terminal view remains first responder using our consolidated method
        ensureWindowActive()
    }

    public func terminateSession() {
        print("[TerminalSession] terminateSession called.")  // DEBUG
        localProcess?.terminate()
        localProcess = nil  // Release reference
        terminalView = nil
        isRunning = false  // Update state immediately
    }

    public func updateSize(cols: Int, rows: Int) {
        print("[TerminalSession] Updating internal size to: \(cols)x\(rows)")
        
        // Only update if valid dimensions
        guard cols > 0 && rows > 0 else {
            print("[TerminalSession] Warning: Ignoring invalid terminal size: \(cols)x\(rows)")
            return
        }
        
        self.currentCols = cols
        self.currentRows = rows
        
        // Update terminal size
        if let process = localProcess, isRunning {
            process.setSize(rows: UInt16(rows), cols: UInt16(cols))
            // Send updated size to terminal
            if let view = terminalView {
                // Update terminal about its new size
                let sizeSequence = "\u{1b}[8;\(rows);\(cols)t"
                view.feed(text: sizeSequence)
            }
        }
    }
    // MARK: - LocalProcessDelegate Methods
    
    @MainActor public func dataReceived(slice: ArraySlice<UInt8>) {
        guard let view = terminalView else {
            print("[TerminalSession] Error: terminalView is nil in dataReceived.")
            return
        }
        
        // Feed data directly to terminal view
        view.feed(byteArray: slice)
        
        // Process output for AI or logging
        if let output = String(bytes: slice, encoding: .utf8) {
            self.lastOutput = output
            
            // Monitor output for command completion
            checkForCommandCompletion(output)
            
            // Debug print for non-empty visible output
            if !output.isEmpty && output.rangeOfCharacter(from: .whitespaces.inverted) != nil {
                print("[TerminalSession] dataReceived: visible output")
                
                // Log any terminal control sequences for debugging
                if output.contains("\u{1b}") {
                    let escapeCodes = output.components(separatedBy: "\u{1b}")
                        .filter { !$0.isEmpty }
                        .map { "\\e" + $0 }
                        .joined(separator: ", ")
                        
                    print("[TerminalSession] Contains escape sequences: \(escapeCodes)")
                }
            }
        }
        
        // Mark session as running if it's not already
        if !isRunning { 
            isRunning = true 
            
            // Save initial session state once we're running
            saveSessionState()
        }
        // Don't force window activation during data receipt - this can cause focus issues
        // and disrupt user interaction with the terminal
    }

    @MainActor public func processTerminated(_ process: LocalProcess, exitCode: Int32?) {
        // Only show termination message if we were actually running
        // This prevents premature "terminal session has ended" messages
        guard isRunning else { return }
        
        // Mark terminal as not running
        isRunning = false
        
        // Show termination message in terminal
        if let view = terminalView {
            let statusMessage: String
            if let code = exitCode {
                statusMessage = "\r\n\u{1b}[33mTerminal session has ended (exit code: \(code))\u{1b}[0m\r\n"
            } else {
                statusMessage = "\r\n\u{1b}[33mTerminal session has ended\u{1b}[0m\r\n"
            }
            view.feed(text: statusMessage)
        }
        
        // Complete all active tasks
        completeAllActiveTasks(exitCode: exitCode)
        
        // Notify the system
        logger.info("Terminal process terminated with exit code: \(exitCode ?? -1)")
        
        // Clean up references
        localProcess = nil
    }
    // MARK: - AI Integration Methods
    
    /// - Parameter mode: Mode to set
    public func setAIMode(_ mode: AIMode) async {
        await aiCoordinator.setMode(mode)
        self.aiMode = mode
        self.lastAIContext = mode == .disabled ? nil : "AI mode set to \(mode.rawValue)"
    }

    /// Sets the AI model to use
    /// - Parameter model: Model to use
    public func setAIModel(_ model: AIModel) async {
        await aiCoordinator.setModel(model)
        self.currentAIModel = model
        self.lastAIContext = "AI model set to \(model.name)"
    }

    /// Enables or disables AI features
    /// - Parameter enabled: Whether AI features should be enabled
    public func toggleAI(_ enabled: Bool) async {
        self.aiEnabled = enabled

        if !enabled {
            // If disabling, set mode to disabled as well
            await setAIMode(.disabled)
        } else if currentAIModel != nil {
            // If enabling and we have a model, default to Auto mode
            await setAIMode(.auto)
        }
    }

    /// Refreshes the available models list
    public func refreshModels() async {
        self.isProcessingAI = true
        let success = await aiCoordinator.refreshModels()
        if success {
            self.availableModels = await aiCoordinator.getAvailableModels()
            self.currentAIModel = await aiCoordinator.currentModel
            self.lastAIContext = "Models refreshed successfully"
        } else {
            self.lastAIContext = "Failed to refresh models"
        }
        self.isProcessingAI = false
    }

    /// Pulls a model from Ollama
    /// - Parameter modelName: Name of the model to pull
    /// - Returns: Stream of progress updates
    public func pullModel(_ modelName: String) async -> AsyncThrowingStream<PullProgress, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Remove try if pullModel doesn't actually throw, but keeping it assuming it might
                    // throw in certain conditions like network errors
                    let stream = await aiCoordinator.pullModel(modelName)
                    for try await update in stream {
                        continuation.yield(update)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Deletes a model from Ollama
    /// - Parameter model: Model to delete
    public func deleteModel(_ model: AIModel) async {
        self.isProcessingAI = true
        do {
            try await aiCoordinator.deleteModel(model)
            self.lastAIContext = "Model '\(model.name)' deleted successfully"
        } catch {
            self.lastAIContext = "Failed to delete model: \(error.localizedDescription)"
        }
        self.isProcessingAI = false
    }

    /// Processes a user command through AI
    // MARK: - Command Processing
    
    /// Processes a user command through AI
    /// - Parameter command: Command to process
    private func processUserCommand(_ command: String) async {
        // Check if AI is disabled
        guard aiEnabled && aiMode != .disabled else {
            sendCommandToProcess(command)  // Send command directly if AI disabled
            return
        }
        
        self.isProcessingAI = true
        
        do {
            // Process through AI coordinator
            let response = try await aiCoordinator.processCommand(command)
            // Update suggestions - no need for MainActor.run since class is @MainActor
            self.aiSuggestions = response.suggestions
            if let context = response.context {
                self.lastAIContext = context
            }
 // If in dispatch mode, execute suggested actions automatically
            if aiMode == .dispatch, let firstAction = response.actions.first {
                // Execute the action if it was approved or doesn't need confirmation
                let shouldExecute = await aiCoordinator.executeAction(firstAction)
                
                if shouldExecute {
                    await executeAIAction(firstAction)
                } else {
                    self.lastAIContext = "Action not confirmed: \(firstAction.content)"
                }
            } else if aiMode == .auto {
                // In auto mode, send the original command for execution
                sendCommandToProcess(command)
            }
        } catch {
            // Update error state
            self.lastAIContext = "AI processing error: \(error.localizedDescription)"
            self.isProcessingAI = false
            
            // Fall back to sending the original command even on AI error
            sendCommandToProcess(command)
        }
        
        self.isProcessingAI = false
    }

    /// Executes an AI action
    /// - Parameter action: Action to execute
    private func executeAIAction(_ action: AIAction) async {
        switch action.type {
        case .executeCommand:
            sendCommandToProcess(action.content)  // Use helper

        case .generateCode:
            // Show generated code with syntax highlighting
            guard let terminalWrapper = terminalView else { return }

            let highlightedCode = codeHighlighter.highlightForTerminal(
                text: action.content,
                theme: currentTheme
            )

            // Format the code display
            let codeDisplay = """

                AI GENERATED CODE:
                ----------------
                \(highlightedCode)
                ----------------

                """

            terminalWrapper.send(txt: "echo -e '\(codeDisplay)'\n")

        case .modifyFile:
            // Extract file path and content from metadata
            guard let filePath = action.metadata["path"] else {
                await MainActor.run {
                    self.lastAIContext = "Error: File path not specified for file modification"
                }
                return
            }

            // Use the execution service to modify the file
            do {
                let result = try await commandExecutionService.executeCommand(
                    "cat > \(filePath) << 'LLAMA_EOF'\n\(action.content)\nLLAMA_EOF"
                )

                await MainActor.run {
                    if result.isSuccessful {
                        self.lastAIContext = "File \(filePath) modified successfully"
                    } else {
                        self.lastAIContext = "Error modifying file: \(result.output)"
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastAIContext = "Error: \(error.localizedDescription)"
                }
            }

        case .installPackage:
            sendCommandToProcess(action.content)  // Use helper

        case .planTask:
            // Display the task plan
            guard let terminalWrapper = terminalView else { return }

            let formattedPlan = """

                AI TASK PLAN:
                ------------
                \(action.content)
                ------------

                """

            terminalWrapper.send(txt: "echo -e '\(formattedPlan)'\n")
        }
    }

    /// Captures and analyzes command output
    /// - Parameters:
    ///   - command: Command that was executed
    ///   - startTime: When the command started
    private func captureCommandOutput(command: String, startTime: Date) async {
        guard aiEnabled, aiMode != .disabled, isRunning else { return }

        // Wait for a reasonable amount of time for command to complete
        try? await Task.sleep(for: .milliseconds(1000))

        // We can't directly capture output from the terminal process
        // Instead, we'll execute a separate background command to get the last output
        do {
            // Use commandExecutionService (asynchronous executor)
            let result = try await commandExecutionService.executeCommand(
                "echo $?"  // Get the exit code of the last command
            )

            let exitCode = Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let duration = Date().timeIntervalSince(startTime)

            // Create a CommandResult to process
            let commandResult = CommandResult(
                command: command,
                output: "Output captured in terminal view",
                exitCode: exitCode,
                duration: duration
            )

            // Create an AIIntegration CommandResult for the AICoordinator
            let aiCommandResult = AIIntegration.CommandResult(
                command: commandResult.command,
                output: commandResult.output,
                exitCode: commandResult.exitCode,
                duration: commandResult.duration
            )

            // Process through AI with the AIIntegration.CommandResult
            let response = try await aiCoordinator.handleCommandResult(aiCommandResult)

            // Update UI with response
            await MainActor.run {
                if let context = response.context, !context.isEmpty {
                    self.lastAIContext = context
                }

                // Update suggestions
                self.aiSuggestions = response.suggestions

                // If in dispatch mode, execute next action if available
                if aiMode == .dispatch, let nextAction = response.actions.first {
                    Task {
                        let shouldExecute = await aiCoordinator.executeAction(nextAction)
                        if shouldExecute {
                            await executeAIAction(nextAction)
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.lastAIContext = "Error analyzing command: \(error.localizedDescription)"
            }
        }
    }

    /// Requests confirmation for an AI action
    /// - Parameters:
    ///   - action: The action requiring confirmation
    ///   - completion: Callback with confirmation result
    private func requestActionConfirmation(_ action: AIAction, completion: @escaping (Bool) -> Void)
    {
        // For now, we'll use a simple terminal-based confirmation
        // In a real UI, this would be a proper dialog
        guard let terminalWrapper = terminalView else {
            completion(false)
            return
        }

        // Determine safety level based on action type
        let safetyLevel: String
        switch action.type {
        case .executeCommand:
            safetyLevel =
                action.content.contains("rm") || action.content.contains("sudo")
                ? "⚠️ POTENTIALLY DESTRUCTIVE" : "✅ SAFE"
        case .modifyFile:
            safetyLevel = "⚠️ WILL MODIFY FILES"
        case .installPackage:
            safetyLevel = "⚠️ WILL INSTALL SOFTWARE"
        default:
            safetyLevel = "✅ SAFE"
        }

        // Create confirmation message
        let confirmationMessage = """

            AI ACTION CONFIRMATION
            ---------------------
            Type: \(action.type.rawValue)
            Safety: \(safetyLevel)
            Action: \(action.content.prefix(100))\(action.content.count > 100 ? "..." : "")

            Confirm execution? (y/n): 
            """

        // Display confirmation and capture response
        terminalWrapper.send(txt: "echo -e '\(confirmationMessage)'\n")

        // Set up a response handler
        // In a real implementation, this would use a proper UI confirmation dialog
        // For now, we'll use a simplistic approach with a timeout
        Task {
            // Wait for a response (simulated)
            try? await Task.sleep(for: .seconds(15))

            // Default to not confirming if no response
            // In a real implementation, this would properly capture user input
            completion(false)

            // For demo purposes, we'll auto-confirm safe actions
            if safetyLevel.contains("SAFE") {
                completion(true)
            } else {
                completion(false)
            }
        }
    }
    /// Execute a command with security validation and sandboxing
    /// - Parameters:
    ///   - command: Command string to execute
    ///   - taskId: Task ID for tracking
    ///   - isAIGenerated: Whether the command was generated by AI
    private func executeCommandWithValidation(command: String, taskId: UUID, isAIGenerated: Bool) async {
    // Determine appropriate security level based on command source
    let securityLevel: CommandSandbox.SecurityLevel = isAIGenerated ? .strict : .standard
    
    // Create a security context for validation
    let securityContext = SecurityContext(
        level: securityLevel,
        isAIGenerated: isAIGenerated,
        timestamp: Date(),
        violations: [],
        lastCheck: Date()
    )
    
    // STEP 1: Validate command security
    do {
        let validationResult = try validateCommandSecurity(command, context: securityContext)
        
        // Only proceed if validation passes
        guard validationResult else {
            throw TerminalError.securityViolation("Command failed validation without specific error")
        }
        
        // STEP 2: Apply command sandboxing to the validated command
        guard let sandboxedCommand = commandSandbox.sandboxCommand(
            command, 
            securityLevel: securityLevel,
            isAIGenerated: isAIGenerated
        ) else {
            throw TerminalError.sandboxViolation("Command rejected by security sandbox")
        }
        
        // STEP 3: Update task state to in-progress
        Task {
            await taskPersistenceManager.updateTaskState(taskId) { task in
                task.status = .inProgress
            }
            
            // Track active task
            await MainActor.run {
                if let task = activeTasks[taskId] {
                    var updatedTask = task
                    updatedTask.status = .inProgress
                    activeTasks[taskId] = updatedTask
                } else {
                    logger.warning("Task \(taskId) not found in active tasks when updating to in-progress")
                }
            }
        }
        
        // STEP 4: Execute the sandboxed command
        let finalCommand = sandboxedCommand + "\n"
        
        // Record start time for duration tracking
        let commandStartTime = Date()
        
        // Send the command to the process
        if let data = finalCommand.data(using: .utf8) {
            sendToProcess(data: ArraySlice(data))
        }
        
        // STEP 5: Log command execution
        Task {
            await auditLogger.logCommandExecution(
                command: command,
                isAIGenerated: isAIGenerated,
                workingDirectory: currentWorkingDirectory
            )
            
            // Log execution time for performance monitoring
            let executionDuration = Date().timeIntervalSince(commandStartTime)
            logger.debug("Command execution initiated. Duration: \(executionDuration)s, AI-generated: \(isAIGenerated)")
        }
    } catch {
        // Handle any errors during validation or sandboxing
        await handleCommandFailure(
            taskId: taskId,
            error: error,
            errorMessage: error is TerminalError.sandboxViolation ? "Command could not be executed due to sandbox restrictions" : "Security validation failed",
            logMessage: error is TerminalError.sandboxViolation ? 
                "Command sandbox failure: \(error.localizedDescription)" : 
                "Security validation failed for command: \(command), error: \(error)",
            command: command,
            isAIGenerated: isAIGenerated,
            securityEventType: error is TerminalError.sandboxViolation ? "sandboxViolation" : "command_rejected"
        )
    }
}
    
    /// Helper method to handle command failures in a consistent way
    /// - Parameters:
    ///   - taskId: Task ID for tracking
    ///   - error: The error that caused the failure
    ///   - errorMessage: User-friendly error message
    ///   - logMessage: Message to log
    ///   - command: The original command
    ///   - isAIGenerated: Whether the command was generated by AI
    ///   - securityEventType: Type of security event to log
    private func handleCommandFailure(
        taskId: UUID,
        error: Error,
        errorMessage: String,
        logMessage: String,
        command: String,
        isAIGenerated: Bool,
        securityEventType: String
    ) async {
        // Update task state to failed
        await taskPersistenceManager.failTask(taskId, error: error.localizedDescription)
        
        // Update in-memory task state
        await MainActor.run {
            if var task = activeTasks[taskId] {
                task.status = .failed
                activeTasks[taskId] = task
            } else {
                logger.warning("Task \(taskId) not found in active tasks when updating to failed")
            }
        }
        
        // Log the failure
        logger.error(logMessage)
        
        // Remove task from activeTasks
        await MainActor.run {
            activeTasks.removeValue(forKey: taskId)
        }
        
        // Notify terminal view about the failure
        if let view = terminalView {
            view.feed(text: "\r\n\u{1b}[31mSecurity error: \(errorMessage)\u{1b}[0m\r\n")
        }
        
        // Log security event
        Task {
            await auditLogger.logEvent(
                category: .security,
                event: securityEventType,
                message: errorMessage,
                severity: .warning,
                details: [
                    "command": command,
                    "isAIGenerated": String(isAIGenerated),
                    "error": error.localizedDescription
                ]
            )
        }
    }
    // Already moved to the top of the file
    
    /// Enhanced command security validation
    private func validateCommandSecurity(_ command: String, context: SecurityContext) throws -> Bool {
        // Update last security check
        lastSecurityEvent = Date()
        
        // Basic security checks
        guard !command.isEmpty else {
            throw TerminalError.invalidCommand
        }
        
        // Check for dangerous patterns
        let dangerousPatterns = [
            "rm -rf /",
            "mkfs",
            "> /dev/"
        ]
        
        for pattern in dangerousPatterns {
            if command.contains(pattern) {
                throw TerminalError.securityViolation("Dangerous command pattern detected: \(pattern)")
            }
        }
        
        // Apply security level-specific checks
        switch context.level {
        case .strict:
            // Stricter validation for AI-generated commands
            let strictPatterns = [
                "sudo",
                "chmod",
                "chown",
                "dd",
                "truncate"
            ]
            
            for pattern in strictPatterns {
                if command.contains(pattern) {
                    throw TerminalError.securityViolation("Restricted command in strict mode: \(pattern)")
                }
            }
            
        case .standard:
            // Standard validation
            let standardPatterns = [
                "rm -rf /*",
                ":(){ :|:& };:",  // Fork bomb
                "> /dev/sd"
            ]
            
            for pattern in standardPatterns {
                if command.contains(pattern) {
                    throw TerminalError.securityViolation("Potentially dangerous command pattern: \(pattern)")
                }
            }
        case .permissive:
            // Minimal validation for permissive mode
            break
        }
        
        // Log security check
        Task {
            await auditLogger.logEvent(
                category: .security,
                event: "command_security_check",
                message: "Security validation performed",
                severity: .info,
                details: context.asDictionary
            )
        }
        
        return true
    }
    
    /// Enhanced recovery for tasks
    private func prepareTaskRecovery(_ task: TaskState) async throws -> Bool {
        guard let taskId = task.id else {
            throw TerminalError.taskRecoveryFailed("Missing task ID")
        }
        
        // Validate task state
        guard task.status != .completed && task.status != .failed else {
            throw TerminalError.taskRecoveryFailed("Task already completed or failed")
        }
        
        // Build recovery context
        var recoveryData: [String: Any] = [
            "taskId": taskId.uuidString,
            "timestamp": Date().timeIntervalSince1970,
            "type": task.type.rawValue,
            "status": task.status.rawValue
        ]
        
        // Add task-specific data
        if let taskData = task.data {
            recoveryData["data"] = taskData
        }
        
        // Add terminal state
        recoveryData["terminalState"] = [
            "workingDirectory": currentWorkingDirectory ?? "",
            "aiMode": aiMode.rawValue,
            "securityLevel": securityMonitoringEnabled ? "enabled" : "disabled"
        ]
        
        // Store recovery context
        self.recoveryContext = recoveryData
        
        // Log recovery preparation
        await auditLogger.logEvent(
            category: .system,
            event: "recovery_preparation",
            message: "Prepared task for recovery",
            severity: .info,
            details: recoveryData.mapValues { String(describing: $0) }
        )
        
        return true
    }
    
    /// Log command execution with enhanced tracking
    private func logCommandExecution(_ command: String, taskId: UUID, context: SecurityContext) async {
        let historyEntry = CommandHistoryEntry(
            command: command,
            timestamp: Date(),
            workingDirectory: currentWorkingDirectory,
            exitCode: nil,
            duration: 0,
            securityContext: context.asDictionary
        )
        
        // Since we're already in a @MainActor class, we don't need MainActor.run
        commandHistory.append(historyEntry)
        
        // Trim history if needed
        if commandHistory.count > 1000 {
            commandHistory.removeFirst(commandHistory.count - 1000)
        }
        
        // Log execution
        await auditLogger.logCommandExecution(
            command: command,
            isAIGenerated: context.isAIGenerated,
            workingDirectory: currentWorkingDirectory,
            details: context.asDictionary
        )
    }

    // MARK: - Window Management Methods
    
    /// Ensures the window for the terminal view is active
    private func ensureWindowActive() {
        guard let view = terminalView, let window = view.window else { return }
        
        // Only force activation if the window isn't already key or the view isn't first responder
        if !window.isKeyWindow || window.firstResponder !== view {
            DispatchQueue.main.async {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(view)
                let _ = view.becomeFirstResponder()
            }
        }
    }
    
    // MARK: - State Management
    
    /// Saves the current session state
    private func saveSessionState() {
        // Don't save state too frequently
        let now = Date()
        if let lastSave = lastSessionStateSave, now.timeIntervalSince(lastSave) < 60.0 {
            return  // Don't save more than once per minute
        }
        
        lastSessionStateSave = now
        
        // Save session state using taskPersistenceManager
        Task {
            await taskPersistenceManager.saveSessionState(sessionId.uuidString, state: [
                "startTime": sessionStartTime.timeIntervalSince1970.description,
                "workingDirectory": currentWorkingDirectory ?? "",
                "aiEnabled": String(aiEnabled),
                "aiMode": aiMode.rawValue
            ])
        }
    }
    
    /// Resets all components to their initial state
    private func resetAllComponents() {
        // Reset state properties
        isRunning = false
        lastOutput = ""
        currentWorkingDirectory = FileManager.default.currentDirectoryPath
        aiMode = .disabled
        isProcessingAI = false
        aiSuggestions = []
        lastAIContext = nil
        activeTasks.removeAll()
        recoveryTasks = []
        error = nil
        statusMessage = "Initializing..."
        
        // Reset managers and handlers
        processManager = nil
        localProcess = nil
    }
    
    // MARK: - TerminalViewDelegate Methods Implementation
    
    @MainActor public func scrolled(source: TerminalView, position: Double) {
        // Handle scrolling if needed
    }
    
    @MainActor public func titleChanged(source: TerminalView, title: String) {
        // Update window title if needed
        if let window = source.window {
            window.title = title
        }
    }
    
    @MainActor public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        // Update size when terminal view size changes
        updateSize(cols: newCols, rows: newRows)
    }
    
    @MainActor public func setTerminalTitle(source: TerminalView, title: String) {
        // Update window title if needed
        if let window = source.window {
            window.title = title
        }
    }
    
    @MainActor public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        if let directory = directory {
            currentWorkingDirectory = directory
        }
    }
    
    @MainActor public func clipboardCopy(source: TerminalView, content: Data) {
        // Copy to clipboard using NSPasteboard
        if let string = String(data: content, encoding: .utf8) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(string, forType: .string)
        }
    }
    
    // MARK: - TerminalSessionProtocol Methods Implementation
    
    /// Handles input data (implementation of TerminalSessionProtocol method)
    public func handleInput(data: ArraySlice<UInt8>) {
        // Forward to input handler
        guard let processManager = processManager else { return }
        inputHandler.handleInput(data: data, processManager: processManager)
    }
    
    /// Processes output data (implementation of TerminalSessionProtocol method)
    public func processOutput(data: ArraySlice<UInt8>) {
        // Forward to output handler
        outputHandler.processOutput(data: data, terminalView: terminalView, highlighter: commandHighlighter)
    }
    
    /// Activates the terminal window (implementation of TerminalSessionProtocol method)
    public func activateWindow() {
        guard let view = terminalView else { return }
        ensureWindowActive()
    }
    
    /// Executes a suggested command (implementation of TerminalSessionProtocol method)
    public func executeSuggestion(_ suggestion: CommandSuggestion) {
        sendCommandToProcess(suggestion.command)
    }
    
    // MARK: - Task Management
    
    /// Checks output for command completion
    /// - Parameter output: Terminal output to check
    private func checkForCommandCompletion(_ output: String) {
        // This is a simple heuristic - in a real implementation, this would
        // be more sophisticated, possibly using terminal control codes or
        // special markers to detect command completion
        
        // Check for common shell prompt patterns
        let promptPatterns = [
            #"\$\s*$"#,        // bash/zsh $ prompt
            #"%\s*$"#,         // zsh % prompt
            #">\s*$"#,         // some shell prompts
            #"]\$\s*$"#,       // common prompt pattern with bracket
            #"[^:]+:\s*$"#     // user@host:path$ style prompts 
        ]
        
        // Check if output contains a shell prompt at the end
        let containsPrompt = promptPatterns.contains { pattern in
            output.range(of: pattern, options: .regularExpression) != nil
        }
        
        if containsPrompt {
            // If we have a prompt, it indicates a command has completed
            completeCurrentCommand(output)
        }
    }
    
    /// Completes the current command and updates tasks
    /// - Parameter output: Command output
    private func completeCurrentCommand(_ output: String) {
        // Mark active commands as completed
        Task {
            // Get first in-progress task
            let inProgressTasks = activeTasks.values.filter { $0.status == .inProgress }
            
            for task in inProgressTasks {
                if let taskId = task.id {
                    // Check for exit code - this is a simplistic way
                    // In a real implementation, this would be more sophisticated
                    let exitCode = 0  // Assume success for simplicity
                    
                    // Update task state
                    let updatedTask = await taskPersistenceManager.updateTaskState(taskId) { task in
                        task.status = .completed
                        task.completedAt = Date()
                        task.context?["exitCode"] = String(exitCode)
                        task.context?["output"] = String(output.prefix(1000))  // Truncate long output
                    }
                    
                    // Mark task as completed and archive it
                    await taskPersistenceManager.completeTask(taskId)
                    
                    // Remove from active tasks
                    await MainActor.run {
                        activeTasks.removeValue(forKey: taskId)
                    }
                    
                    // Log command completion
                    await auditLogger.logEvent(
                        category: .command,
                        event: "command_completed",
                        message: "Command completed successfully",
                        severity: .info,
                        details: [
                            "taskId": taskId.uuidString,
                            "exitCode": String(exitCode)
                        ]
                    )
                }
            }
        }
    }
    
    /// Completes all active tasks
    /// - Parameter exitCode: Terminal exit code
    private func completeAllActiveTasks(exitCode: Int32?) {
        Task {
            // Mark all active tasks as completed or failed
            for (taskId, task) in activeTasks {
                if let code = exitCode, code == 0 {
                    // Normal termination - complete tasks
                    await taskPersistenceManager.completeTask(taskId)
                } else {
                    // Abnormal termination - mark tasks as failed
                    await taskPersistenceManager.failTask(
                        taskId,
                        error: "Terminal process terminated with exit code: \(exitCode ?? -1)"
                    )
                }
            }
            
            // Clear active tasks
            await MainActor.run {
                activeTasks.removeAll()
            }
        }
    }
    
    /// Checks for recovery tasks at startup
    private func checkForRecoveryTasks() async {
        do {
            // Get tasks that need recovery
            let tasks = await taskPersistenceManager.recoverFromCrash()
            
            // If we have recovery tasks, handle them
            if !tasks.isEmpty {
                await MainActor.run {
                    recoveryTasks = tasks
                }
                
                // Log recovery
                await auditLogger.logEvent(
                    category: .system,
                    event: "recovery_tasks_found",
                    message: "Found \(tasks.count) tasks to recover from previous session",
                    severity: .info
                )
                
                // Ask user if they want to recover
                // In a real implementation, this would be a UI dialog
                // For this example, we'll automatically attempt recovery with safety checks
                var recoveredCount = 0
                var failedCount = 0
                
                for task in tasks {
                    // Only recover in-progress tasks that were interrupted
                    if task.status == .inProgress {
                        // Add extra validation for sensitive operations
                        let isHighRiskTask = task.type == .fileOperation || 
                                            (task.type == .aiCommand && task.description.contains("rm"))
                        
                        if isHighRiskTask {
                            // Log but don't automatically recover high-risk tasks
                            await auditLogger.logEvent(
                                category: .security,
                                event: "high_risk_task_recovery_skipped",
                                message: "Skipped automatic recovery of high-risk task",
                                severity: .warning,
                                details: [
                                    "taskId": task.id?.uuidString ?? "unknown",
                                    "taskType": task.type.rawValue,
                                    "description": task.description
                                ]
                            )
                            
                            // Mark as failed but with special context
                            if let taskId = task.id {
                                await taskPersistenceManager.updateTaskState(taskId) { state in
                                    state.status = .paused
                                    state.context?["recoveryStatus"] = "skipped_high_risk"
                                }
                            }
                            
                            // In a real app, this would prompt the user explicitly
                            continue
                        }
                        
                        // Apply recovery with proper error handling
                        do {
                            let success = await taskPersistenceManager.handleTaskRecovery(task)
                            
                            if success {
                                recoveredCount += 1
                            } else {
                                failedCount += 1
                            }
                            
                            await auditLogger.logEvent(
                                category: .system,
                                event: "task_recovery_attempt",
                                message: "Recovery attempt for task: \(success ? "succeeded" : "failed")",
                                severity: success ? .info : .warning,
                                details: [
                                    "taskId": task.id?.uuidString ?? "unknown",
                                    "taskType": task.type.rawValue,
                                    "description": task.description
                                ]
                            )
                        } catch {
                            failedCount += 1
                            
                            // Log the error
                            await auditLogger.logError(
                                error,
                                context: "Task recovery",
                                details: [
                                    "taskId": task.id?.uuidString ?? "unknown",
                                    "taskType": task.type.rawValue,
                                    "description": task.description
                                ]
                            )
                        }
                    }
                }
                
                // Log summary
                if recoveredCount > 0 || failedCount > 0 {
                    await auditLogger.logEvent(
                        category: .system,
                        event: "recovery_complete",
                        message: "Task recovery process completed",
                        severity: failedCount > 0 ? .warning : .info,
                        details: [
                            "recoveredCount": "\(recoveredCount)",
                            "failedCount": "\(failedCount)",
                            "totalTasks": "\(tasks.count)"
                        ]
                    )
                }
                
                // Show recovery status to user
                if let view = terminalView, recoveredCount > 0 {
                    await MainActor.run {
                        view.feed(text: "\r\n\u{1b}[32mRecovered \(recoveredCount) tasks from previous session\u{1b}[0m\r\n")
                    }
                }
            }
        } catch {
            // Log any errors during recovery
            await auditLogger.logError(
                error,
                context: "Recovery task initialization",
                details: [
                    "sessionId": sessionId.uuidString
                ]
            )
            
            // Notify the user
            if let view = terminalView {
                await MainActor.run {
                    view.feed(text: "\r\n\u{1b}[31mError recovering tasks from previous session\u{1b}[0m\r\n")
                }
            }
        }
    }
    
    /// Saves the current session state for potential recovery
    /// Recovers tasks from a previous session
    /// - Returns: Array of recovered tasks
    public func recoverTasks(_ tasks: [TaskState]) async {
        guard !tasks.isEmpty else { return }
        
        logger.info("Recovering \(tasks.count) tasks")
        
        // Sort tasks by priority for recovery
        let sortedTasks = tasks.sorted { $0.recoveryPriority > $1.recoveryPriority }
        
        // Process recovery
        for task in sortedTasks {
            // Handle based on task type
            let success = await taskPersistenceManager.handleTaskRecovery(task)
            
            if success {
                logger.info("Successfully recovered task: \(task.id?.uuidString ?? "unknown") - \(task.description)")
                
                // Notify terminal of successful recovery
                await MainActor.run {
                    if let view = terminalView {
                        let message = "\r\n\u{1b}[32mRecovered: \(task.description)\u{1b}[0m\r\n"
                        view.feed(text: message)
                    }
                }
            } else {
                logger.warning("Failed to recover task: \(task.id?.uuidString ?? "unknown") - \(task.description)")
                
                // Notify terminal of recovery failure
                await MainActor.run {
                    if let view = terminalView {
                        let message = "\r\n\u{1b}[31mFailed to recover: \(task.description)\u{1b}[0m\r\n"
                        view.feed(text: message)
                    }
                }
            }
            
            // Small delay between recoveries
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        // Clear recovery tasks after processing
        await MainActor.run {
            recoveryTasks = []
        }
    }
    
    /// Clears recovery tasks without recovering them
    public func clearRecoveryTasks() async {
        // Clear recovery tasks
        await taskPersistenceManager.clearRecoveryTasks()
        
        // Update UI
        await MainActor.run {
            recoveryTasks = []
        }
        
        // Log the action
        await auditLogger.logEvent(
            category: .system,
            event: "recovery_tasks_cleared",
            message: "User cleared recovery tasks without recovering",
            severity: .info,
            details: [
                "sessionId": sessionId.uuidString
            ]
        )
    }
}

// MARK: - Extensions

// Explicitly adopt TerminalViewDelegate protocol
extension TerminalSession: TerminalViewDelegate {}

// Make TerminalSession conform to ShellCommandExecutor for the terminal configuration
extension TerminalSession: ShellCommandExecutor {
    /// Executes a shell command
    public func executeCommand(_ command: String) {
        sendCommandToProcess(command)
    }
}

// Make TerminalSession conform to ConfigurationDelegate
extension TerminalSession: TerminalConfigurationDelegate {
    public func configureTerminal(view: TerminalView) {
        terminalConfiguration.configureTerminal(terminalView: view)
    }
    
    public func windowDidActivate() {
        // Ensure proper terminal focus
        refreshTerminalState()
    }
}

// Make TerminalSession conform to OutputProcessingDelegate
extension TerminalSession: OutputProcessingDelegate {
    public func didProcessOutput(_ output: String) {
        // Process output for command completion detection
        checkForCommandCompletion(output)
    }
}
