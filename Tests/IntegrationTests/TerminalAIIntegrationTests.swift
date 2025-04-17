import XCTest
@testable import App
@testable import TerminalCore
@testable import AIIntegration
@testable import UIComponents

final class TerminalAIIntegrationTests: XCTestCase {
    var appState: AppState!
    
    override func setUp() {
        super.setUp()
        appState = AppState()
        
        // Setup with some history and a terminal tab
        appState.addNewTab()
        
        // Add some test history
        addTestHistoryData()
    }
    
    override func tearDown() {
        appState = nil
        super.tearDown()
    }
    
    // Test the integration between terminal sessions and AI state
    func testTerminalAIStateIntegration() {
        // Initial state
        XCTAssertEqual(appState.currentAIMode, .disabled, "AI Mode should start as disabled")
        XCTAssertFalse(appState.showAIPanel, "AI Panel should initially be hidden")
        
        // Enable AI mode
        appState.setAIMode(.auto)
        XCTAssertEqual(appState.currentAIMode, .auto, "AI Mode should be set to auto")
        XCTAssertTrue(appState.showAIPanel, "AI Panel should be shown when AI mode is enabled")
        
        // Switch modes
        appState.setAIMode(.command)
        XCTAssertEqual(appState.currentAIMode, .command, "AI Mode should be changed to command")
        XCTAssertTrue(appState.showAIPanel, "AI Panel should remain shown when switching modes")
        
        // Disable AI
        appState.setAIMode(.disabled)
        XCTAssertEqual(appState.currentAIMode, .disabled, "AI Mode should be disabled")
    }
    
    // Test terminal tab management
    func testTerminalTabManagement() {
        // Start with one tab
        XCTAssertEqual(appState.terminalTabs.count, 1, "Should start with one terminal tab")
        
        // Add a new tab
        appState.addNewTab()
        XCTAssertEqual(appState.terminalTabs.count, 2, "Should have two terminal tabs")
        XCTAssertEqual(appState.selectedTabIndex, 1, "Second tab should be selected")
        
        // Close a tab
        appState.closeTab(at: 0)
        XCTAssertEqual(appState.terminalTabs.count, 1, "Should have one terminal tab")
        XCTAssertEqual(appState.selectedTabIndex, 0, "First tab should be selected")
        
        // Close all tabs - should auto-create a new one
        appState.closeTab(at: 0)
        XCTAssertEqual(appState.terminalTabs.count, 1, "Should have one terminal tab after closing all")
    }
    
    // Test theme and font preferences
    func testTerminalPreferences() {
        // Default preferences
        XCTAssertTrue(appState.isDarkMode, "Dark mode should be enabled by default")
        XCTAssertEqual(appState.fontSize, 12.0, "Default font size should be 12.0")
        
        // Change theme
        appState.toggleDarkMode()
        XCTAssertFalse(appState.isDarkMode, "Dark mode should be disabled after toggle")
        
        // Change font size
        appState.increaseFontSize()
        XCTAssertEqual(appState.fontSize, 13.0, "Font size should increase by 1")
        
        appState.decreaseFontSize()
        XCTAssertEqual(appState.fontSize, 12.0, "Font size should decrease by 1")
        
        // Reset font size
        appState.increaseFontSize()
        appState.increaseFontSize()
        appState.resetFontSize()
        XCTAssertEqual(appState.fontSize, 12.0, "Font size should reset to default")
    }
    
    // Test AIModel selection flow
    func testModelSelectionFlow() {
        // Add test models
        let model1 = AIModel(id: "test1", name: "Test Model 1", size: 1000, modified: Date())
        let model2 = AIModel(id: "test2", name: "Test Model 2", size: 2000, modified: Date(), 
                            capabilities: ModelCapabilities(isCodeCapable: true))
        
        appState.availableModels = [model1, model2]
        
        // No model selected initially
        XCTAssertNil(appState.selectedModel, "No model should be selected initially")
        
        // Select a model
        appState.selectedModel = model1
        XCTAssertEqual(appState.selectedModel?.id, "test1", "First model should be selected")
        
        // Switch models
        appState.selectedModel = model2
        XCTAssertEqual(appState.selectedModel?.id, "test2", "Second model should be selected")
        XCTAssertTrue(appState.selectedModel?.capabilities.isCodeCapable ?? false, "Selected model should have code capabilities")
        
        // Test model detection
        XCTAssertTrue(appState.isOllamaDetected, "Ollama should be detected when models are available")
    }
    
    // Test preferences saving and loading
    func testPreferencesPersistence() {
        // Change settings
        appState.setAIMode(.code)
        appState.toggleDarkMode() // Should be false now
        appState.increaseFontSize() // Should be 13.0 now
        
        // Save preferences
        appState.savePreferences()
        
        // Create a new AppState instance to simulate app restart
        let newAppState = AppState()
        
        // Set a brief delay to allow UserDefaults to reflect changes
        let expectation = XCTestExpectation(description: "Preferences loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Verify settings were loaded
            XCTAssertEqual(newAppState.currentAIMode, .code, "AI mode should persist")
            XCTAssertFalse(newAppState.isDarkMode, "Dark mode setting should persist")
            XCTAssertEqual(newAppState.fontSize, 13.0, "Font size should persist")
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // Add some test history data
    private func addTestHistoryData() {
        let commands = [
            CommandHistoryItem(id: UUID(), command: "ls -la", output: "total 16\ndrwxr-xr-x  8 user  staff  256 Apr 15 10:00 .", timestamp: Date(), isAIGenerated: false),
            CommandHistoryItem(id: UUID(), command: "git status", output: "On branch main\nYour branch is up to date", timestamp: Date(), isAIGenerated: false),
            CommandHistoryItem(id: UUID(), command: "find . -name \"*.swift\"", output: "./Sources/App/ContentView.swift", timestamp: Date(), isAIGenerated: true)
        ]
        
        appState.commandHistory = commands
    }
    
    static var allTests = [
        ("testTerminalAIStateIntegration", testTerminalAIStateIntegration),
        ("testTerminalTabManagement", testTerminalTabManagement),
        ("testTerminalPreferences", testTerminalPreferences),
        ("testModelSelectionFlow", testModelSelectionFlow),
        ("testPreferencesPersistence", testPreferencesPersistence),
    ]
}

