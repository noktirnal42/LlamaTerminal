import XCTest
import SwiftUI
import ViewInspector
@testable import App
@testable import TerminalCore
@testable import AIIntegration
@testable import UIComponents

final class UIInteractionPathsTests: XCTestCase {
    var appState: AppState!
    
    override func setUp() {
        super.setUp()
        appState = AppState()
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
    }
    
    override func tearDown() {
        appState = nil
        super.tearDown()
    }
    
    // MARK: - Basic UI Interaction Tests
    
    func testModelSelectionSheetFlow() {
        XCTAssertFalse(appState.showModelSelectionSheet, "Model selection sheet should be hidden initially")
        
        appState.showModelSelectionSheet = true
        XCTAssertTrue(appState.showModelSelectionSheet, "Model selection sheet should be visible after setting")
        
        appState.showModelSelectionSheet = false
        XCTAssertFalse(appState.showModelSelectionSheet, "Model selection sheet should be hidden after dismissing")
    }
    
    func testCommandHistorySheetFlow() {
        XCTAssertFalse(appState.showCommandHistorySheet, "Command history sheet should be hidden initially")
        
        appState.showCommandHistorySheet = true
        XCTAssertTrue(appState.showCommandHistorySheet, "Command history sheet should be visible after setting")
        
        let testCommand = CommandHistoryItem(
            id: UUID(),
            command: "ls -la",
            output: "test output",
            timestamp: Date(),
            isAIGenerated: false
        )
        appState.commandHistory.append(testCommand)
        XCTAssertEqual(appState.commandHistory.count, 1, "Command history should have one item")
        
        appState.showCommandHistorySheet = false
        XCTAssertFalse(appState.showCommandHistorySheet, "Command history sheet should be hidden after dismissing")
    }
    
    func testTabSelection() {
        XCTAssertEqual(appState.terminalTabs.count, 1, "Should start with one terminal tab")
        XCTAssertEqual(appState.selectedTabIndex, 0, "First tab should be selected")
        
        appState.addNewTab()
        XCTAssertEqual(appState.terminalTabs.count, 2, "Should have two tabs after adding")
        XCTAssertEqual(appState.selectedTabIndex, 1, "New tab should be selected")
        
        appState.closeTab(at: 1)
        XCTAssertEqual(appState.terminalTabs.count, 1, "Should have one tab after closing")
        XCTAssertEqual(appState.selectedTabIndex, 0, "First tab should be selected after closing")
    }
    
    // MARK: - AI Mode and Features Tests
    
    func testAIModeChanging() {
        XCTAssertEqual(appState.currentAIMode, .disabled, "AI Mode should start as disabled")
        
        appState.setAIMode(.auto)
        XCTAssertEqual(appState.currentAIMode, .auto, "AI Mode should be set to auto")
        
        appState.setAIMode(.code)
        XCTAssertEqual(appState.currentAIMode, .code, "AI Mode should be set to code")
        
        appState.setAIMode(.command)
        XCTAssertEqual(appState.currentAIMode, .command, "AI Mode should be set to command")
        
        appState.setAIMode(.dispatch)
        XCTAssertEqual(appState.currentAIMode, .dispatch, "AI Mode should be set to dispatch")
        
        XCTAssertTrue(appState.showAIPanel, "AI panel should be visible in active mode")
        
        appState.setAIMode(.disabled)
        XCTAssertFalse(appState.showAIPanel, "AI panel should be hidden in disabled mode")
        
        let testModel = AIModel(id: "test", name: "test", size: 1000, modified: Date())
        appState.selectedModel = testModel
        appState.setAIMode(.auto)
        XCTAssertTrue(appState.showAIPanel, "AI panel should show when mode enabled with model")
        
        appState.savePreferences()
        let newState = AppState()
        XCTAssertEqual(newState.currentAIMode, .auto, "AI mode should persist across app restarts")
    }
    
    func testAICommandSuggestionFlow() {
        // Setup test model
        let testModel = AIModel(
            id: "test-model",
            name: "CommandLlama",
            size: 1000,
            modified: Date(),
            capabilities: ModelCapabilities(isCommandOptimized: true)
        )
        appState.selectedModel = testModel
        
        // Enable command mode
        appState.setAIMode(.command)
        XCTAssertEqual(appState.currentAIMode, .command, "Should be in command mode")
        XCTAssertTrue(appState.showAIPanel, "AI panel should be visible")
        
        // Add test commands to history
        let aiCommand = CommandHistoryItem(
            id: UUID(),
            command: "ls -la",
            output: "test output",
            timestamp: Date(),
            isAIGenerated: true
        )
        appState.commandHistory.append(aiCommand)
        
        let userCommand = CommandHistoryItem(
            id: UUID(),
            command: "cd ..",
            output: "changed directory",
            timestamp: Date(),
            isAIGenerated: false
        )
        appState.commandHistory.append(userCommand)
        
        // Verify command history
        XCTAssertEqual(appState.commandHistory.count, 2, "Should have two commands in history")
        XCTAssertTrue(appState.commandHistory.first?.isAIGenerated ?? false, "First command should be AI generated")
        XCTAssertFalse(appState.commandHistory.last?.isAIGenerated ?? true, "Last command should be user generated")
    }
    
    // MARK: - Error Handling and Edge Cases
    
    func testModelLoadingErrors() {
        // Test missing model handling
        appState.setAIMode(.auto)
        XCTAssertEqual(appState.currentAIMode, .disabled, "Should remain disabled without model")
        
        // Test model switch during operation
        let model1 = AIModel(id: "test1", name: "test1", size: 1000, modified: Date())
        let model2 = AIModel(id: "test2", name: "test2", size: 1000, modified: Date())
        
        appState.selectedModel = model1
        appState.setAIMode(.auto)
        XCTAssertEqual(appState.currentAIMode, .auto, "Should enable with model1")
        
        // Switch model while active
        appState.selectedModel = model2
        XCTAssertEqual(appState.currentAIMode, .auto, "Should remain in auto mode after model switch")
        
        // Remove model while active
        appState.selectedModel = nil
        XCTAssertEqual(appState.currentAIMode, .disabled, "Should disable when model removed")
    }
    
    func testConcurrentOperations() {
        // Test rapid mode switching
        for _ in 0...10 {
            appState.setAIMode(.auto)
            appState.setAIMode(.disabled)
        }
        XCTAssertEqual(appState.currentAIMode, .disabled, "Should end up disabled after rapid switching")
        
        // Test multiple tab operations
        for _ in 0...5 {
            appState.addNewTab()
        }
        XCTAssertEqual(appState.terminalTabs.count, 7, "Should have correct number of tabs after rapid addition")
        
        // Close all tabs rapidly
        while !appState.terminalTabs.isEmpty {
            appState.closeTab(at: 0)
        }
        XCTAssertEqual(appState.terminalTabs.count, 1, "Should maintain minimum of one tab")
    }
    
    // MARK: - Helper Methods
    
    static var allTests = [
        // Basic UI interaction tests
        ("testModelSelectionSheetFlow", testModelSelectionSheetFlow),
        ("testCommandHistorySheetFlow", testCommandHistorySheetFlow),
        ("testTabSelection", testTabSelection),
        
        // AI mode and capability tests
        ("testAIModeChanging", testAIModeChanging),
        ("testAICommandSuggestionFlow", testAICommandSuggestionFlow),
        
        // Error handling and edge cases
        ("testModelLoadingErrors", testModelLoadingErrors),
        ("testConcurrentOperations", testConcurrentOperations)
    ]
}

