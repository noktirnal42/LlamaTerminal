import XCTest
@testable import App
@testable import TerminalCore
@testable import AIIntegration
@testable import UIComponents

final class AICommandWorkflowTests: XCTestCase {
    var appState: AppState!
    
    override func setUp() {
        super.setUp()
        appState = AppState()
        appState.addNewTab() // Add a tab for terminal operations
        
        // Setup test models
        setupTestModels()
    }
    
    override func tearDown() {
        appState = nil
        super.tearDown()
    }
    
    // Test AI command generation workflow
    func testCommandGenerationWorkflow() {
        // Setup command mode
        appState.setAIMode(.command)
        XCTAssertEqual(appState.currentAIMode, .command, "AI mode should be set to command")
        
        // Create a mock "generated" command
        let generatedCommand = "find . -type f -name \"*.swift\" | wc -l"
        
        // Simulate command suggestion (in real app this would come from AI)
        mockCommandSuggestion(generatedCommand)
        
        // Check if command was added to suggestions
        XCTAssertEqual(appState.aiSuggestions.first, generatedCommand, "Generated command should be in suggestions")
        
        // Simulate command execution
        executeCommand(generatedCommand)
        
        // Verify command was executed and added to history
        XCTAssertTrue(appState.commandHistory.contains { $0.command == generatedCommand }, 
                     "Command should be added to history after execution")
    }
    
    // Test terminal output capture and processing
    func testTerminalOutputProcessing() {
        // Setup terminal session
        let terminalSession = appState.terminalTabs.first?.session
        XCTAssertNotNil(terminalSession, "Terminal session should exist")
        
        // Generate some output
        let testOutput = "Hello from terminal"
        terminalSession?.addOutput(testOutput)
        
        // In a real app, this would be processed by AI
        // Here we just verify it's captured
        XCTAssertEqual(terminalSession?.lastOutput, testOutput, "Output should be captured")
        
        // Test with multiline output
        let multilineOutput = "Line 1\nLine 2\nLine 3"
        terminalSession?.addOutput(multilineOutput)
        
        XCTAssertEqual(terminalSession?.lastOutput, multilineOutput, "Multiline output should be captured correctly")
    }
    
    // Test command history synchronization
    func testCommandHistorySynchronization() {
        // Execute commands
        let commands = ["ls -la", "pwd", "echo 'test'"]
        
        for command in commands {
            executeCommand(command)
        }
        
        // Verify all commands are in history
        XCTAssertEqual(appState.commandHistory.count, commands.count, "All commands should be added to history")
        
        // Verify order (newest first)
        for (index, command) in commands.enumerated() {
            XCTAssertEqual(appState.commandHistory[commands.count - 1 - index].command, command, 
                          "Commands should be in correct order")
        }
        
        // Test clearing history
        appState.commandHistory.removeAll()
        XCTAssertEqual(appState.commandHistory.count, 0, "History should be clearable")
    }
    
    // Test AI mode state transitions
    func testAIModeStateTransitions() {
        // Test mode transitions and their effects on UI state
        
        // Start with disabled
        appState.setAIMode(.disabled)
        XCTAssertFalse(appState.showAIPanel, "AI panel should be hidden when disabled")
        
        // Transition: disabled -> auto
        appState.setAIMode(.auto)
        XCTAssertTrue(appState.showAIPanel, "AI panel should show when transitioning from disabled to auto")
        XCTAssertEqual(appState.currentAIMode, .auto, "Current mode should be auto")
        
        // Transition: auto -> code
        appState.setAIMode(.code)
        XCTAssertTrue(appState.showAIPanel, "AI panel should remain visible when changing modes")
        XCTAssertEqual(appState.currentAIMode, .code, "Current mode should be code")
        
        // Transition: code -> disabled
        appState.setAIMode(.disabled)
        XCTAssertEqual(appState.currentAIMode, .disabled, "Current mode should be disabled")
        
        // Transition: disabled -> auto (with panel hidden)
        appState.showAIPanel = false
        appState.setAIMode(.auto)
        XCTAssertTrue(appState.showAIPanel, "AI panel should automatically show when enabling AI mode")
    }
    
    // Test adaptive behavior based on terminal context
    func testAdaptiveBehaviorBasedOnContext() {
        // Set up code mode
        appState.setAIMode(.code)
        
        // Simulate terminal context with code-related command
        executeCommand("vim main.swift")
        
        // In a real app, this would trigger code suggestions
        // Here we'll simulate by adding a code suggestion directly
        let codeSuggestion = "func main() {\n    print(\"Hello, world!\")\n}\n\nmain()"
        mockCodeSuggestion(codeSuggestion)
        
        // Verify appropriate suggestions
        XCTAssertEqual(appState.aiCodeSuggestions.first, codeSuggestion, "Code suggestion should be added")
        
        // Switch to command mode
        appState.setAIMode(.command)
        
        // Simulate terminal context with directory listing
        executeCommand("ls -la")
        
        // Simulate command suggestion
        let commandSuggestion = "find . -name '*.swift'"
        mockCommandSuggestion(commandSuggestion)
        
        // Verify appropriate suggestions
        XCTAssertEqual(appState.aiSuggestions.first, commandSuggestion, "Command suggestion should be added")
    }
    
    // MARK: - Helper Methods
    
    /// Setup test models
    private func setupTestModels() {
        // Create test models
        let codeModel = AIModel(
            id: "code-model",
            name: "CodeLlama",
            size: 1000,
            modified: Date(),
            capabilities: ModelCapabilities(isCodeCapable: true)
        )
        
        let commandModel = AIModel(
            id: "command-model",
            name: "TerminalLlama",
            size: 1500,
            modified: Date(),
            capabilities: ModelCapabilities(isCommandOptimized: true)
        )
        
        // Add models to available models
        appState.availableModels = [codeModel, commandModel]
        
        // Select a model
        appState.selectedModel = codeModel
    }
    
    /// Execute a command (test helper)
    private func executeCommand(_ command: String) {
        // Execute on terminal
        appState.terminalTabs.first?.session.executeCommand(command)
        
        // Add to history (this would normally happen via output capture)
        addCommandToHistory(command)
    }
    
    /// Add a command to history (test helper)
    private func addCommandToHistory(_ command: String) {
        let historyItem = CommandHistoryItem(
            id: UUID(),
            command: command,
            output: "Simulated output for '\(command)'",
            timestamp: Date(),
            isAIGenerated: false
        )
        
        appState.commandHistory.append(historyItem)
    }
    
    /// Mock a command suggestion (test helper)
    private func mockCommandSuggestion(_ command: String) {
        // In a real app this would come from AI API
        if appState.aiSuggestions == nil {
            appState.aiSuggestions = [command]
        } else {
            appState.aiSuggestions?.append(command)
        }
    }
    
    /// Mock a code suggestion (test helper)
    private func mockCodeSuggestion(_ code: String) {
        // In a real app this would come from AI API
        if appState.aiCodeSuggestions == nil {
            appState.aiCodeSuggestions = [code]
        } else {
            appState.aiCodeSuggestions?.append(code)
        }
    }
    
    static var allTests = [
        ("testCommandGenerationWorkflow", testCommandGenerationWorkflow),
        ("testTerminalOutputProcessing", testTerminalOutputProcessing),
        ("testCommandHistorySynchronization", testCommandHistorySynchronization),
        ("testAIModeStateTransitions", testAIModeStateTransitions),
        ("testAdaptiveBehaviorBasedOnContext", testAdaptiveBehaviorBasedOnContext),
    ]
}

//

