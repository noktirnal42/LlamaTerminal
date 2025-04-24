import XCTest
@testable import AIIntegration

/// Tests for the AutoModeHandler
class AutoModeHandlerTests: XCTestCase {
    
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
    
    /// Mock implementation of CommandPatternDetector
    class MockCommandPatternDetector: CommandPatternDetector {
        var detectedPattern: CommandPatternType?
        
        override func detectPattern(in command: String) -> CommandPatternType? {
            return detectedPattern
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
    
    // MARK: - Test Context Tracking
    
    func testContextTracking() async throws {
        // Create mocks with subclass that exposes internal state for testing
        class TestableAutoModeHandler: AutoModeHandler {
            var contextHistoryCount: Int {
                return contextHistory.count
            }
            
            var stateContextCount: Int {
                return state.context.count
            }
        }
        
        let handler = TestableAutoModeHandler(model: "test-model")
        
        // Verify initial state
        XCTAssertEqual(handler.contextHistoryCount, 0, "Context history should start empty")
        XCTAssertEqual(handler.stateContextCount, 0, "State context should start empty")
        
        // Process inputs to build context
        _ = try await handler.processInput("ls -la")
        XCTAssertEqual(handler.contextHistoryCount, 1, "Context should have one entry")
        
        _ = try await handler.handleCommandResult(createSuccessResult(command: "ls -la", output: "file1 file2"))
        XCTAssertEqual(handler.contextHistoryCount, 2, "Context should have two entries")
        
        // Add multiple entries and check if context is properly limited
        for i in 1...60 {
            _ = try await handler.processInput("command \(i)")
        }
        
        // Context should be limited to maxContextSize (50)
        XCTAssertEqual(handler.contextHistoryCount, 50, "Context should be limited to maxContextSize")
        XCTAssertEqual(handler.stateContextCount, 50, "State context should be limited to maxContextSize")
        
        // Reset should clear context
        await handler.reset()
        XCTAssertEqual(handler.contextHistoryCount, 0, "Context should be cleared after reset")
        XCTAssertEqual(handler.stateContextCount, 0, "State context should be cleared after reset")
    }
    
    // MARK: - Test Proactive Suggestion Generation
    
    func testProactiveSuggestionGeneration() async throws {
        // Create mocks
        let mockCompletionService = MockChatCompletionService()
        let mockParsingService = MockCommandParsingService()
        
        // Configure mock to test proactive suggestions
        let proactiveSuggestionResponse = """
        SUGGESTIONS:
        - Suggestion: alias ll='ls -la'
          Explanation: Create a shortcut for listing files with details
          Safety: safe
        
        - Suggestion: history | grep "git commit"
          Explanation: Find your previous git commits
          Safety: safe
        END SUGGESTIONS
        """
        
        mockCompletionService.chatCompletionResponse = AsyncStream { continuation in
            continuation.yield(ChatMessageChunk(content: proactiveSuggestionResponse))
            continuation.finish()
        }
        
        // Configure parsing service to return suggestions
        mockParsingService.parseSuggestionsResult = [
            CommandSuggestion(
                command: "alias ll='ls -la'",
                explanation: "Create a shortcut for listing files with details",
                safetyLevel: .safe
            ),
            CommandSuggestion(
                command: "history | grep \"git commit\"",
                explanation: "Find your previous git commits",
                safetyLevel: .safe
            )
        ]
        
        // Create handler with ability to expose shouldGenerateProactiveSuggestion
        class TestableAutoModeHandler: AutoModeHandler {
            var shouldGenerateProactiveSuggestionOverride: Bool?
            
            override func shouldGenerateProactiveSuggestion() -> Bool {
                return shouldGenerateProactiveSuggestionOverride ?? super.shouldGenerateProactiveSuggestion()
            }
        }
        
        let handler = TestableAutoModeHandler(
            model: "test-model",
            parsingService: mockParsingService,
            completionService: mockCompletionService,
            aiModel: createSampleModel()
        )
        
        // Force proactive suggestion generation to true
        handler.shouldGenerateProactiveSuggestionOverride = true
        
        // Build some context first
        _ = try await handler.processInput("ls -la")
        _ = try await handler.handleCommandResult(createSuccessResult(command: "ls -la"))
        _ = try await handler.processInput("cd Documents")
        
        // This should trigger proactive suggestion
        let response = try await handler.handleCommandResult(createSuccessResult(command: "cd Documents"))
        
        // Verify suggestions were generated
        XCTAssertEqual(response.suggestions.count, 2, "Should have 2 proactive suggestions")
        XCTAssertEqual(response.suggestions[0].command, "alias ll='ls -la'")
        XCTAssertEqual(response.suggestions[1].command, "history | grep \"git commit\"")
        
        // Verify system prompt used for proactive suggestions
        XCTAssertTrue(mockCompletionService.lastMessages?.first?.content.contains("proactively helps users") ?? false,
                     "Should use the proactive system prompt")
    }
    
    // MARK: - Test Error Assistance
    
    func testErrorAssistance() async throws {
        // Create mocks
        let mockCompletionService = MockChatCompletionService()
        let mockParsingService = MockCommandParsingService()
        
        // Configure mock for error assistance
        let errorAssistanceResponse = """
        ERROR ANALYSIS:
        The 'apt-get' command is not found because macOS uses 'brew' instead of apt.
        
        SUGGESTIONS:
        - Suggestion: brew install package-name
          Explanation: Use Homebrew instead of apt-get on macOS
          Safety: safe
        
        - Suggestion: which apt-get
          Explanation: Check if apt-get is installed somewhere
          Safety: safe
        END SUGGESTIONS
        """
        
        mockCompletionService.chatCompletionResponse = AsyncStream { continuation in
            continuation.yield(ChatMessageChunk(content: errorAssistanceResponse))
            continuation.finish()
        }
        
        // Configure parsing service to return error suggestions
        mockParsingService.parseSuggestionsResult = [
            CommandSuggestion(
                command: "brew install package-name",
                explanation: "Use Homebrew instead of apt-get on macOS",
                safetyLevel: .safe
            ),
            CommandSuggestion(
                command: "which apt-get",
                explanation: "Check if apt-get is installed somewhere",
                safetyLevel: .safe
            )
        ]
        
        // Create handler
        let handler = AutoModeHandler(
            model: "test-model",
            parsingService: mockParsingService,
            completionService: mockCompletionService,
            aiModel: createSampleModel()
        )
        
        // Process input first
        _ = try await handler.processInput("apt-get install package-name")
        
        // Create a failed result
        let failedResult = createFailedResult(
            command: "apt-get install package-name",
            output: "apt-get: command not found",
            exitCode: 127
        )
        
        // Test error assistance
        let response = try await handler.handleCommandResult(failedResult)
        
        // Verify suggestions
        XCTAssertEqual(response.suggestions.count, 2, "Should have 2 error assistance suggestions")
        XCTAssertEqual(response.suggestions[0].command, "brew install package-name")
        XCTAssertEqual(response.suggestions[1].command, "which apt-get")
        
        // Verify system prompt used for error assistance
        XCTAssertTrue(mockCompletionService.lastMessages?.first?.content.contains("fixing command errors") ?? false,
                     "Should use the error assistance system prompt")
    }
    
    // MARK: - Test Pattern Detection and Specialized Suggestions
    
    func testPatternDetectionAndSpecializedSuggestions() async throws {
        // Create mocks
        let mockCompletionService = MockChatCompletionService()
        let mockParsingService = MockCommandParsingService()
        let patternDetector = MockCommandPatternDetector()
        
        // Configure mock for specialized suggestions
        let specializedSuggestionResponse = """
        SUGGESTIONS:
        - Suggestion: find . -name "*.txt" -type f | xargs grep "pattern"
          Explanation: Search for pattern in all text files
          Safety: safe
        
        - Suggestion: find . -name "*.txt" -exec grep "pattern" {} \\;
          Explanation: Alternative approach to search text files
          Safety: safe
        END SUGGESTIONS
        """
        
        mockCompletionService.chatCompletionResponse = AsyncStream { continuation in
            continuation.yield(ChatMessageChunk(content: specializedSuggestionResponse))
            continuation.finish()
        }
        
        // Configure parsing service to return specialized suggestions
        mockParsingService.parseSuggestionsResult = [
            CommandSuggestion(
                command: "find . -name \"*.txt\" -type f | xargs grep \"pattern\"",
                explanation: "Search for pattern in all text files",
                safetyLevel: .safe
            ),
            CommandSuggestion(
                command: "find . -name \"*.txt\" -exec grep \"pattern\" {} \\;",
                explanation: "Alternative approach to search text files",
                safetyLevel: .safe
            )
        ]
        
        // Create handler with custom pattern detector
        class TestableAutoModeHandler: AutoModeHandler {
            let customPatternDetector: MockCommandPatternDetector
            
            init(
                model: String,
                parsingService: CommandParsingService,
                completionService: ChatCompletionService,
                aiModel: AIModel?,
                patternDetector: MockCommandPatternDetector
            ) {
                self.customPatternDetector = patternDetector
                super.init(model: model, parsingService: parsingService, completionService: completionService, aiModel: aiModel)
            }
            
            override func detectPattern(in command: String) -> CommandPatternType? {
                return customPatternDetector.detectPattern(in: command)
            }
        }
        
        // Set up pattern detection
        patternDetector.detectedPattern = .searchPattern
        
        let handler = TestableAutoModeHandler(
            model: "test-model",
            parsingService: mockParsingService,
            completionService: mockCompletionService,
            aiModel: createSampleModel(),
            patternDetector: patternDetector
        )
        
        // Process input with search pattern
        let response = try await handler.processInput("grep pattern file.txt")
        
        // Verify specialized suggestions
        XCTAssertEqual(response.suggestions.count, 2, "Should have 2 specialized suggestions")
        XCTAssertEqual(response.suggestions[0].command, "find . -name \"*.txt\" -type f | xargs grep \"pattern\"")
        XCTAssertEqual(response.suggestions[1].command, "find . -name \"*.txt\" -exec grep \"pattern\" {} \\;")
        
        // Verify system prompt contains specialized instructions for search
        XCTAssertTrue(mockCompletionService.lastMessages?.first?.content.contains("searching") ?? false,
                     "Should use the search-specific system prompt")
    }
    
    // MARK: - Test Command Complexity Detection
    
    func testCommandComplexityDetection() async throws {
        // Create mocks
        let mockCompletionService = MockChatCompletionService()
        let mockParsingService = MockCommandParsingService()
        
        // Create testable subclass that exposes isComplexCommand for testing
        class TestableAutoModeHandler: AutoModeHandler {
            func testIsComplexCommand(_ command: String) -> Bool {
                return isComplexCommand(command)
            }
        }
        
        // Configure mock for suggestions when complex commands are detected
        let complexCommandResponse = """
        SUGGESTIONS:
        - Suggestion: command --help
          Explanation: View help for this complex command
          Safety: safe
        END SUGGESTIONS
        """
        
        mockCompletionService.chatCompletionResponse = AsyncStream { continuation in
            continuation.yield(ChatMessageChunk(content: complexCommandResponse))
            continuation.finish()
        }
        
        // Configure parsing service to return a suggestion
        mockParsingService.parseSuggestionsResult = [
            CommandSuggestion(
                command: "command --help",
                explanation: "View help for this complex command",
                safetyLevel: .safe
            )
        ]
        
        // Create handler
        let handler = TestableAutoModeHandler(
            model: "test-model",
            parsingService: mockParsingService,
            completionService: mockCompletionService,
            aiModel: createSampleModel()
        )
        
        // Test 1: Complex commands with pipes, redirections, and multiple operations
        XCTAssertTrue(handler.testIsComplexCommand("find . -name '*.txt' | xargs grep 'pattern'"), 
                     "Should detect pipe as complex")
        XCTAssertTrue(handler.testIsComplexCommand("cat file.txt > output.txt"), 
                     "Should detect redirection as complex")
        XCTAssertTrue(handler.testIsComplexCommand("ls -la && cd Documents"), 
                     "Should detect multiple commands as complex")
        XCTAssertTrue(handler.testIsComplexCommand("grep pattern file.txt || echo 'Not found'"), 
                     "Should detect conditional execution as complex")
        
        // Test 2: Commands with multiple flags
        XCTAssertTrue(handler.testIsComplexCommand("tar -zxvf archive.tar.gz"), 
                     "Should detect multiple flags as complex")
        XCTAssertTrue(handler.testIsComplexCommand("find . -type f -name '*.txt' -mtime -7"), 
                     "Should detect multiple arguments as complex")
        
        // Test 3: Complex tool usage
        XCTAssertTrue(handler.testIsComplexCommand("docker run --rm -it -p 8080:80 nginx"), 
                     "Should detect docker as complex tool")
        XCTAssertTrue(handler.testIsComplexCommand("find . -type f -name '*.js'"), 
                     "Should detect find as complex tool")
        XCTAssertTrue(handler.testIsComplexCommand("awk '{print $1}' file.txt"), 
                     "Should detect awk as complex tool")
        
        // Test 4: Simple commands that shouldn't trigger complexity detection
        XCTAssertFalse(handler.testIsComplexCommand("ls"), 
                      "Basic ls shouldn't be complex")
        XCTAssertFalse(handler.testIsComplexCommand("cd Documents"), 
                      "Basic cd shouldn't be complex")
        XCTAssertFalse(handler.testIsComplexCommand("echo hello"), 
                      "Basic echo shouldn't be complex")
        
        // Verify behavior when processing commands
        // Complex command should generate suggestions
        let complexResponse = try await handler.processInput("find . -name '*.txt' | grep pattern")
        XCTAssertFalse(complexResponse.suggestions.isEmpty, 
                      "Complex command should trigger suggestions")
        
        // Simple command should not generate suggestions
        let simpleResponse = try await handler.processInput("ls")
        XCTAssertTrue(simpleResponse.suggestions.isEmpty, 
                     "Simple command should not trigger suggestions")
    }
    
    // MARK: - Test Safety Level Detection
    
    func testSafetyLevelDetection() async throws {
        // Create mocks
        let mockCompletionService = MockChatCompletionService()
        let mockParsingService = MockCommandParsingService()
        
        // Configure mock for destructive command suggestions
        let destructiveCommandResponse = """
        SUGGESTIONS:
        - Suggestion: rm -rf /some/path
          Explanation: Remove directory recursively
          Safety: destructive
        END SUGGESTIONS
        """
        
        mockCompletionService.chatCompletionResponse = AsyncStream { continuation in
            continuation.yield(ChatMessageChunk(content: destructiveCommandResponse))
            continuation.finish()
        }
        
        // Configure parsing service to return a suggestion with destructive safety level
        mockParsingService.parseSuggestionsResult = [
            CommandSuggestion(
                command: "rm -rf /some/path",
                explanation: "Remove directory recursively",
                safetyLevel: .destructive,
                requiresConfirmation: true
            )
        ]
        
        // Create handler
        let handler = AutoModeHandler(
            model: "test-model",
            parsingService: mockParsingService,
            completionService: mockCompletionService,
            aiModel: createSampleModel()
        )
        
        // Process input that might trigger destructive suggestions
        let response = try await handler.processInput("rm -rf")
        
        // Verify destructive suggestion
        XCTAssertEqual(response.suggestions.count, 1, "Should have 1 suggestion")
        XCTAssertEqual(response.suggestions[0].safetyLevel, .destructive, 
                      "Should be marked as destructive")
        XCTAssertTrue(response.suggestions[0].requiresConfirmation, 
                     "Destructive command should require confirmation")
    }
}
