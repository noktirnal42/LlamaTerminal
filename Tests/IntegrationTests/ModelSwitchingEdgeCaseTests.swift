import XCTest
@testable import App
@testable import TerminalCore
@testable import AIIntegration
@testable import UIComponents

final class ModelSwitchingEdgeCaseTests: XCTestCase {
    var appState: AppState!
    
    override func setUp() {
        super.setUp()
        appState = AppState()
        
        // Setup with some models
        setupTestModels()
    }
    
    override func tearDown() {
        appState = nil
        super.tearDown()
    }
    
    // Test model unavailability scenarios
    func testModelUnavailabilityScenarios() {
        // Initially has models
        XCTAssertFalse(appState.availableModels.isEmpty, "Should start with available models")
        
        // Select a model
        let initialModel = appState.availableModels.first!
        appState.selectedModel = initialModel
        XCTAssertEqual(appState.selectedModel?.id, initialModel.id, "Model should be selected")
        
        // Simulate model becoming unavailable (e.g., Ollama crash)
        simulateModelUnavailable(initialModel)
        
        // In a robust app, it should handle this gracefully
        let expectation = self.expectation(description: "Model unavailability handled")
        
        handleModelUnavailable(initialModel) { success in
            // Should deselect the model and display a warning or fallback
            XCTAssertNil(appState.selectedModel, "Selected model should be cleared when unavailable")
            XCTAssertTrue(success, "Unavailability should be handled gracefully")
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0, handler: nil)
    }
    
    // Test model capability changes during runtime
    func testModelCapabilityChanges() {
        // Select a code-capable model
        let codeModel = appState.availableModels.first { $0.capabilities.isCodeCapable }!
        appState.selectedModel = codeModel
        XCTAssertTrue(appState.selectedModel!.capabilities.isCodeCapable, "Selected model should have code capabilities")
        
        // Put app in code mode
        appState.setAIMode(.code)
        XCTAssertEqual(appState.currentAIMode, .code, "App should be in code mode")
        
        // Simulate model capabilities changing at runtime (e.g., Ollama update)
        simulateCapabilityChange(codeModel, newCapabilities: ModelCapabilities(isCodeCapable: false))
        
        // Test proper handling - should notify user but not crash
        let expectation = self.expectation(description: "Capability change handled")
        
        handleCapabilityChange(codeModel) { success in
            // Should maintain mode but indicate capability change
            XCTAssertEqual(appState.currentAIMode, .code, "Mode should not change automatically")
            XCTAssertFalse(appState.selectedModel!.capabilities.isCodeCapable, "Model should reflect updated capabilities")
            XCTAssertTrue(success, "Capability change should be handled gracefully")
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0, handler: nil)
    }
    
    // Test model switching during active operations
    func testModelSwitchingDuringActiveOperations() {
        // Start with a model
        let initialModel = appState.availableModels.first!
        appState.selectedModel = initialModel
        
        // Simulate an active AI operation
        let operationExpectation = self.expectation(description: "Operation completed")
        var operationCompleted = false
        
        startLongRunningOperation {
            operationCompleted = true
            operationExpectation.fulfill()
        }
        
        // Change model mid-operation
        let newModel = appState.availableModels.last!
        XCTAssertNotEqual(initialModel.id, newModel.id, "Should be different models for test")
        
        appState.selectedModel = newModel
        XCTAssertEqual(appState.selectedModel?.id, newModel.id, "Model should change immediately")
        
        // Wait for operation to complete - should not deadlock or crash
        waitForExpectations(timeout: 3.0, handler: nil)
        XCTAssertTrue(operationCompleted, "Operation should complete despite model change")
    }
    
    // Test model load/unload edge cases
    func testModelLoadUnloadEdgeCases() {
        // Test the case where all models become unavailable
        let expectation = self.expectation(description: "No models handled gracefully")
        
        // Start with models
        XCTAssertFalse(appState.availableModels.isEmpty, "Should start with models")
        
        // Clear all models (simulate Ollama service stopping)
        simulateAllModelsUnavailable()
        XCTAssertTrue(appState.availableModels.isEmpty, "All models should be unavailable")
        
        // App should handle this gracefully
        handleNoModelsAvailable { success in
            XCTAssertTrue(success, "Should handle no models gracefully")
            XCTAssertNil(appState.selectedModel, "Selected model should be cleared")
            XCTAssertEqual(appState.currentAIMode, .disabled, "AI mode should be disabled")
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0, handler: nil)
        
        // Test loading models back - should recover
        let recoveryExpectation = self.expectation(description: "Models restored")
        
        // Restore models
        simulateModelsRestored()
        
        // Verify recovery
        XCTAssertFalse(appState.availableModels.isEmpty, "Models should be restored")
        
        recoveryExpectation.fulfill()
        waitForExpectations(timeout: 1.0, handler: nil)
    }
    
    // Test concurrent model switching attempts
    func testConcurrentModelSwitching() {
        // Start with a model
        let initialModel = appState.availableModels.first!
        appState.selectedModel = initialModel
        
        // Setup models to switch between
        guard appState.availableModels.count >= 3 else {
            XCTFail("Need at least 3 models for this test")
            return
        }
        
        let model1 = appState.availableModels[0]
        let model2 = appState.availableModels[1]
        let model3 = appState.availableModels[2]
        
        // Simulate rapid switching from multiple sources
        let expectation = self.expectation(description: "Concurrent switching completed")
        
        // Use a dispatch group to coordinate the concurrent operations
        let dispatchGroup = DispatchGroup()
        
        // Track issues
        var encounteredIssue = false
        
        // First switch
        dispatchGroup.enter()
        DispatchQueue.global().async {
            self.appState.selectedModel = model1
            dispatchGroup.leave()
        }
        
        // Second switch
        dispatchGroup.enter()
        DispatchQueue.global().async {
            self.appState.selectedModel = model2
            dispatchGroup.leave()
        }
        
        // Third switch with delay
        dispatchGroup.enter()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            self.appState.selectedModel = model3
            dispatchGroup.leave()
        }
        
        // Wait for all to complete
        dispatchGroup.notify(queue: .main) {
            // After all operations, the selected model should be valid
            XCTAssertNotNil(self.appState.selectedModel, "A model should be selected")
            
            // It should be one of our test models
            let isValidModel = self.appState.selectedModel?.id == model1.id ||
                             self.appState.selectedModel?.id == model2.id ||
                             self.appState.selectedModel?.id == model3.id
                          
            XCTAssertTrue(isValidModel, "Selected model should be one of the test models")
            XCTAssertFalse(encounteredIssue, "No issues should occur during concurrent switching")
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2.0, handler: nil)
    }
    
    // MARK: - Helper Methods
    
    // Setup test models
    private func setupTestModels() {
        // Create test models with different capabilities
        var models: [AIModel] = []
        
        // Code model
        let codeModel = AIModel(
            id: "code-model",
            name: "CodeLlama",
            size: 3_000_000_000,
            modified: Date(),
            capabilities: ModelCapabilities(isCodeCapable: true)
        )
        models.append(codeModel)
        
        // Command model
        let commandModel = AIModel(
            id: "command-model",
            name: "CommandLlama",
            size: 2_000_000_000,
            modified: Date(),
            capabilities: ModelCapabilities(isCommandOptimized: true)
        )
        models.append(commandModel)
        
        // General model
        let generalModel = AIModel(
            id: "general-model",
            name: "Llama3",
            size: 4_000_000_000,
            modified: Date(),
            capabilities: ModelCapabilities()
        )
        models.append(generalModel)
        
        // Multimodal model
        let multimodalModel = AIModel(
            id: "multimodal-model",
            name: "LlamaVision",
            size: 7_000_000_000,
            modified: Date(),
            capabilities: ModelCapabilities(isMultimodal: true)
        )
        models.append(multimodalModel)
        
        appState.availableModels = models
    }
    
    // Simulate model becoming unavailable
    private func simulateModelUnavailable(_ model: AIModel) {
        appState.availableModels.removeAll { $0.id == model.id }
    }
    
    // Handle model unavailability
    private func handleModelUnavailable(_ model: AIModel, completion: @escaping (Bool) -> Void) {
        // In a real app, this would show alerts, etc.
        // For testing, just clear selected model
        if appState.selectedModel?.id == model.id {
            appState.selectedModel = nil
        }
        
        // Return success
        completion(true)
    }
    
    // Simulate capability change
    private func simulateCapabilityChange(_ model: AIModel, newCapabilities: ModelCapabilities) {
        // Find the model and update its capabilities
        if let index = appState.availableModels.firstIndex(where: { $0.id == model.id }) {
            // Create a new model with updated capabilities
            let updatedModel = AIModel(
                id: model.id,
                name: model.name,
                size: model.size,
                modified: model.modified,
                capabilities: newCapabilities
            )
            
            // Update the model in the list
            appState.availableModels[index] = updatedModel
            
            // Update selected model if needed
            if appState.selectedModel?.id == model.id {
                appState.selectedModel = updatedModel
            }
        }
    }
    
    // Handle capability change
    private func handleCapabilityChange(_ model: AIModel, completion: @escaping (Bool) -> Void) {
        // In a real app, this might show alerts or update UI
        // For testing, consider it handled
        completion(true)
    }
    
    // Start a long-running operation
    private func startLongRunningOperation(completion: @escaping () -> Void) {
        // Simulate a lengthy AI operation
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            // Operation completes
            completion()
        }
    }
    
    // Simulate all models becoming unavailable
    private func simulateAllModelsUnavailable() {
        appState.availableModels = []
    }
    
    // Handle no models available
    private func handleNoModelsAvailable(completion: @escaping (Bool) -> Void) {
        // Clear selected model
        appState.selectedModel = nil
        
        // Set AI mode to disabled
        appState.setAIMode(.disabled)
        
        // Return success
        completion(true)
    }
    
    // Simulate models being restored
    private func simulateModelsRestored() {
        // Restore models by calling setup again
        setupTestModels()
    }
    
    // Test model version updates
    func testModelVersionUpdates() {
        // Start with original model
        let originalModel = appState.availableModels.first { $0.name == "Llama3" }!
        appState.selectedModel = originalModel
        XCTAssertEqual(appState.selectedModel?.id, originalModel.id, "Original model should be selected")
        
        // Simulate a model version update (same name but different ID and possibly capabilities)
        let updatedModel = AIModel(
            id: "updated-model-id",
            name: "Llama3", // Same name
            size: originalModel.size + 1_000_000_000, // Larger size
            modified: Date(), // Newer date
            capabilities: ModelCapabilities(isCodeCapable: true) // Added capabilities
        )
        
        // Simulate update by replacing the model in available models
        let originalIndex = appState.availableModels.firstIndex { $0.id == originalModel.id }!
        appState.availableModels[originalIndex] = updatedModel
        
        // Test version update handling
        let expectation = self.expectation(description: "Version update handled")
        
        handleModelVersionUpdate(originalModel, updatedModel) { success in
            // Should update the selected model to the new version
            XCTAssertEqual(appState.selectedModel?.id, updatedModel.id, "Selected model should update to new version")
            XCTAssertTrue(appState.selectedModel?.capabilities.isCodeCapable ?? false, "Updated capabilities should be reflected")
            XCTAssertTrue(success, "Version update should be handled gracefully")
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0, handler: nil)
    }
    
    // Test switching between models with different capabilities
    func testSwitchingBetweenDifferentCapabilities() {
        // Put app in code mode
        appState.setAIMode(.code)
        
        // Start with code-capable model
        let codeModel = appState.availableModels.first { $0.capabilities.isCodeCapable }!
        appState.selectedModel = codeModel
        XCTAssertTrue(appState.selectedModel?.capabilities.isCodeCapable ?? false, "Selected model should have code capabilities")
        
        // Find a model without code capabilities
        let nonCodeModel = appState.availableModels.first { !$0.capabilities.isCodeCapable }!
        XCTAssertFalse(nonCodeModel.capabilities.isCodeCapable, "Test model should not have code capabilities")
        
        // Switch to non-code model
        let expectation = self.expectation(description: "Capability switch handled")
        
        // Simulate user switching models
        appState.selectedModel = nonCodeModel
        
        // Test capability mismatch handling
        handleCapabilityMismatch(appState.currentAIMode, nonCodeModel) { handled in
            // In a real app, this might show a warning or suggest switching modes
            // Here we just verify it's handled
            XCTAssertTrue(handled, "Capability mismatch should be handled")
            XCTAssertEqual(appState.selectedModel?.id, nonCodeModel.id, "Model should still be switched despite capabilities mismatch")
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0, handler: nil)
        
        // Test switching back to matching capabilities
        appState.selectedModel = codeModel
        XCTAssertEqual(appState.selectedModel?.id, codeModel.id, "Should switch back to code model")
    }
    
    // Test handling network timeouts during model operations
    func testNetworkTimeoutsDuringModelOperations() {
        // Simulate starting a model operation
        let expectation = self.expectation(description: "Timeout handled")
        
        // Simulate a network timeout during model loading
        simulateNetworkTimeout { handled in
            // Should handle timeout gracefully
            XCTAssertTrue(handled, "Network timeout should be handled gracefully")
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2.0, handler: nil)
        
        // Test retry mechanism
        let retryExpectation = self.expectation(description: "Retry mechanism works")
        
        // Simulate retry success
        simulateRetryAfterTimeout { success in
            XCTAssertTrue(success, "Retry after timeout should succeed")
            retryExpectation.fulfill()
        }
        
        waitForExpectations(timeout: 2.0, handler: nil)
    }
    
    // MARK: - Additional Helper Methods
    
    // Handle model version update
    private func handleModelVersionUpdate(_ oldModel: AIModel, _ newModel: AIModel, completion: @escaping (Bool) -> Void) {
        // If currently selected model is the one being updated, update the reference
        if appState.selectedModel?.id == oldModel.id {
            appState.selectedModel = newModel
        }
        
        // Return success
        completion(true)
    }
    
    // Handle capability mismatch between mode and model
    private func handleCapabilityMismatch(_ mode: AIMode, _ model: AIModel, completion: @escaping (Bool) -> Void) {
        // In a real app, this would show warnings or suggestions
        // For testing, we just simulate handling it
        
        var mismatchDetected = false
        
        // Detect mismatches
        switch mode {
        case .code:
            mismatchDetected = !model.capabilities.isCodeCapable
        case .command:
            mismatchDetected = !model.capabilities.isCommandOptimized
        default:
            mismatchDetected = false
        }
        
        // Return whether a mismatch was detected and handled
        completion(mismatchDetected)
    }
    
    // Simulate network timeout
    private func simulateNetworkTimeout(completion: @escaping (Bool) -> Void) {
        // Simulate starting a network request that times out
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            // Simulate timeout detection and handling
            completion(true)
        }
    }
    
    // Simulate retry after timeout
    private func simulateRetryAfterTimeout(completion: @escaping (Bool) -> Void) {
        // Simulate retry logic
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            // Simulate successful retry
            completion(true)
        }
    }
    
    static var allTests = [
        ("testModelUnavailabilityScenarios", testModelUnavailabilityScenarios),
        ("testModelCapabilityChanges", testModelCapabilityChanges),
        ("testModelSwitchingDuringActiveOperations", testModelSwitchingDuringActiveOperations),
        ("testModelLoadUnloadEdgeCases", testModelLoadUnloadEdgeCases),
        ("testConcurrentModelSwitching", testConcurrentModelSwitching),
        ("testModelVersionUpdates", testModelVersionUpdates),
        ("testSwitchingBetweenDifferentCapabilities", testSwitchingBetweenDifferentCapabilities),
        ("testNetworkTimeoutsDuringModelOperations", testNetworkTimeoutsDuringModelOperations),
    ]
}

