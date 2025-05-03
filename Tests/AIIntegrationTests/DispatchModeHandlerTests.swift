import XCTest
@testable import AIIntegration

/// Tests for the enhanced DispatchModeHandler
class DispatchModeHandlerTests: XCTestCase {
    
    // MARK: - Mock Services
    
    /// Mock implementation of ChatCompletionService for testing
    class MockChatCompletionService: ChatCompletionServiceProtocol {
        // Captured parameters for inspection
        var lastModel: AIModel?
        var lastMessages: [ChatMessage]?
        var lastTemperature: Double?
        var lastStreamSetting: Bool?
        
        // Configurable responses
        var chatCompletionResponse: AsyncStream<ChatMessageChunk>?
        var error: Error?
        
        func generateChatCompletion(
            model: AIModel,
            messages: [ChatMessage],
            temperature: Double = 0.7,
            stream: Bool = true
        ) async throws -> AsyncStream<ChatMessageChunk> {
            // Capture the parameters
            self.lastModel = model
            self.lastMessages = messages
            self.lastTemperature = temperature
            self.lastStreamSetting = stream
            
            // Return configured error or response
            if let error = error {
                throw error
            }
            
            return chatCompletionResponse ?? AsyncStream { continuation in
                continuation.yield(ChatMessageChunk(content: "Mock response"))
                continuation.finish()
            }
        }
    }
    
    /// Mock implementation of CommandParsingService for testing
    class MockCommandParsingService: CommandParsingServiceProtocol {
        var preprocessResponseResult = ""
        var parseSuggestionsResult: [CommandSuggestion] = []
        var parseActionsResult: [AIAction] = []
        var requiresConfirmationResult = false
        
        func preprocessResponse(_ response: String) async -> String {
            return preprocessResponseResult
        }
        
        func parseSuggestions(from response: String) async throws -> [CommandSuggestion] {
            return parseSuggestionsResult
        }
        
        func parseActions(from response: String) async throws -> [AIAction] {
            return parseActionsResult
        }
        
        func requiresConfirmation(_ command: String) async -> Bool {
            return requiresConfirmationResult
        }
    }
    
    /// Mock implementation of CommandService for testing
    class MockCommandService: CommandService {
        var executeCommandResult: CommandResult?
        var error: Error?
        
        override func executeCommand(_ command: String) async throws -> CommandResult {
            if let error = error {
                throw error
            }
            
            return executeCommandResult ?? CommandResult(
                command: command,
                output: "Mock output",
                exitCode: 0,
                duration: 0.1
            )
        }
    }
    
    // MARK: - Test Data
    
    /// Creates sample AI model for testing
    private func createSampleModel() -> AIModel {
        return AIModel(
            id: "test-model",
            name: "test-model",
            size: 1000,
            modified: Date(),
            capabilities: ModelCapabilities(
                isCodeCapable: true,
                isMultimodal: false,
                isCommandOptimized: true
            )
        )
    }
    
    /// Creates a successful command result
    private func createSuccessResult(command: String, output: String = "Success") -> CommandResult {
        return CommandResult(
            command: command,
            output: output,
            exitCode: 0,
            duration: 0.1
        )
    }
    
    /// Creates a failed command result
    private func createFailedResult(command: String, output: String = "Command failed", exitCode: Int = 1) -> CommandResult {
        return CommandResult(
            command: command,
            output: output,
            exitCode: exitCode,
            duration: 0.1
        )
    }
    
    // MARK: - Test AI Task Planning
    
    func testTaskPlanningWithAI() async throws {
        // Create mocks
        let mockCompletionService = MockChatCompletionService()
        let mockParsingService = MockCommandParsingService()
        let mockCommandService = MockCommandService()
        
        // Configure mock completion response with a structured plan
        let planResponse = """
        PLAN:
        - Step 1: ls -la
          - Explanation: List all files in current directory
          - Safety Level: safe
          - Requires Confirmation: false
        
        - Step 2: mkdir -p test/folder
          - Explanation: Create test directory structure
          - Safety Level: safe
          - Requires Confirmation: false
        END OF PLAN
        """
        
        mockCompletionService.chatCompletionResponse = AsyncStream { continuation in
            continuation.yield(ChatMessageChunk(content: planResponse))
            continuation.finish()
        }
        
        // Create the handler with mocks
        let handler = DispatchModeHandler(
            model: "test-model",
            commandService: mockCommandService,
            parsingService: mockParsingService,
            completionService: mockCompletionService,
            aiModel: createSampleModel()
        )
        
        // Test the planning functionality
        let response = try await handler.processInput("List files and create a test directory")
        
        // Verify that the completion service was called with appropriate messages
        XCTAssertNotNil(mockCompletionService.lastMessages)
        XCTAssertEqual(mockCompletionService.lastMessages?.count, 2)
        XCTAssertEqual(mockCompletionService.lastMessages?[0].role, .system)
        XCTAssertEqual(mockCompletionService.lastMessages?[1].role, .user)
        XCTAssertEqual(mockCompletionService.lastMessages?[1].content, "Task: List files and create a test directory")
        
        // Verify the response contains actions
        XCTAssertFalse(response.actions.isEmpty)
        
        // Verify first action is the first step from the plan
        if let firstAction = response.actions.first {
            XCTAssertEqual(firstAction.type, .executeCommand)
            XCTAssertEqual(firstAction.content, "ls -la")
            XCTAssertFalse(firstAction.requiresConfirmation)
            XCTAssertEqual(firstAction.metadata["safetyLevel"], "safe")
        } else {
            XCTFail("No actions were returned")
        }
    }
    
    func testTaskPlanningWithoutStructuredResponse() async throws {
        // Create mocks
        let mockCompletionService = MockChatCompletionService()
        let mockParsingService = MockCommandParsingService()
        let mockCommandService = MockCommandService()
        
        // Configure mock completion response with an unstructured response
        let unstructuredResponse = """
        You can accomplish this with the following commands:
        
        ```bash
        ls -la
        mkdir -p test/folder
        ```
        
        This will list all files and create the test directory structure.
        """
        
        mockCompletionService.chatCompletionResponse = AsyncStream { continuation in
            continuation.yield(ChatMessageChunk(content: unstructuredResponse))
            continuation.finish()
        }
        
        // Create the handler with mocks
        let handler = DispatchModeHandler(
            model: "test-model",
            commandService: mockCommandService,
            parsingService: mockParsingService,
            completionService: mockCompletionService,
            aiModel: createSampleModel()
        )
        
        // Test the planning functionality
        let response = try await handler.processInput("List files and create a test directory")
        
        // Verify the response contains actions extracted from unstructured text
        XCTAssertFalse(response.actions.isEmpty)
    }
    
    func testTaskPlanningWithAIError() async throws {
        // Create mocks
        let mockCompletionService = MockChatCompletionService()
        let mockParsingService = MockCommandParsingService()
        let mockCommandService = MockCommandService()
        
        // Configure mock completion service to throw an error
        mockCompletionService.error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        
        // Create the handler with mocks
        let handler = DispatchModeHandler(
            model: "test-model",
            commandService: mockCommandService,
            parsingService: mockParsingService,
            completionService: mockCompletionService,
            aiModel: createSampleModel()
        )
        
        // Test the planning functionality with error
        do {
            _ = try await handler.processInput("List files and create a test directory")
            XCTFail("Expected error was not thrown")
        } catch {
            // Expected error
            XCTAssertNotNil(error)
        }
    }
    
    // MARK: - Test Recovery Planning
    
    func testRecoveryPlanningForFailedCommand() async throws {
        // Create mocks
        let mockCompletionService = MockChatCompletionService()
        let mockParsingService = MockCommandParsingService()
        let mockCommandService = MockCommandService()
        
        // Configure mock completion response with a recovery plan
        let recoveryPlanResponse = """
        RECOVERY PLAN:
        - Issue Analysis: Command not found error suggests the tool is not installed
        
        - Step 1: apt-get update
          - Purpose: Update package index
          - Safety Level: safe
          - Requires Confirmation: false
        
        - Step 2: apt-get install missing-tool
          - Purpose: Install the missing tool
          - Safety Level: moderate
          - Requires Confirmation: true
        
        - Final Step: missing-tool --version
          - Purpose: Verify installation succeeded
          - Safety Level: safe
          - Requires Confirmation: false
        
        END OF PLAN
        """
        
        mockCompletionService.chatCompletionResponse = AsyncStream { continuation in
            continuation.yield(ChatMessageChunk(content: recoveryPlanResponse))
            continuation.finish()
        }
        
        // Create the handler with mocks
        let handler = DispatchModeHandler(
            model: "test-model",
            commandService: mockCommandService,
            parsingService: mockParsingService,
            completionService: mockCompletionService,
            aiModel: createSampleModel()
        )
        
        // First, set up initial state with a task plan
        _ = try await handler.processInput("Run missing-tool")
        
        // Configure a failed command result
        let failedResult = createFailedResult(
            command: "missing-tool",
            output: "bash: missing-tool: command not found",
            exitCode: 127
        )
        
        // Test the recovery planning
        let response = try await handler.handleCommandResult(failedResult)
        
        // Verify the recovery plan was created
        XCTAssertFalse(response.actions.isEmpty)
        XCTAssertEqual(response.context, "Recovery plan created")
        
        // Verify first action is correctly parsed from recovery plan
        if let firstAction = response.actions.first {
            XCTAssertEqual(firstAction.type, .executeCommand)
            // The first action should be to echo the analysis
            XCTAssertTrue(firstAction.content.starts(with: "echo"))
            XCTAssertFalse(firstAction.requiresConfirmation)
        } else {
            XCTFail("No recovery actions were returned")
        }
    }
    
    func testRecoveryPlanningWithoutStructuredResponse() async throws {
        // Create mocks
        let mockCompletionService = MockChatCompletionService()
        let mockParsingService = MockCommandParsingService()
        let mockCommandService = MockCommandService()
        
        // Configure mock completion response with an unstructured response
        let unstructuredResponse = """
        It looks like the command is not found. Try installing it with:
        
        ```
        sudo apt-get update
        sudo apt-get install missing-tool
        ```
        
        Then try running it again.
        """
        
        mockCompletionService.chatCompletionResponse = AsyncStream { continuation in
            continuation.yield(ChatMessageChunk(content: unstructuredResponse))
            continuation.finish()
        }
        
        // Create the handler with mocks
        let handler = DispatchModeHandler(
            model: "test-model",
            commandService: mockCommandService,
            parsingService: mockParsingService,
            completionService: mockCompletionService,
            aiModel: createSampleModel()
        )
        
        // First, set up initial state with a task plan
        _ = try await handler.processInput("Run missing-tool")
        
        // Configure a failed command result
        let failedResult = createFailedResult(
            command: "missing-tool",
            output: "bash: missing-tool: command not found",
            exitCode: 127
        )
        
        // Test the recovery planning
        let response = try await handler.handleCommandResult(failedResult)
        
        // Verify the recovery plan was created
        XCTAssertFalse(response.actions.isEmpty)
    }
    
    func testRecoveryPlanningWithoutAIModel() async throws {
        // Create mocks
        let mockCompletionService = MockChatCompletionService()
        let mockParsingService = MockCommandParsingService()
        let mockCommandService = MockCommandService()
        
        // Create the handler with mocks but no AI model
        let handler = DispatchModeHandler(
            model: "test-model",
            commandService: mockCommandService,
            parsingService: mockParsingService,
            completionService: mockCompletionService
        )
        
        // First, set up initial state with a task plan
        _ = try await handler.processInput("Run missing-tool")
        
        // Configure a failed command result
        let failedResult = createFailedResult(
            command: "missing-tool",
            output: "bash: missing-tool: command not found",
            exitCode: 127
        )
        
        // Test the recovery planning
        let response = try await handler.handleCommandResult(failedResult)
        
        // Verify a fallback recovery action was created
        XCTAssertFalse(response.actions.isEmpty)
        
        // Verify the fallback action is an echo of the error
        if let action = response.actions.first {
            XCTAssertEqual(action.type, .executeCommand)
            XCTAssertTrue(action.content.contains("Error recovery"))
            XCTAssertFalse(action.requiresConfirmation)
        } else {
            XCTFail("No fallback action was returned")
        }
    }
    
    // MARK: - Test Completion Summary
    
    func testCompletionSummaryGeneration() async throws {
        // Create mocks
        let mockCompletionService = MockChatCompletionService()
        let mockParsingService = MockCommandParsingService()
        let mockCommandService = MockCommandService()
        
        // Configure mock completion response with a summary
        let summaryResponse = """
        ✅ Successfully listed files and created directory structure. Created directory tree with 3 nested folders and checked permissions.
        """
        
        mockCompletionService.chatCompletionResponse = AsyncStream { continuation in
            continuation.yield(ChatMessageChunk(content: summaryResponse))
            continuation.finish()
        }
        
        // Create the handler with mocks
        let handler = DispatchModeHandler(
            model: "test-model",
            commandService: mockCommandService,
            parsingService: mockParsingService,
            completionService: mockCompletionService,
            aiModel: createSampleModel()
        )
        
        // First, set up initial state with a task plan and execute it
        _ = try await handler.processInput("List files and create test directory")
        
        // Create a series of successful results to simulate task completion
        let result1 = createSuccessResult(
            command: "ls -la",
            output: "total 24\ndrwxr-xr-x  3 user group  96 Apr 24 10:00 .\ndrwxr-xr-x  5 user group 160 Apr 24 10:00 .."
        )
        _ = try await handler.handleCommandResult(result1)
        
        let result2 = createSuccessResult(
            command: "mkdir -p test/folder",
            output: ""
        )
        
        // This should complete the task and return a summary
        let response = try await handler.handleCommandResult(result2)
        
        // Verify that a completion summary was generated
        XCTAssertNil(response.actions.first, "Should be no actions after task completion")
        XCTAssertNotNil(response.context, "Should have a context with the summary")
        XCTAssertEqual(response.context, summaryResponse, "Summary should match the AI response")
    }
    
    func testCompletionSummaryWithFormattingApplied() async throws {
        // Create mocks
        let mockCompletionService = MockChatCompletionService()
        let mockParsingService = MockCommandParsingService()
        let mockCommandService = MockCommandService()
        
        // Configure mock completion response with a long summary that needs formatting
        let longSummaryResponse = """
        Task execution completed with the following results: 
        1. The system performed a full directory listing showing all files including hidden ones.
        2. Created a new directory structure with the `mkdir -p test/folder` command which ensures parent directories are created if they don't exist.
        3. All operations completed successfully with no errors or warnings.
        
        This complex task was executed within 0.2 seconds and created 3 directory levels. The terminal permissions look good and all operations were performed with standard user privileges.
        """
        
        mockCompletionService.chatCompletionResponse = AsyncStream { continuation in
            continuation.yield(ChatMessageChunk(content: longSummaryResponse))
            continuation.finish()
        }
        
        // Create the handler with mocks
        let handler = DispatchModeHandler(
            model: "test-model",
            commandService: mockCommandService,
            parsingService: mockParsingService,
            completionService: mockCompletionService,
            aiModel: createSampleModel()
        )
        
        // First, set up initial state with a task plan and execute it
        _ = try await handler.processInput("List files and create test directory")
        
        // Create successful results to simulate task completion
        let result = createSuccessResult(command: "ls -la && mkdir -p test/folder")
        
        // This should complete the task and return a summary
        let response = try await handler.handleCommandResult(result)
        
        // Verify that a completion summary was generated and formatted
        XCTAssertNil(response.actions.first, "Should be no actions after task completion")
        XCTAssertNotNil(response.context, "Should have a context with the summary")
        
        // Verify that emoji was added if not present in original summary
        XCTAssertTrue(
            response.context?.contains("✅") == true ||
            response.context?.contains("⚠️") == true ||
            response.context?.contains("🔍") == true,
            "Summary should include status emoji"
        )
        
        // Verify that long lines were reasonably wrapped
        let lines = response.context?.split(separator: "\n") ?? []
        for line in lines {
            XCTAssertLessThanOrEqual(line.count, 90, "Lines should be reasonably wrapped")
        }
    }
    
    func testCompletionSummaryWithoutAIModel() async throws {
        // Create mocks
        let mockCompletionService = MockChatCompletionService()
        let mockParsingService = MockCommandParsingService()
        let mockCommandService = MockCommandService()
        
        // Create the handler with mocks but no AI model
        let handler = DispatchModeHandler(
            model: "test-model",
            commandService: mockCommandService,
            parsingService: mockParsingService,
            completionService: mockCompletionService
        )
        
        // First, set up initial state with a task plan and execute it
        _ = try await handler.processInput("List files and create test directory")
        
        // Create successful results to simulate task completion
        let result = createSuccessResult(command: "ls -la && mkdir -p test/folder")
        
        // This should complete the task and return a fallback summary
        let response = try await handler.handleCommandResult(result)
        
        // Verify that a basic fallback summary was generated
        XCTAssertNil(response.actions.first, "Should be no actions after task completion")
        XCTAssertNotNil(response.context, "Should have a context with the summary")
        XCTAssertTrue(response.context?.contains("Task completed successfully") == true, 
                      "Fallback summary should indicate success")
    }
    
    // MARK: - Test Safety Checks
    
    func testSafetyChecksForDestructiveCommands() async throws {
        // Create mocks
        let mockCompletionService = MockChatCompletionService()
        let mockParsingService = MockCommandParsingService()
        let mockCommandService = MockCommandService()
        
        // Configure mock completion response with a plan containing destructive commands
        let planWithDestructiveCommands = """
        PLAN:
        - Step 1: ls -la
          - Explanation: List all files in current directory
          - Safety Level: safe
          - Requires Confirmation: false
        
        - Step 2: rm -rf old_folder
          - Explanation: Delete the old folder recursively
          - Safety Level: destructive
          - Requires Confirmation: false
        
        - Step 3: mkdir -p new_folder
          - Explanation: Create new directory structure
          - Safety Level: safe
          - Requires Confirmation: false
        END OF PLAN
        """
        
        mockCompletionService.chatCompletionResponse = AsyncStream { continuation in
            continuation.yield(ChatMessageChunk(content: planWithDestructiveCommands))
            continuation.finish()
        }
        
        // Create the handler with mocks
        let handler = DispatchModeHandler(
            model: "test-model",
            commandService: mockCommandService,
            parsingService: mockParsingService,
            completionService: mockCompletionService,
            aiModel: createSampleModel()
        )
        
        // Test the planning functionality
        let response = try await handler.processInput("List files, delete old folder, create new folder")
        
        // Verify the response contains actions
        XCTAssertFalse(response.actions.isEmpty)
        
        // Process first action (safe command)
        let result1 = createSuccessResult(command: "ls -la")
        let nextResponse = try await handler.handleCommandResult(result1)
        
        // Verify second action (destructive command) requires confirmation
        if let destructiveAction = nextResponse.actions.first {
            XCTAssertEqual(destructiveAction.type, .executeCommand)
            XCTAssertEqual(destructiveAction.content, "rm -rf old_folder")
            XCTAssertTrue(destructiveAction.requiresConfirmation, 
                         "Destructive command should require confirmation")
            XCTAssertEqual(destructiveAction.metadata["safetyLevel"], "destructive",
                         "Safety level should be properly set")
        } else {
            XCTFail("No actions were returned")
        }
    }
    
    func testSafetyLevelOverrides() async throws {
        // Create mocks
        let mockCompletionService = MockChatCompletionService()
        let mockParsingService = MockCommandParsingService()
        let mockCommandService = MockCommandService()
        
        // Configure mock completion response with a plan containing a safe command marked as destructive
        let planWithOverride = """
        PLAN:
        - Step 1: echo "Hello World"
          - Explanation: Simple echo command
          - Safety Level: destructive
          - Requires Confirmation: true
        END OF PLAN
        """
        
        mockCompletionService.chatCompletionResponse = AsyncStream { continuation in
            continuation.yield(ChatMessageChunk(content: planWithOverride))
            continuation.finish()
        }
        
        // Create the handler with mocks
        let handler = DispatchModeHandler(
            model: "test-model",
            commandService: mockCommandService,
            parsingService: mockParsingService,
            completionService: mockCompletionService,
            aiModel: createSampleModel()
        )
        
        // Test the planning functionality
        let response = try await handler.processInput("Echo hello world")
        
        // Verify the first action respects the safety level override
        if let action = response.actions.first {
            XCTAssertEqual(action.type, .executeCommand)
            XCTAssertEqual(action.content, "echo \"Hello World\"")
            XCTAssertTrue(action.requiresConfirmation, 
                         "Should respect the requires confirmation flag")
            XCTAssertEqual(action.metadata["safetyLevel"], "destructive",
                         "Should respect the safety level override")
        } else {
            XCTFail("No actions were returned")
        }
    }
    
    // MARK: - Test Edge Cases and Error Handling
    
    func testEmptyInputHandling() async throws {
        // Create mocks
        let mockCompletionService = MockChatCompletionService()
        let mockParsingService = MockCommandParsingService()
        let mockCommandService = MockCommandService()
        
        // Configure a minimal response for empty input
        mockCompletionService.chatCompletionResponse = AsyncStream { continuation in
            continuation.yield(ChatMessageChunk(content: "No valid task specified."))
            continuation.finish()
        }
        
        // Create the handler with mocks
        let handler = DispatchModeHandler(
            model: "test-model",
            commandService: mockCommandService,
            parsingService: mockParsingService,
            completionService: mockCompletionService,
            aiModel: createSampleModel()
        )
        
        // Test with empty input
        let response = try await handler.processInput("")
        
        // Empty input should still provide a context response but no actions
        XCTAssertTrue(response.actions.isEmpty, "Empty input should not generate actions")
        XCTAssertNotNil(response.context, "Should have a context response for empty input")
    }
    
    func testHandlingOfMalformedAIResponse() async throws {
        // Create mocks
        let mockCompletionService = MockChatCompletionService()
        let mockParsingService = MockCommandParsingService()
        let mockCommandService = MockCommandService()
        
        // Configure a malformed response that doesn't follow the expected format
        mockCompletionService.chatCompletionResponse = AsyncStream { continuation in
            continuation.yield(ChatMessageChunk(content: """
            I think what you want to do is:
            
            First, check the files
            Then create a directory
            Finally, move some files
            
            But I'm not formatting this as requested, sorry!
            """))
            continuation.finish()
        }
        
        // Create the handler with mocks
        let handler = DispatchModeHandler(
            model: "test-model",
            commandService: mockCommandService,
            parsingService: mockParsingService,
            completionService: mockCompletionService,
            aiModel: createSampleModel()
        )
        
        // Test with input that generates malformed response
        let response = try await handler.processInput("List files and create directory")
        
        // Should attempt to extract commands even from malformed response
        XCTAssertNotNil(response.context, "Should have a context response")
    }
    
    func testStateResetOnCompletion() async throws {
        // Create mocks
        let mockCompletionService = MockChatCompletionService()
        let mockParsingService = MockCommandParsingService()
        let mockCommandService = MockCommandService()
        
        // Configure mock completion response with a multi-step plan
        let multiStepPlan = """
        PLAN:
        - Step 1: ls -la
          - Explanation: List all files in current directory
          - Safety Level: safe
          - Requires Confirmation: false
        
        - Step 2: mkdir -p test/folder
          - Explanation: Create test directory structure
          - Safety Level: safe
          - Requires Confirmation: false
        
        - Step 3: echo "Task completed" > test/folder/status.txt
          - Explanation: Create status file
          - Safety Level: safe
          - Requires Confirmation: false
        END OF PLAN
        """
        
        mockCompletionService.chatCompletionResponse = AsyncStream { continuation in
            continuation.yield(ChatMessageChunk(content: multiStepPlan))
            continuation.finish()
        }
        
        // Configure summary response for when task completes
        let summaryResponse = "✅ Task completed successfully with 3 steps."
        
        // Create the handler with mocks
        let handler = DispatchModeHandler(
            model: "test-model",
            commandService: mockCommandService,
            parsingService: mockParsingService,
            completionService: mockCompletionService,
            aiModel: createSampleModel()
        )
        
        // Step 1: Set up initial task
        let initialResponse = try await handler.processInput("Set up a test directory with status file")
        
        // Verify task plan contains multiple steps
        XCTAssertFalse(initialResponse.actions.isEmpty, "Should have actions in the plan")
        XCTAssertTrue(initialResponse.context?.contains("with") == true, "Context should mention steps")
        
        // Step 2: Execute first command in the plan
        let result1 = createSuccessResult(command: "ls -la")
        let secondResponse = try await handler.handleCommandResult(result1)
        
        // Verify we're proceeding to next step
        XCTAssertEqual(secondResponse.context, "Proceeding with step 2 of 3")
        
        // Step 3: Execute second command in the plan
        let result2 = createSuccessResult(command: "mkdir -p test/folder")
        let thirdResponse = try await handler.handleCommandResult(result2)
        
        // Verify we're proceeding to the final step
        XCTAssertEqual(thirdResponse.context, "Proceeding with step 3 of 3")
        
        // Configure the completion service to return the summary now
        mockCompletionService.chatCompletionResponse = AsyncStream { continuation in
            continuation.yield(ChatMessageChunk(content: summaryResponse))
            continuation.finish()
        }
        
        // Step 4: Execute final command to complete the task
        let result3 = createSuccessResult(command: "echo \"Task completed\" > test/folder/status.txt")
        let completionResponse = try await handler.handleCommandResult(result3)
        
        // Verify the task is completed with a summary
        XCTAssertNil(completionResponse.actions.first, "No actions should remain after completion")
        XCTAssertEqual(completionResponse.context, summaryResponse, "Summary should be provided")
        
        // Step 5: Test that state is reset by starting a new task
        
        // Configure mock with a new plan for the second task
        let secondTaskPlan = """
        PLAN:
        - Step 1: cat test/folder/status.txt
          - Explanation: Check status file
          - Safety Level: safe
          - Requires Confirmation: false
        END OF PLAN
        """
        
        mockCompletionService.chatCompletionResponse = AsyncStream { continuation in
            continuation.yield(ChatMessageChunk(content: secondTaskPlan))
            continuation.finish()
        }
        
        // Start a new task
        let newTaskResponse = try await handler.processInput("Check the status file")
        
        // Verify the handler started a fresh task plan
        XCTAssertFalse(newTaskResponse.actions.isEmpty, "New task should have actions")
        XCTAssertTrue(newTaskResponse.context?.contains("with") == true, "Context should reference new plan")
        
        if let firstAction = newTaskResponse.actions.first {
            XCTAssertEqual(firstAction.content, "cat test/folder/status.txt", 
                         "First action should be from the new task")
        } else {
            XCTFail("No actions were returned for the new task")
        }
        
        // Check handler state is fresh (we can't directly access private state, but we can infer from behavior)
        let state = await handler.getState()
        XCTAssertTrue(state.pendingActions.count <= 1, "Only current step should be pending")
    }
}
