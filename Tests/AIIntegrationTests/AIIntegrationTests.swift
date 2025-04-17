import XCTest
import Combine
@testable import AIIntegration
@testable import TerminalCore

final class AIIntegrationTests: XCTestCase {
    var coordinator: AITerminalCoordinator!
    var mockModelService: MockOllamaModelService!
    
    // Sample test models
    var commandModel: AIModel!
    var codeModel: AIModel!
    var generalModel: AIModel!
    
    override func setUp() async throws {
        // Create test models
        commandModel = AIModel(
            id: "command-model-id",
            name: "llama:command",
            size: 1024 * 1024 * 1024,
            modified: Date(),
            capabilities: ModelCapabilities(isCodeCapable: false, isMultimodal: false, isCommandOptimized: true)
        )
        
        codeModel = AIModel(
            id: "code-model-id",
            name: "llama:code",
            size: 2048 * 1024 * 1024,
            modified: Date(),
            capabilities: ModelCapabilities(isCodeCapable: true, isMultimodal: false, isCommandOptimized: false)
        )
        
        generalModel = AIModel(
            id: "general-model-id",
            name: "llama:general",
            size: 3072 * 1024 * 1024,
            modified: Date(),
            capabilities: ModelCapabilities(isCodeCapable: true, isMultimodal: true, isCommandOptimized: true)
        )
        
        // Create mock model service
        mockModelService = MockOllamaModelService()
        mockModelService.availableModels = [commandModel, codeModel, generalModel]
        
        // Initialize coordinator with mock service
        coordinator = AITerminalCoordinator(modelService: mockModelService)
    }
    
    override func tearDown() async throws {
        coordinator = nil
        mockModelService = nil
        commandModel = nil
        codeModel = nil
        generalModel = nil
    }
    
    // MARK: - Initialization Tests
    
    func testInitializationSuccess() async {
        // Test successful initialization
        let success = await coordinator.initialize()
        XCTAssertTrue(success)
        XCTAssertTrue(await coordinator.isReady)
        
        // Verify default model selection
        let currentModel = await coordinator.currentModel
        XCTAssertNotNil(currentModel)
        
        // Should select command model first
        XCTAssertEqual(currentModel?.id, commandModel.id)
    }
    
    func testInitializationFailure() async {
        // Set up failure condition
        mockModelService.shouldFail = true
        
        // Test failed initialization
        let success = await coordinator.initialize()
        XCTAssertFalse(success)
        XCTAssertFalse(await coordinator.isReady)
        XCTAssertNil(await coordinator.currentModel)
    }
    
    // MARK: - Mode Switching Tests
    
    func testModeSwitching() async {
        // Initialize first
        _ = await coordinator.initialize()
        
        // Default mode should be disabled
        var currentMode = await coordinator.currentMode
        XCTAssertEqual(currentMode, .disabled)
        
        // Switch to auto mode
        await coordinator.setMode(.auto)
        currentMode = await coordinator.currentMode
        XCTAssertEqual(currentMode, .auto)
        
        // Verify state
        let state = await coordinator.currentState
        XCTAssertTrue(state.isActive)
        
        // Switch to dispatch mode
        await coordinator.setMode(.dispatch)
        currentMode = await coordinator.currentMode
        XCTAssertEqual(currentMode, .dispatch)
        
        // Switch back to disabled
        await coordinator.setMode(.disabled)
        currentMode = await coordinator.currentMode
        XCTAssertEqual(currentMode, .disabled)
        
        // Verify state is inactive
        let finalState = await coordinator.currentState
        XCTAssertFalse(finalState.isActive)
    }
    
    // MARK: - Model Selection Tests
    
    func testModelSelection() async {
        // Initialize first
        _ = await coordinator.initialize()
        
        // Switch to code model
        await coordinator.setModel(codeModel)
        let currentModel = await coordinator.currentModel
        XCTAssertEqual(currentModel?.id, codeModel.id)
        
        // Test model filtering
        let codeModels = await coordinator.getModels(withCapability: .code)
        XCTAssertEqual(codeModels.count, 2) // Code model and general model
        
        let commandModels = await coordinator.getModels(withCapability: .command)
        XCTAssertEqual(commandModels.count, 2) // Command model and general model
        
        let multimodalModels = await coordinator.getModels(withCapability: .multimodal)
        XCTAssertEqual(multimodalModels.count, 1) // Only general model
    }
    
    func testModelRefresh() async {
        // Initialize first
        _ = await coordinator.initialize()
        
        // Add a new model to the mock service
        let newModel = AIModel(
            id: "new-model",
            name: "llama:new",
            size: 4096 * 1024 * 1024,
            modified: Date(),
            capabilities: ModelCapabilities(isCodeCapable: true, isMultimodal: true, isCommandOptimized: true)
        )
        mockModelService.availableModels.append(newModel)
        
        // Refresh models
        let success = await coordinator.refreshModels()
        XCTAssertTrue(success)
        
        // Should now have 4 models
        let allModels = await coordinator.getAvailableModels()
        XCTAssertEqual(allModels.count, 4)
    }
    
    // MARK: - Command Processing Tests
    
    func testAutoModeProcessing() async throws {
        // Initialize and set up auto mode
        _ = await coordinator.initialize()
        await coordinator.setModel(commandModel)
        await coordinator.setMode(.auto)
        
        // Set up mock response
        mockModelService.mockHandler.suggestions = [
            CommandSuggestion(
                command: "ls -la",
                explanation: "List all files with details",
                safetyLevel: .safe,
                requiresConfirmation: false
            )
        ]
        
        // Process input
        let response = try await coordinator.processInput("show me all files")
        
        // Verify suggestions
        XCTAssertEqual(response.suggestions.count, 1)
        XCTAssertEqual(response.suggestions.first?.command, "ls -la")
    }
    
    func testDispatchModeProcessing() async throws {
        // Initialize and set up dispatch mode
        _ = await coordinator.initialize()
        await coordinator.setModel(commandModel)
        await coordinator.setMode(.dispatch)
        
        // Set up mock response
        mockModelService.mockHandler.actions = [
            AIAction(
                type: .executeCommand,
                content: "mkdir test_dir",
                requiresConfirmation: false
            )
        ]
        
        // Process input
        let response = try await coordinator.processInput("create a directory called test_dir")
        
        // Verify actions
        XCTAssertEqual(response.actions.count, 1)
        XCTAssertEqual(response.actions.first?.type, .executeCommand)
        XCTAssertEqual(response.actions.first?.content, "mkdir test_dir")
    }
    
    // MARK: - Command Result Tests
    
    func testCommandResultHandling() async throws {
        // Initialize and set up auto mode
        _ = await coordinator.initialize()
        await coordinator.setModel(commandModel)
        await coordinator.setMode(.auto)
        
        // Create successful command result
        let successResult = CommandResult(
            command: "ls -la",
            output: "total 16\ndrwxr-xr-x 4 user group 128 Apr 16 17:00 .",
            exitCode: 0,
            duration: 0.1
        )
        
        // Process result
        let successResponse = try await coordinator.handleCommandResult(successResult)
        
        // Verify analysis was performed
        XCTAssertNotNil(successResponse.context)
        
        // Create failed command result
        let failureResult = CommandResult(
            command: "cat nonexistent.txt",
            output: "cat: nonexistent.txt: No such file or directory",
            exitCode: 1,
            duration: 0.1
        )
        
        // Process failed result
        let failureResponse = try await coordinator.handleCommandResult(failureResult)
        
        // Verify error analysis was performed
        XCTAssertNotNil(failureResponse.context)
    }
    
    // MARK: - Safety Check Tests
    
    func testSafeActionConfirmation() async {
        // Initialize
        _ = await coordinator.initialize()
        
        // Create safe action
        let safeAction = AIAction(
            type: .executeCommand,
            content: "ls -la",
            requiresConfirmation: false
        )
        
        // Should execute without confirmation
        let shouldExecute = await coordinator.executeAction(safeAction)
        XCTAssertTrue(shouldExecute)
    }
    
    func testDestructiveActionConfirmation() async {
        // Initialize
        _ = await coordinator.initialize()
        
        // Create destructive action
        let destructiveAction = AIAction(
            type: .executeCommand,
            content: "rm -rf /",
            requiresConfirmation: true
        )
        
        // Without confirmation handler, should default to not executing
        let shouldExecute = await coordinator.executeAction(destructiveAction)
        XCTAssertFalse(shouldExecute)
    }
    
    // MARK: - Model Management Tests
    
    func testModelPulling() async {
        // Set up mock progress
        let progress1 = PullProgress(completed: 50, total: 100, status: "downloading")
        let progress2 = PullProgress(completed: 100, total: 100, status: "success")
        mockModelService.mockPullProgress = [progress1, progress2]
        
        // Pull a model
        var progressValues: [PullProgress] = []
        let stream = coordinator.pullModel("llama:newmodel")
        
        do {
            for try await progress in stream {
                progressValues.append(progress)
            }
        } catch {
            XCTFail("Should not throw: \(error)")
        }
        
        // Verify progress updates
        XCTAssertEqual(progressValues.count, 2)
        XCTAssertEqual(progressValues.first?.completed, 50)
        XCTAssertEqual(progressValues.last?.status, "success")
    }
    
    func testModelDeletion() async throws {
        // Initialize
        _ = await coordinator.initialize()
        
        // Delete a model
        try await coordinator.deleteModel(commandModel)
        
        // Verify model was removed from available models
        let models = await coordinator.getAvailableModels()
        XCTAssertEqual(models.count, 2) // Initial 3 minus 1
        XCTAssertFalse(models.contains { $0.id == commandModel.id })
    }
}

// MARK: - Mock Classes

class MockOllamaModelService: OllamaModelService {
    var availableModels: [AIModel] = []
    var shouldFail: Bool = false
    var mockHandler = MockModeHandler()
    var mockPullProgress: [PullProgress] = []
    
    override func listModels() async throws -> [AIModel] {
        if shouldFail {
            throw OllamaError.connectionFailed
        }
        return availableModels
    }
    
    override func pullModel(modelName: String) throws -> AsyncThrowingStream<PullProgress, Error> {
        if shouldFail {
            throw OllamaError.connectionFailed
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                for progress in self.mockPullProgress {
                    continuation.yield(progress)
                }
                continuation.finish()
            }
        }
    }
    
    override func deleteModel(modelName: String) async throws {
        if shouldFail {
            throw OllamaError.connectionFailed
        }
        
        availableModels.removeAll { $0.name == modelName }
    }
}

class MockModeHandler: AIModeHandler {
    var model: AIModel = AIModel(
        id: "mock-id",
        name: "mock-model",
        size: 1024,
        modified: Date()
    )
    
    var suggestions: [CommandSuggestion] = []
    var actions: [AIAction] = []
    var context: String?
    
    required init(model: AIModel) {
        self.model = model
    }
    
    func getState() async -> AIModeState {
        return AIModeState(
            isActive: true,
            context: ["Mock context"],
            pendingActions: actions
        )
    }
    
    func processInput(_ input: String) async throws -> AIModeResponse {
        return AIModeResponse(
            suggestions: suggestions,
            actions: actions,
            context: context
        )
    }
    
    func handleCommandResult(_ result: CommandResult) async throws -> AIModeResponse {
        return AIModeResponse(
            suggestions: suggestions,
            actions: actions,
            context: result.isSuccessful ? "Command executed successfully" : "Command failed"
        )
    }
    
    func reset() async {
        suggestions = []
        actions = []
        context = nil
    }
}

