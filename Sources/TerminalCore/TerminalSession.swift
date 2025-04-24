import AIIntegration
import Combine
import Darwin  // For ioctl and winsize
import Foundation
import SwiftTerm

@MainActor public class TerminalSession: ObservableObject, @preconcurrency LocalProcessDelegate, TerminalViewDelegate {
    @Published public var isRunning: Bool = false
    @Published public var lastOutput: String = ""
    @Published public var currentWorkingDirectory: String?

    // Terminal dimensions
    @Published public private(set) var currentCols: Int = 80
    @Published public private(set) var currentRows: Int = 25

    // Syntax highlighting
    @Published public private(set) var currentTheme: HighlightTheme
    @Published public var syntaxHighlightingEnabled: Bool = true

    // AI Integration
    @Published public private(set) var aiCoordinator: AITerminalCoordinator
    @Published public private(set) var aiEnabled: Bool = true
    @Published public private(set) var aiMode: AIMode = .disabled
    @Published public private(set) var currentAIModel: AIModel?
    @Published public private(set) var availableModels: [AIModel] = []
    @Published public private(set) var aiSuggestions: [CommandSuggestion] = []
    @Published public private(set) var isProcessingAI: Bool = false
    @Published public private(set) var lastAIContext: String?

    // SwiftTerm Integration
    weak var terminalView: SwiftTerm.TerminalView?
    private var localProcess: SwiftTerm.LocalProcess?

    // Shell configuration
    // Use interactive login shell to ensure proper environment setup
    private let shell: String = "/bin/zsh"
    private let shellArgs: [String] = ["-i", "-l"]  // Interactive and login shell

    // Buffer for typed commands before sending (if needed by UI)
    var commandBuffer: String = ""
    
    // Input handling flags
    private var isHandlingInput = false
    private var pendingInput = Data()

    // Removed duplicate process property since localProcess is the actual instance used
    private let commandHighlighter: ShellCommandHighlighter
    private let codeHighlighter: CodeHighlighter
    private var commandExecutionService: CommandExecutionService
    private var cancellables = Set<AnyCancellable>()

    public init(theme: HighlightTheme = .dark) {
        // Initialize currentWorkingDirectory, could fetch from FileManager
        self.currentWorkingDirectory = FileManager.default.currentDirectoryPath
        self.currentTheme = theme
        self.commandHighlighter = ShellCommandHighlighter()
        self.codeHighlighter = CodeHighlighter()
        self.aiCoordinator = AITerminalCoordinator()
        self.commandExecutionService = CommandExecutionService()

        // Set up safety confirmation handler
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

    /// Ensures that the terminal window is active and focused
    /// Consolidates window activation logic in one place
    private func ensureWindowActive() {
        guard let view = terminalView,
              let window = view.window else { return }
        
        // For window activation, we need to do everything on the main thread
        if !Thread.isMainThread {
            DispatchQueue.main.sync { [weak self] in
                self?.ensureWindowActive()
            }
            return
        }
        
        // Check current window and responder state
        let needsActivation = !window.isKeyWindow || window.firstResponder !== view
        
        if needsActivation {
            print("[TerminalSession] Window activation needed")
            
            // First, ensure window is visible and key
            window.makeKeyAndOrderFront(nil)
            
            // Then set first responder
            if window.firstResponder !== view {
                print("[TerminalSession] Setting first responder to terminal view")
                window.makeFirstResponder(view)
                view.becomeFirstResponder()
            }
            
            // Force cursor visibility and state refresh after activation
            let refreshSequence = [
                "\u{1b}[?25h",    // Show cursor
                "\u{1b}[?12l",    // Disable local echo
                "\u{1b}[4l",      // Reset insert mode
            ].joined()
            view.feed(txt: refreshSequence)
            
            // Give a moment for activation to take effect, then verify again
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                
                if !window.isKeyWindow || window.firstResponder !== view {
                    print("[TerminalSession] Window activation verification failed, retrying")
                    window.makeKeyAndOrderFront(nil)
                    window.makeFirstResponder(view)
                    view.becomeFirstResponder()
                    self.refreshTerminalState()
                }
            }
        }
    }
    
    /// Ensures the terminal view has proper focus
    /// Ensures the terminal view has proper focus - REMOVED, use ensureWindowActive instead
    private func refreshTerminalState() {
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
            "\u{1b}]0;LlamaTerminal\u{7}", // Reset window title (helps with focus issues)
        ].joined()
        
        // Set proper terminal options through the terminal object if available
        if let terminal = view.getTerminal() {
            // These options are crucial for proper terminal behavior
            terminal.setOption(.cursorVisible, true)
            terminal.setOption(.cursorBlink, true)
            terminal.setOption(.bracketedPasteMode, true)
            terminal.setOption(.altSendsEscape, true)   // Ensure Alt/Meta keys work properly
            terminal.setOption(.allowMouseReporting, true) // Make mouse clicks work in apps like vim
        }
        
        // Send control sequences to terminal
        print("[TerminalSession] Sending terminal control sequences")
        view.feed(txt: refreshSequence)
        
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
        
        // Set delegate
        view.delegate = self
        
        // Configure terminal view colors first
        view.configureNativeColors()
        view.installColors(.defaultDark)
        
        // Clear screen and ensure clean state before any other initialization
        view.feed(txt: "\u{1b}[2J\u{1b}[H")  // Clear screen and home cursor
        Thread.sleep(forTimeInterval: 0.05)  // Brief pause
        
        // Initialize terminal size
        if let size = view.getOptimalTtySize() {
            self.currentCols = size.cols > 0 ? Int(size.cols) : 80
            self.currentRows = size.rows > 0 ? Int(size.rows) : 25
        }
        
        // Perform basic initialization immediately
        if let terminal = view.getTerminal() {
            terminal.resetToInitialState()
            terminal.setOption(.cursorVisible, true)
            terminal.setOption(.cursorBlink, true)
            terminal.setOption(.bracketedPasteMode, true)
            terminal.setEncoding(.utf8)
        }
        
        // Set initial window state
        if let window = view.window {
            DispatchQueue.main.sync {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(view)
                view.becomeFirstResponder()
            }
        }
    }
    
    /// Performs a thorough terminal reset and initialization
    /// Performs a thorough terminal reset and initialization
    private func performFullTerminalReset(_ view: SwiftTerm.TerminalView) {
        print("[TerminalSession] Performing full terminal reset sequence")
        
        // First, use the SwiftTerm built-in reset capabilities
        if let terminal = view.getTerminal() {
            terminal.resetToInitialState()
            
            // Set essential terminal options
            terminal.setOption(.allowMouseReporting, true)
            terminal.setOption(.bracketedPasteMode, true)
            terminal.setOption(.cursorBlink, true)
            terminal.setOption(.cursorVisible, true)
            terminal.setEncoding(.utf8)
        }
        
        // Apply single, consolidated reset sequence in proper order
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
        view.feed(txt: resetSequence)
        
        // Give terminal a moment to process, then clear screen once more
        Thread.sleep(forTimeInterval: 0.05)
        view.feed(txt: "\u{1b}[2J\u{1b}[H\u{1b}[?25h") // Clear, home cursor, and show cursor
    }
    
    @MainActor public func startSession(terminalView: SwiftTerm.TerminalView) async {
        print("[TerminalSession] startSession called.")
        
        // Reset state
        self.isRunning = false
        self.pendingInput = Data()
        self.isHandlingInput = false
        self.lastOutput = ""
        
        // STEP 1: Initialize terminal view first with proper setup
        // Initialize the terminal view before anything else to ensure proper setup
        initializeTerminalView(terminalView)
        
        // STEP 2: Ensure window activation - CRITICAL for preventing input echo issues
        if let view = terminalView, let window = view.window {
            print("[TerminalSession] Activating window before process start")
            
            // Use synchronous activation to ensure proper window focus
            DispatchQueue.main.sync {
                // First, ensure window is ordered front
                window.makeKeyAndOrderFront(nil)
                Thread.sleep(forTimeInterval: 0.05) // Brief pause for window operation
                
                // Then set focus
                window.makeFirstResponder(view)
                view.becomeFirstResponder()
            }
            
            // Wait for window activation to take effect
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        // STEP 3: Initialize LocalProcess with proper PTY configuration
        self.localProcess = SwiftTerm.LocalProcess(delegate: self)
        guard let localProcess = self.localProcess else {
            print("[TerminalSession] Error: Failed to create LocalProcess.")
            
            // Display error in terminal view
            if let view = self.terminalView {
                view.feed(txt: "\r\nFailed to initialize terminal process. Please restart the application.\r\n")
            }
            
            self.lastOutput = "Failed to initialize terminal process handler."
            return
        }
        
        // STEP 4: Set up environment variables
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
        environment["SHELL"] = shell
        environment["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["HOME"] = ProcessInfo.processInfo.environment["HOME"]
        environment["USER"] = ProcessInfo.processInfo.environment["USER"]
        environment["LOGNAME"] = ProcessInfo.processInfo.environment["USER"]
        environment["PWD"] = FileManager.default.currentDirectoryPath
        
        // Let shell handle its own initialization (don't override PS1)
        environment.removeValue(forKey: "ZDOTDIR")
        environment.removeValue(forKey: "PS1")
        
        // Convert environment to string array
        let envStrings = environment.map { "\($0.key)=\($0.value)" }
        
        // STEP 5: Final verification of window and terminal state before process start
        if let view = terminalView, let window = view.window {
            // One last check to ensure the window is active and view is first responder
            if !window.isKeyWindow || window.firstResponder !== view {
                print("[TerminalSession] Window not properly activated, forcing activation")
                DispatchQueue.main.sync {
                    window.makeKeyAndOrderFront(nil)
                    window.makeFirstResponder(view)
                    view.becomeFirstResponder()
                }
            }
            
            // Consolidated terminal initialization before process start
            print("[TerminalSession] Performing final terminal reset before process start")
            
            // Perform complete terminal reset with a clean slate
            performFullTerminalReset(view)
            
            // Ensure window is active before starting process (critical for input focus)
            print("[TerminalSession] Final window activation before process start")
            DispatchQueue.main.sync {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(view)
                view.becomeFirstResponder()
            }
            // Give time for activation to take effect
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        // STEP 6: Start the process with proper error handling
        do {
            // Start the process with environment and shell args
            print("[TerminalSession] Starting LocalProcess with command: \(shell) \(shellArgs.joined(separator: " "))")
            try localProcess.startProcess(
                executable: self.shell,
                args: shellArgs,
                environment: envStrings,
                cols: UInt16(self.currentCols),    // Add current size
                rows: UInt16(self.currentRows)     // Add current size
            )
            
            // Mark as running only after process starts successfully
            self.isRunning = true
            
            // Process started successfully - no need to immediately force activation
            // The terminal is already properly initialized and focused
        } catch {
            print("[TerminalSession] Error starting process: \(error.localizedDescription)")
            
            if let view = self.terminalView {
                view.feed(txt: "\r\nError starting terminal process: \(error.localizedDescription)\r\n")
            }
            
            self.lastOutput = "Failed to start terminal process: \(error.localizedDescription)"
            return
        }
        
        // Configure terminal with minimal settings in a separate task
        Task {
            do {
                // Give the process time to start before sending any commands
                // This delay is crucial for proper echo behavior
                try await Task.sleep(nanoseconds: 500_000_000)  // 500ms delay
                
                // Set basic terminal options with better defaults for input echo
                // Break these into stages for better reliability
                
                // Stage 1: Basic TTY configuration
                let initCommands1 = [
                    "stty sane",                  // Reset to sane terminal settings (primary reset)
                    "sleep 0.1",                  // Brief pause for settings to take effect
                    "stty echo",                  // Ensure echo is on (basic setting)
                    "stty icrnl onlcr",           // Handle line endings (crucial for proper display)
                ]
                
                // Stage 2: Enhanced TTY settings
                let initCommands2 = [
                    "stty echoe echok echoke",    // Enhanced echo control options
                    "stty icanon",                // Enable canonical mode
                    "stty erase '^?'",            // Set erase character
                    "stty intr '^C'",             // Set interrupt character
                    "stty isig",                  // Enable signals
                    "stty ixon",                  // Enable flow control
                ]
                
                // Stage 3: Additional optimization
                let initCommands3 = [
                    "stty susp '^Z'",             // Set suspend character
                    "stty werase '^W'",           // Set word erase
                    "stty kill '^U'",             // Set line kill
                    "stty -tostop",               // Prevent background processes from stopping on output
                    "stty -echoctl",              // Don't echo control characters as ^X
                    // Configure shell
                    "bindkey -e",                 // Emacs key bindings
                    "setopt PROMPT_SUBST",        // Enable prompt substitution
                    "setopt INTERACTIVE_COMMENTS", // Allow comments
                    "export TERM=xterm-256color", // Ensure terminal type is set properly
                ]
                
                // Send commands in stages with proper error handling
                async let stage1 = self.sendCommands(initCommands1, delay: 100_000_000)  // 100ms delay
                await stage1
                
                async let stage2 = self.sendCommands(initCommands2, delay: 75_000_000)   // 75ms delay
                await stage2
                
                async let stage3 = self.sendCommands(initCommands3, delay: 50_000_000)   // 50ms delay
                await stage3
                
                // Final window activation after all initialization
                try await Task.sleep(nanoseconds: 200_000_000)  // 200ms delay for everything to settle
                
                // Only refresh the state if needed, don't force activation
                await MainActor.run {
                    if let view = self.terminalView, let window = view.window {
                        // Only activate if not already active
                        if !window.isKeyWindow || window.firstResponder !== view {
                            // Force refresh before activation for best results
                            view.feed(txt: "\u{1b}[?25h") // Just ensure cursor is visible
                            self.ensureWindowActive()
                        }
                    }
                }
                
                // Initialize AI features after terminal is fully configured - removed duplicate call
                // The initialization is already done at startup
            } catch {
                print("[TerminalSession] Error during terminal configuration: \(error)")
            }
        } // End of Task block
    }  // End of startSession function
    
    /// Helper to send a batch of shell commands with proper error handling
    private func sendCommands(_ commands: [String], delay: UInt64) async {
        for cmd in commands {
            guard self.isRunning, let proc = self.localProcess else {
                print("[TerminalSession] Process not available for command: \(cmd)")
                break
            }
            
            proc.send(data: ArraySlice((cmd + "\n").utf8))
            
            // Wait briefly between commands to ensure they're processed correctly
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                print("[TerminalSession] Error in sleep between commands: \(error.localizedDescription)")
            }
        }
    }

    public func sendToProcess(data: ArraySlice<UInt8>) {
        guard isRunning, let localProcess = self.localProcess else {
            print(
                "[TerminalSession] Cannot send data: Session not running or process not initialized."
            )
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
            process.resize(rows: UInt16(rows), cols: UInt16(cols))
            
            // Send updated size to terminal
            if let view = terminalView {
                // Update terminal about its new size
                let sizeSequence = "\u{1b}[8;\(rows);\(cols)t"
                view.feed(txt: sizeSequence)
            }
        }
    }
    // --- LocalProcessDelegate Methods ---

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
        }
        // Don't force window activation during data receipt - this can cause focus issues
        // and disrupt user interaction with the terminal
    }

    @MainActor public func processTerminated(_ process: LocalProcess, exitCode: Int32?) {
        // Only show termination message if we were actually running
        // This prevents premature "terminal session has ended" messages
        guard isRunning else { return }
        
        let statusText = exitCode != nil ? "status: \(exitCode!)" : "signal or error"
        print("[TerminalSession] processTerminated delegate: \(statusText)")
        
        // Update state
        isRunning = false
        localProcess = nil
        
        // Keep terminal view active but clear screen
        if let view = terminalView {
            // Clear screen and reset cursor
            view.feed(txt: "\u{1b}[2J\u{1b}[H")
            
            // Display termination message
            let terminationMessage = """
                \r\n
                Terminal session ended (\(statusText))
                Press Enter to start a new session, or use Command+N for a new window.
                \r\n
                """
            view.feed(txt: terminationMessage)
            
            // Ensure terminal view remains first responder using our consolidated method
            ensureWindowActive()
        }
        
        // Update last output
        lastOutput = "Terminal process terminated (\(statusText))"
    }

    @MainActor public func getWindowSize() -> winsize {
        // Ensure we never return invalid dimensions
        let rows = max(UInt16(self.currentRows), 10)
        let cols = max(UInt16(self.currentCols), 40)
        
        let ws = winsize(
            ws_row: rows, 
            ws_col: cols, 
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        
        print("[TerminalSession] getWindowSize delegate reporting: \(ws.ws_col)x\(ws.ws_row)")  // DEBUG
        return ws
    }

    // MARK: - AI Integration Methods

    /// Initializes AI features by fetching available models
    private func initializeAIFeatures() async {
        // Try to initialize the AI coordinator
        let success = await aiCoordinator.initialize()

        if success {
            // Update available models
            self.availableModels = await aiCoordinator.getAvailableModels()

            // Set initial model if available
            if let model = await aiCoordinator.currentModel {
                self.currentAIModel = model
            }

            // Default to Auto mode if a model is available
            if self.currentAIModel != nil {
                await setAIMode(.auto)
            }
        } else {
            print("Failed to initialize AI features. Check if Ollama is running.")
            self.aiEnabled = false
        }
    }

    /// Sets the AI mode
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
    /// - Parameter command: Command to process
    private func processUserCommand(_ command: String) async {
        guard aiEnabled, aiMode != .disabled else {
            sendCommandToProcess(command)  // Send command directly if AI disabled
            return
        }

        self.isProcessingAI = true

        do {
            // Process through AI coordinator
            let response = try await aiCoordinator.processInput(command)

            // Update suggestions
            await MainActor.run {
                self.aiSuggestions = response.suggestions
                if let context = response.context {
                    self.lastAIContext = context
                }
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
            await MainActor.run {
                self.lastAIContext = "AI processing error: \(error.localizedDescription)"
                self.isProcessingAI = false
            }

            // Fall back to sending the original command even on AI error
            sendCommandToProcess(command)
        }

        await MainActor.run {
            self.isProcessingAI = false
        }
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

    /// Executes a suggested command
    /// - Parameter suggestion: Command suggestion to execute
    public func executeSuggestion(_ suggestion: CommandSuggestion) {
        guard isRunning else { return }

        if suggestion.requiresConfirmation {
            // For now, echo the suggestion and ask for confirmation
            guard let terminalWrapper = terminalView else { return }

            let safetyIndicator: String
            switch suggestion.safetyLevel {
            case .safe: safetyIndicator = "✅ SAFE"
            case .moderate: safetyIndicator = "⚠️ MODIFIES FILES/STATE"
            case .destructive: safetyIndicator = "🔴 DESTRUCTIVE"
            }

            let confirmationMessage = """

                COMMAND SUGGESTION:
                \(suggestion.command)

                EXPLANATION:
                \(suggestion.explanation)

                SAFETY: \(safetyIndicator)

                Execute? (y/n): 
                """

            terminalWrapper.send(txt: "echo -e '\(confirmationMessage)'\n")

            // In a real UI, we would wait for confirmation
            // For demo purposes, auto-confirm safe commands
            if suggestion.safetyLevel == .safe {
                sendCommandToProcess(suggestion.command)  // Use helper
            }
        } else {
            sendCommandToProcess(suggestion.command)  // Use helper
        }
    }

    // Helper to send a command string to the process
    public func sendCommandToProcess(_ command: String) {
        let commandWithNewline = command + "\n"
        if let data = commandWithNewline.data(using: .utf8) {
            print("[TerminalSession] Sending command string: \(command)")  // DEBUG
            sendToProcess(data: ArraySlice(data))
        }
    }
    
    // MARK: - TerminalViewDelegate Methods
    
    public func scrolled(source: TerminalView, position: Double) {
        // Handle scrolling if needed
    }
    
    public func titleChanged(source: TerminalView, title: String) {
        // Update window title if needed
    }
    
    public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        print("[TerminalSession] Size changed: \(newCols)x\(newRows)")
        updateSize(cols: newCols, rows: newRows)
    }
    
    public func setTerminalTitle(source: TerminalView, title: String) {
        if let window = source.window {
            window.title = title
        }
    }
}  // End of TerminalSession class
