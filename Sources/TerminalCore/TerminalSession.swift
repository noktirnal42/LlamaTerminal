import AIIntegration
import Combine
import Darwin  // For ioctl and winsize
import Foundation
import SwiftTerm

@MainActor public class TerminalSession: ObservableObject, @preconcurrency LocalProcessDelegate {
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
    // Revert back to zsh -i
    private let shell: String = "/bin/zsh"
    private let shellArgs: [String] = ["-i"]

    // Buffer for typed commands before sending (if needed by UI)
    var commandBuffer: String = ""

    private var process: Process?
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

    @MainActor public func startSession(terminalView: SwiftTerm.TerminalView) async {
        print("[TerminalSession] startSession called.")  // DEBUG
        self.terminalView = terminalView
        // Ensure delegate is set *before* starting process
        self.localProcess = SwiftTerm.LocalProcess(delegate: self)

        // Prepare environment as [String] = ["KEY=VALUE"]
        var envStrings: [String] = []
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["LANG"] = "en_US.UTF-8"  // Often needed for PTYs
        for (key, value) in environment {
            envStrings.append("\(key)=\(value)")
        }

        Task {  // Initialize AI in background
            await initializeAIFeatures()
        }

        if let process = self.localProcess {
            print(
                "[TerminalSession] Starting LocalProcess with command: \(shell) \(shellArgs.joined(separator: " "))"
            )  // DEBUG
            process.startProcess(
                executable: self.shell,
                args: self.shellArgs,
                environment: envStrings
            )
        } else {
            // Error handling as before
            print("[TerminalSession] Error: Failed to create LocalProcess.")
            self.isRunning = false
            self.lastOutput = "Failed to initialize terminal process handler."
        }
    }  // End startSession function

    public func sendToProcess(data: ArraySlice<UInt8>) {
        guard isRunning, let process = localProcess else {
            print(
                "[TerminalSession] Cannot send data: Session not running or process not initialized."
            )
            return
        }
        // DEBUG: Print data being sent
        let str = String(bytes: data, encoding: .utf8) ?? "Non-UTF8 Data"
        print(
            "[TerminalSession] Sending data to process: \(str.replacingOccurrences(of: "\\n", with: "\\\\n").replacingOccurrences(of: "\\r", with: "\\\\r"))"
        )
        process.send(data: data)
    }

    public func terminateSession() {
        print("[TerminalSession] terminateSession called.")  // DEBUG
        localProcess?.terminate()
        localProcess = nil  // Release reference
        terminalView = nil
        isRunning = false  // Update state immediately
    }

    public func updateSize(cols: Int, rows: Int) {
        print("[TerminalSession] Updating internal size to: \(cols)x\(rows)")  // DEBUG
        self.currentCols = cols
        self.currentRows = rows
        // SwiftTerm will call getWindowSize() when it needs to inform the PTY
        // localProcess?.winch(rows: rows, cols: cols) // REMOVED
    }

    // --- LocalProcessDelegate Methods ---

    @MainActor public func dataReceived(slice: ArraySlice<UInt8>) {
        print("[TerminalSession] dataReceived delegate: \(slice.count) bytes")  // DEBUG
        guard let view = terminalView else {
            print("[TerminalSession] Error: terminalView is nil in dataReceived.")
            return
        }
        view.feed(byteArray: slice)
        if !isRunning { isRunning = true }
    }

    @MainActor public func processTerminated(_ process: LocalProcess, exitCode: Int32?) {
        // Use optional exitCode
        let statusText = exitCode != nil ? "status: \(exitCode!)" : "signal or error"
        print("[TerminalSession] processTerminated delegate: \(statusText)")  // DEBUG
        isRunning = false
        lastOutput = "Terminal process terminated (\(statusText))"
        localProcess = nil
        terminalView = nil
    }

    @MainActor public func getWindowSize() -> winsize {
        let ws = winsize(
            ws_row: UInt16(self.currentRows), ws_col: UInt16(self.currentCols), ws_xpixel: 0,
            ws_ypixel: 0)
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
                    let stream = try await aiCoordinator.pullModel(modelName)
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
}  // End of TerminalSession class
