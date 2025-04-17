import XCTest
@testable import AIIntegration

final class AIModeTests: XCTestCase {
    // Test Models
    let testModel = AIModel(
        id: "test-model",
        name: "test-model",
        size: 1000,
        modified: Date(),
        capabilities: ModelCapabilities(
            isCodeCapable: true,
            isCommandOptimized: true
        )
    )
    
    // MARK: - Auto Mode Tests
    
    func testAutoModeInitialization() async {
        let handler = MockAutoModeHandler(model: testModel)
        let state = await handler.getState()
        XCTAssertEqual(handler.model.id, testModel.id)
        XCTAssertTrue(state.isActive)
        XCTAssertTrue(state.context.isEmpty)
        XCTAssertTrue(state.pendingActions.isEmpty)
    }
    
    func testAutoModeContextManagement() async throws {
        let handler = MockAutoModeHandler(model: testModel)
        
        // Test processing multiple inputs
        _ = try await handler.processInput("ls -la")
        _ = try await handler.processInput("cd Documents")
        
        // Verify context is updated
        let state = await handler.getState()
        XCTAssertEqual(state.context.count, 2)
        XCTAssertEqual(state.context[0], "ls -la")
        XCTAssertEqual(state.context[1], "cd Documents")
        
        // Test reset
        await handler.reset()
        let resetState = await handler.getState()
        XCTAssertTrue(resetState.context.isEmpty)
    }
    
    func testAutoModeSuggestionGeneration() async throws {
        let handler = MockAutoModeHandler(model: testModel)
        handler.mockSuggestions = [
            CommandSuggestion(
                command: "ls -la",
                explanation: "List all files including hidden ones",
                safetyLevel: .safe
            ),
            CommandSuggestion(
                command: "find . -name '*.swift'",
                explanation: "Find Swift files",
                safetyLevel: .safe
            )
        ]
        
        let response = try await handler.processInput("find files")
        
        // Verify suggestions
        XCTAssertEqual(response.suggestions.count, 2)
        XCTAssertEqual(response.suggestions[0].command, "ls -la")
        XCTAssertEqual(response.suggestions[1].command, "find . -name '*.swift'")
    }
    
    func testAutoModeCommandResultAnalysis() async throws {
        let handler = MockAutoModeHandler(model: testModel)
        handler.mockAnalysis = "Command executed successfully. Found 5 Swift files."
        
        let result = CommandResult(
            command: "find . -name '*.swift'",
            output: "file1.swift\nfile2.swift\nfile3.swift\nfile4.swift\nfile5.swift",
            exitCode: 0,
            duration: 0.1
        )
        
        let response = try await handler.handleCommandResult(result)
        
        // Verify analysis
        XCTAssertEqual(response.context, "Command executed successfully. Found 5 Swift files.")
        
        // Verify context is updated with command and result
        let state = await handler.getState()
        XCTAssertEqual(state.context.count, 2)
        XCTAssertEqual(state.context[0], "$ find . -name '*.swift'")
        XCTAssertTrue(state.context[1].contains("file1.swift"))
    }
    
    // MARK: - Dispatch Mode Tests
    
    func testDispatchModeInitialization() async {
        let handler = MockDispatchModeHandler(model: testModel)
        let state = await handler.getState()
        XCTAssertEqual(handler.model.id, testModel.id)
        XCTAssertTrue(state.isActive)
        XCTAssertTrue(state.context.isEmpty)
        XCTAssertTrue(state.pendingActions.isEmpty)
    }
    
    func testDispatchModeTaskPlanning() async throws {
        let handler = MockDispatchModeHandler(model: testModel)
        
        // Prepare test actions
        let actions = [
            createTestAction("mkdir -p project"),
            createTestAction("cd project"),
            createTestAction("git init")
        ]
        handler.mockActions = actions
        
        let response = try await handler.processInput("Set up a new project")
        
        // Verify plan was created
        XCTAssertEqual(response.actions.count, 1)
        XCTAssertEqual(response.actions[0].content, "mkdir -p project")
        XCTAssertTrue(response.context?.contains("Task planned with 3 steps") ?? false)
        
        // Verify state updates
        let state = await handler.getState()
        XCTAssertEqual(state.pendingActions.count, 3)
    }
    
    func testDispatchModeStepExecution() async throws {
        let handler = MockDispatchModeHandler(model: testModel)
        
        // Prepare test actions
        let actions = [
            createTestAction("mkdir -p project"),
            createTestAction("cd project"),
            createTestAction("git init")
        ]
        handler.mockActions = actions
        
        // First, plan the task
        _ = try await handler.processInput("Set up a new project")
        
        // Execute first step successfully
        let firstResult = CommandResult(
            command: "mkdir -p project",
            output: "",
            exitCode: 0,
            duration: 0.1
        )
        
        let response = try await handler.handleCommandResult(firstResult)
        
        // Verify next step is provided
        XCTAssertEqual(response.actions.count, 1)
        XCTAssertEqual(response.actions[0].content, "cd project")
        XCTAssertTrue(response.context?.contains("Proceeding with step 2") ?? false)
    }
    
    func testDispatchModeErrorHandling() async throws {
        let handler = MockDispatchModeHandler(model: testModel)
        
        // Prepare test actions
        let actions = [
            createTestAction("git clone https://github.com/user/repo.git"),
            createTestAction("cd repo"),
            createTestAction("npm install")
        ]
        handler.mockActions = actions
        
        // Prepare recovery actions
        let recoveryActions = [
            createTestAction("mkdir -p repo"),
            createTestAction("cd repo"),
            createTestAction("git init")
        ]
        handler.mockRecoveryActions = recoveryActions
        
        // Plan a task
        _ = try await handler.processInput("Clone and set up repository")
        
        // Simulate a failed command
        let failedResult = CommandResult(
            command: "git clone https://github.com/user/repo.git",
            output: "fatal: repository not found",
            exitCode: 128,
            duration: 0.1
        )
        
        let response = try await handler.handleCommandResult(failedResult)
        
        // Verify error handling
        XCTAssertTrue(response.context?.contains("Encountered error") ?? false)
        
        // Verify recovery action is provided
        XCTAssertEqual(response.actions.count, 1)
        XCTAssertEqual(response.actions[0].content, "mkdir -p repo")
    }
    
    func testDispatchModeTaskCompletion() async throws {
        let handler = MockDispatchModeHandler(model: testModel)
        
        // Prepare test actions (just one action)
        handler.mockActions = [createTestAction("echo 'Hello World'")]
        handler.mockCompletionSummary = "Task completed successfully. Displayed hello world message."
        
        // Plan and start the task
        _ = try await handler.processInput("Display hello world")
        
        // Execute the step successfully
        let result = CommandResult(
            command: "echo 'Hello World'",
            output: "Hello World",
            exitCode: 0,
            duration: 0.1
        )
        
        let response = try await handler.handleCommandResult(result)
        
        // Verify completion
        XCTAssertTrue(response.actions.isEmpty)
        XCTAssertEqual(response.context, "Task completed successfully. Displayed hello world message.")
    }
    
    func testDispatchModeUnrecoverableError() async throws {
        let handler = MockDispatchModeHandler(model: testModel)
        
        // Prepare test actions
        handler.mockActions = [createTestAction("invalid_command")]
        handler.mockRecoveryActions = [] // Empty indicates recovery not possible
        
        // Plan and start the task
        _ = try await handler.processInput("Run invalid command")
        
        // Execute the step with a failure
        let result = CommandResult(
            command: "invalid_command",
            output: "command not found: invalid_command",
            exitCode: 127,
            duration: 0.1
        )
        
        let response = try await handler.handleCommandResult(result)
        
        // Verify task abandonment
        XCTAssertTrue(response.actions.isEmpty)
        XCTAssertTrue(response.context?.contains("Task failed") ?? false)
    }
    
    // MARK: - Command Parsing Tests
    
    func testCommandParsing() async throws {
        let parsingService = CommandParsingService()
        
        // Test parsing multiple command suggestions
        let suggestionsText = """
        Command: ls -la
        Explanation: List all files in long format
        Safety: safe
        
        Command: df -h
        Explanation: Show disk usage
        Safety: safe
        
        Command: find . -name "*.txt"
        Explanation: Find all text files
        Safety: moderate
        """
        
        let suggestions = try await parsingService.parseSuggestions(from: suggestionsText)
        
        XCTAssertEqual(suggestions.count, 3)
        XCTAssertEqual(suggestions[0].command, "ls -la")
        XCTAssertEqual(suggestions[1].command, "df -h")
        XCTAssertEqual(suggestions[2].command, "find . -name \"*.txt\"")
        XCTAssertEqual(suggestions[2].safetyLevel, .moderate)
    }
    
    func testCommandValidation() async throws {
        let parsingService = CommandParsingService()
        
        // Test safe command
        let safeCommand = """
        Command: ls -l
        Explanation: List files in long format
        Safety: safe
        """
        let safeSuggestions = try await parsingService.parseSuggestions(from: safeCommand)
        XCTAssertEqual(safeSuggestions.first?.safetyLevel, .safe)
        
        // Test moderate command
        let moderateCommand = """
        Command: git checkout -b feature
        Explanation: Create and switch to new branch
        Safety: moderate
        """
        let moderateSuggestions = try await parsingService.parseSuggestions(from: moderateCommand)
        XCTAssertEqual(moderateSuggestions.first?.safetyLevel, .moderate)
        
        // Test destructive command
        let destructiveCommand = """
        Command: rm -rf .git
        Explanation: Remove git repository
        Safety: destructive
        """
        let destructiveSuggestions = try await parsingService.parseSuggestions(from: destructiveCommand)
        XCTAssertEqual(destructiveSuggestions.first?.safetyLevel, .destructive)
        XCTAssertTrue(destructiveSuggestions.first?.requiresConfirmation ?? false)
    }
    
    func testForbiddenCommandRejection() async throws {
        let parsingService = CommandParsingService()
        
        // Test forbidden command
        let forbiddenCommand = """
        Command: rm -rf /
        Explanation: Remove everything
        Safety: destructive
        """
        
        do {
            _ = try await parsingService.parseSuggestions(from: forbiddenCommand)
            XCTFail("Should have thrown an error for forbidden command")
        } catch let error as CommandValidationError {
            XCTAssertEqual(error.localizedDescription, "Command is forbidden: rm -rf /")
        }
    }
    
    func testResponsePreprocessing() async throws {
        let parsingService = CommandParsingService()
        
        // Test code block conversion
        let codeBlockResponse = """
        Here are some useful commands:
        ```bash
        ls -la
        cd Documents
        ```
        These will help you navigate.
        """
        
        let processed = await parsingService.preprocessResponse(codeBlockResponse)
        
        XCTAssertTrue(processed.contains("Command: ls -la"))
        XCTAssertTrue(processed.contains("Command: cd Documents"))
    }
    
    // MARK: - Async and Concurrency Tests
    
    func testAsyncCommandProcessing() async throws {
        let handler = MockAutoModeHandler(model: testModel)
        
        // Setup mock suggestions that will be returned after a delay
        handler.mockSuggestions = [
            CommandSuggestion(command: "find . -name '*.swift'", 
                             explanation: "Find Swift files", 
                             safetyLevel: .safe)
        ]
        handler.mockDelay = 0.2 // Simulate network delay
        
        // Capture start time
        let startTime = Date()
        
        // Process input
        let response = try await handler.processInput("find swift files")
        
        // Verify delay occurred (handles async properly)
        let processingTime = Date().timeIntervalSince(startTime)
        XCTAssertGreaterThanOrEqual(processingTime, 0.2)
        
        // Verify expected response
        XCTAssertEqual(response.suggestions.count, 1)
    }
    
    func testConcurrentInputProcessing() async throws {
        let handler = MockAutoModeHandler(model: testModel)
        
        // Set up different suggestions for concurrent requests
        let suggestions1 = [CommandSuggestion(command: "ls", explanation: "List files", safetyLevel: .safe)]
        let suggestions2 = [CommandSuggestion(command: "pwd", explanation: "Show working directory", safetyLevel: .safe)]
        
        // Create tracking for which suggestion set was used
        var usedSuggestions: [Int] = []
        handler.mockSuggestionsProvider = { input in
            if input.contains("list") {
                usedSuggestions.append(1)
                return suggestions1
            } else {
                usedSuggestions.append(2)
                return suggestions2
            }
        }
        
        // Process multiple inputs concurrently
        async let response1 = handler.processInput("list files")
        async let response2 = handler.processInput("current directory")
        
        // Wait for both to complete
        let responses = try await [response1, response2]
        
        // Verify both were processed
        XCTAssertEqual(responses.count, 2)
        let state = await handler.getState()
        XCTAssertEqual(state.context.count, 2)
        
        // Verify suggestions were matched to correct inputs
        XCTAssertEqual(usedSuggestions.count, 2)
        XCTAssertTrue(usedSuggestions.contains(1))
        XCTAssertTrue(usedSuggestions.contains(2))
    }
    
    func testTimeoutHandling() async throws {
        let handler = MockAutoModeHandler(model: testModel)
        
        // Setup a suggestion provider that simulates a timeout
        handler.mockSuggestionsProvider = { input in
            // Simulate network delay longer than timeout
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            throw NSError(domain: "AIIntegration", code: NSURLErrorTimedOut, userInfo: nil)
        }
        
        // Reduce timeout to 0.1 seconds for testing
        handler.mockTimeout = 0.1
        
        do {
            _ = try await handler.processInput("slow command")
            XCTFail("Should have thrown a timeout error")
        } catch {
            // Success - timeout was properly thrown
            XCTAssertEqual((error as NSError).code, NSURLErrorTimedOut)
        }
        
        // Verify context was still updated despite the error
        let state = await handler.getState()
        XCTAssertEqual(state.context.count, 1)
        XCTAssertEqual(state.context[0], "slow command")
    }
    
    // MARK: - Edge Case Tests
    
    func testEmptyInputHandling() async throws {
        let handler = MockAutoModeHandler(model: testModel)
        
        // Test empty input
        let response = try await handler.processInput("")
        
        // Verify empty input is handled gracefully
        XCTAssertTrue(response.suggestions.isEmpty)
        let state = await handler.getState()
        XCTAssertEqual(state.context.count, 1)
        XCTAssertEqual(state.context[0], "")
    }
    
    func testDispatchModeTaskInterruption() async throws {
        let handler = MockDispatchModeHandler(model: testModel)
        
        // Setup a multi-step task
        handler.mockActions = [
            createTestAction("step1"),
            createTestAction("step2"),
            createTestAction("step3")
        ]
        
        // Start the task
        _ = try await handler.processInput("multi-step task")
        
        // Execute the first step
        _ = try await handler.handleCommandResult(CommandResult(
            command: "step1",
            output: "completed",
            exitCode: 0,
            duration: 0.1
        ))
        
        // Now start a new task (interrupting the current one)
        handler.mockActions = [
            createTestAction("new-task-step")
        ]
        
        let interruptResponse = try await handler.processInput("new task")
        
        // Verify the new task replaced the old one
        // Verify the new task replaced the old one
        XCTAssertEqual(interruptResponse.actions.count, 1)
        XCTAssertEqual(interruptResponse.actions[0].content, "new-task-step")
        let state = await handler.getState()
        XCTAssertEqual(state.pendingActions.count, 1)
    }
    
    func testStateConsistencyDuringErrors() async throws {
        let handler = MockDispatchModeHandler(model: testModel)
        
        // Setup actions that will fail
        handler.mockActions = [createTestAction("failing-command")]
        
        // Start task
        _ = try await handler.processInput("will fail")
        
        // Capture state after planning
        let stateAfterPlanning = await handler.getState()
        XCTAssertEqual(stateAfterPlanning.pendingActions.count, 1)
        
        // Force recovery to fail
        handler.mockRecoveryActions = []
        handler.mockRecoveryThrows = true
        
        do {
            _ = try await handler.handleCommandResult(CommandResult(
                command: "failing-command",
                output: "error",
                exitCode: 1,
                duration: 0.1
            ))
            XCTFail("Should have thrown an error")
        } catch {
            // Success - error was thrown
        }
        
        // Verify state was reset properly despite error
        let finalState = await handler.getState()
        XCTAssertTrue(finalState.pendingActions.isEmpty)
        XCTAssertTrue(finalState.context.isEmpty)
    }
    
    // MARK: - Stream Processing Edge Cases
    
    func testStreamProcessingLargeOutput() async throws {
        let handler = MockAutoModeHandler(model: testModel)
        
        // Generate a large output that needs to be truncated
        let largeOutput = String(repeating: "This is a very long line of output.\n", count: 100)
        let result = CommandResult(
            command: "generate_large_output",
            output: largeOutput,
            exitCode: 0,
            duration: 0.1
        )
        
        let response = try await handler.handleCommandResult(result)
        
        // Verify truncation occurred
        let state = await handler.getState()
        XCTAssertTrue(state.context.last?.contains("... (output truncated)") ?? false)
        XCTAssertLessThan(state.context.last?.count ?? 0, largeOutput.count)
    }
    
    func testStreamProcessingSpecialCharacters() async throws {
        let handler = MockAutoModeHandler(model: testModel)
        
        // Test output with ANSI escape codes and special characters
        let outputWithSpecialChars = """
        \u{001B}[31mError:\u{001B}[0m Test failed
        Line with tabs\tand escapes\n
        Unicode: 🚀 📁 💻
        """
        
        let result = CommandResult(
            command: "test_special_chars",
            output: outputWithSpecialChars,
            exitCode: 0,
            duration: 0.1
        )
        
        let response = try await handler.handleCommandResult(result)
        
        // Verify special characters are preserved
        let state = await handler.getState()
        XCTAssertTrue(state.context.last?.contains("🚀") ?? false)
        XCTAssertTrue(state.context.last?.contains("Error:") ?? false)
    }
    
    func testStreamProcessingMultipleChunks() async throws {
        let handler = MockAutoModeHandler(model: testModel)
        
        // Test handling multiple chunks of output
        for i in 1...5 {
            let result = CommandResult(
                command: "chunk_\(i)",
                output: "Output chunk \(i)",
                exitCode: 0,
                duration: 0.1
            )
            
            let response = try await handler.handleCommandResult(result)
            XCTAssertNotNil(response.context)
        }
        
        // Verify all chunks were processed
        let state = await handler.getState()
        XCTAssertEqual(state.context.count, 10) // 5 commands + 5 outputs
        
        // Verify order is maintained
        for i in 1...5 {
            XCTAssertTrue(state.context.contains { $0.contains("chunk_\(i)") })
            XCTAssertTrue(state.context.contains { $0.contains("Output chunk \(i)") })
        }
    }
    
    func testStreamProcessingConcurrentOutput() async throws {
        let handler = MockAutoModeHandler(model: testModel)
        
        // Process multiple outputs concurrently
        async let result1 = handler.handleCommandResult(CommandResult(
            command: "cmd1",
            output: "Output 1",
            exitCode: 0,
            duration: 0.1
        ))
        
        async let result2 = handler.handleCommandResult(CommandResult(
            command: "cmd2",
            output: "Output 2",
            exitCode: 0,
            duration: 0.1
        ))
        
        // Wait for both to complete
        let responses = try await [result1, result2]
        XCTAssertEqual(responses.count, 2)
        
        // Verify both outputs were processed
        let state = await handler.getState()
        XCTAssertEqual(state.context.count, 4) // 2 commands + 2 outputs
        XCTAssertTrue(state.context.contains { $0.contains("cmd1") })
        XCTAssertTrue(state.context.contains { $0.contains("Output 1") })
        XCTAssertTrue(state.context.contains { $0.contains("cmd2") })
        XCTAssertTrue(state.context.contains { $0.contains("Output 2") })
    }
    
    // MARK: - Helper Methods
    
    private func createTestAction(_ command: String, type: AIActionType = .executeCommand) -> AIAction {
        AIAction(
            type: type,
            content: command,
            requiresConfirmation: false
        )
    }
}

// MARK: - Mock Implementations for Testing

/// Mock implementation of AutoModeHandler for testing
actor MockAutoModeHandler: AIModeHandler {
    private var _state: AIModeState
    public let model: AIModel
    
    // Test configuration
    var mockSuggestions: [CommandSuggestion] = []
    var mockAnalysis: String = "Analysis of command result"
    var mockDelay: TimeInterval = 0.0
    var mockTimeout: TimeInterval = 30.0
    
    // Support for dynamic suggestion generation based on input
    var mockSuggestionsProvider: ((String) throws -> [CommandSuggestion])? = nil
    // Support for dynamic analysis based on result
    var mockAnalysisProvider: ((CommandResult) -> String)? = nil
    
    public init(model: AIModel) {
        self.model = model
        self._state = AIModeState()
    }
    
    public func getState() async -> AIModeState {
        return _state
    }
    
    public func processInput(_ input: String) async throws -> AIModeResponse {
        // Store input in context
        _state.context.append(input)
        
        // Simulate network delay if specified
        if mockDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(mockDelay * 1_000_000_000))
        }
        
        // Check if timeout should be simulated
        if mockTimeout < mockDelay {
            throw NSError(domain: "AIIntegration", code: NSURLErrorTimedOut, userInfo: nil)
        }
        
        // Use provider if available
        let suggestions = try mockSuggestionsProvider?(input) ?? mockSuggestions
        
        return AIModeResponse(suggestions: suggestions)
    }
    
    public func handleCommandResult(_ result: CommandResult) async throws -> AIModeResponse {
        // Store command and result in context
        _state.context.append("$ \(result.command)")
        
        // Truncate output if it's very long
        let truncatedOutput = result.output.count > 1000
            ? String(result.output.prefix(1000)) + "... (output truncated)"
            : result.output
        _state.context.append(truncatedOutput)
        
        // Use provider if available
        let analysis = mockAnalysisProvider?(result) ?? mockAnalysis
        
        return AIModeResponse(context: analysis)
    }
    
    public func reset() async {
        _state = AIModeState()
    }
}

/// Mock implementation of DispatchModeHandler for testing
actor MockDispatchModeHandler: AIModeHandler {
    private var _state: AIModeState
    public let model: AIModel
    
    // Test configuration
    var mockActions: [AIAction] = []
    var mockRecoveryActions: [AIAction] = []
    var mockCompletionSummary: String = "Task completed successfully."
    var mockRecoveryThrows: Bool = false
    
    // Support for dynamic generation
    var mockActionsProvider: ((String) throws -> [AIAction])? = nil
    var mockCompletionProvider: (() -> String)? = nil
    
    // Task tracking
    private var taskPlan: [AIAction] = []
    private var currentStep: Int = 0
    private var taskContext: [String] = []
    
    public init(model: AIModel) {
        self.model = model
        self._state = AIModeState()
    }
    
    public func getState() async -> AIModeState {
        return _state
    }
    
    public func processInput(_ input: String) async throws -> AIModeResponse {
        // Reset task context
        taskContext = ["Original task: \(input)"]
        
        // Get actions from provider or use mock actions
        let actions = try mockActionsProvider?(input) ?? mockActions
        
        // Update state
        taskPlan = actions
        currentStep = 0
        _state.pendingActions = actions
        
        return AIModeResponse(
            actions: [actions.first].compactMap { $0 },
            context: "Task planned with \(actions.count) steps"
        )
    }
    
    public func handleCommandResult(_ result: CommandResult) async throws -> AIModeResponse {
        // Record result
        taskContext.append("Step \(currentStep + 1) result: \(result.command)")
        
        // Handle failure
        if result.exitCode != 0 {
            if mockRecoveryThrows {
                throw NSError(domain: "AIIntegration", code: 500,
                            userInfo: [NSLocalizedDescriptionKey: "Simulated recovery error"])
            }
            
            if mockRecoveryActions.isEmpty {
                await reset()
                return AIModeResponse(context: "Task failed: Unable to recover")
            }
            
            taskPlan = mockRecoveryActions
            currentStep = 0
            _state.pendingActions = mockRecoveryActions
            return AIModeResponse(
                actions: [mockRecoveryActions[0]],
                context: "Recovery plan created"
            )
        }
        
        // Move to next step
        currentStep += 1
        
        // Check for completion
        if currentStep >= taskPlan.count {
            let summary = mockCompletionProvider?() ?? mockCompletionSummary
            await reset()
            return AIModeResponse(context: summary)
        }
        
        // Continue with next step
        return AIModeResponse(
            actions: [taskPlan[currentStep]],
            context: "Proceeding with step \(currentStep + 1)"
        )
    }
    
    public func reset() async {
        _state = AIModeState()
        taskPlan = []
        currentStep = 0
        taskContext = []
    }
}

// MARK: - Testing Utilities

extension AIAction {
    /// Creates a test action with default values
    static func testAction(
        command: String,
        type: AIActionType = .executeCommand,
        requiresConfirmation: Bool = false,
        metadata: [String: String] = [:]
    ) -> AIAction {
        AIAction(
            type: type,
            content: command,
            requiresConfirmation: requiresConfirmation,
            metadata: metadata
        )
    }
}

extension CommandResult {
    /// Creates a test result with default values
    static func testResult(
        command: String,
        output: String = "",
        exitCode: Int = 0,
        duration: TimeInterval = 0.1
    ) -> CommandResult {
        CommandResult(
            command: command,
            output: output,
            exitCode: exitCode,
            duration: duration
        )
    }
    
    /// Creates a test result indicating success
    static func success(command: String, output: String = "Success") -> CommandResult {
        testResult(command: command, output: output, exitCode: 0)
    }
    
    /// Creates a test result indicating failure
    static func failure(command: String, output: String = "Error", exitCode: Int = 1) -> CommandResult {
        testResult(command: command, output: output, exitCode: exitCode)
    }
}

extension CommandSuggestion {
    /// Creates a test suggestion with default values
    static func testSuggestion(
        command: String,
        explanation: String = "Test explanation",
        safetyLevel: CommandSafetyLevel = .safe,
        requiresConfirmation: Bool = false
    ) -> CommandSuggestion {
        CommandSuggestion(
            command: command,
            explanation: explanation,
            safetyLevel: safetyLevel,
            requiresConfirmation: requiresConfirmation
        )
    }
}
