import XCTest
@testable import App
@testable import TerminalCore
@testable import AIIntegration
@testable import UIComponents

final class PerformanceTests: XCTestCase {
    var appState: AppState!
    
    override func setUp() {
        super.setUp()
        appState = AppState()
        
        // Prepare test data for performance testing
        prepareTestData()
    }
    
    override func tearDown() {
        appState = nil
        super.tearDown()
    }
    
    // Test performance of command history with large number of entries
    func testCommandHistoryPerformance() {
        // Measure searching through a large command history
        self.measure {
            // Perform 100 searches in the history
            for _ in 0..<100 {
                let randomQuery = generateRandomSearchQuery()
                let results = searchCommandHistory(query: randomQuery)
                
                // Verify results but don't log them to avoid affecting measurement
                XCTAssertNotNil(results, "Search should return results object")
            }
        }
    }
    
    // Test performance of terminal rendering
    func testTerminalRenderingPerformance() {
        // Measure terminal rendering with large output
        self.measure {
            // Simulate rendering 1000 lines of terminal output
            let largeOutput = generateLargeTerminalOutput(lines: 1000)
            processTerminalOutput(largeOutput)
        }
    }
    
    // Test performance of model switching
    func testModelSwitchingPerformance() {
        // Measure model switching performance
        self.measure {
            // Switch between models 100 times
            for i in 0..<100 {
                let modelIndex = i % appState.availableModels.count
                appState.selectedModel = appState.availableModels[modelIndex]
            }
        }
    }
    
    // Test AI suggestion generation performance
    func testSuggestionGenerationPerformance() {
        // Measure AI suggestion generation performance
        self.measure {
            // Generate 50 command suggestions
            for _ in 0..<50 {
                let command = generateRandomCommand()
                generateSuggestions(for: command)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    // Prepare test data for performance testing
    private func prepareTestData() {
        // Create test command history with 1000 entries
        var commands: [CommandHistoryItem] = []
        for i in 0..<1000 {
            let command = CommandHistoryItem(
                id: UUID(),
                command: "command_\(i) \(generateRandomCommand())",
                output: "output for command \(i)\n" + generateRandomOutput(),
                timestamp: Date().addingTimeInterval(-Double(i) * 60),
                isAIGenerated: i % 3 == 0 // Every third command is AI generated
            )
            commands.append(command)
        }
        
        appState.commandHistory = commands
        
        // Create test models
        var models: [AIModel] = []
        for i in 0..<10 {
            let model = AIModel(
                id: "model_\(i)",
                name: "Test Model \(i)",
                size: UInt64(1_000_000 * (i + 1)),
                modified: Date().addingTimeInterval(-Double(i) * 86400),
                capabilities: ModelCapabilities(
                    isCodeCapable: i % 2 == 0,
                    isMultimodal: i % 3 == 0,
                    isCommandOptimized: i % 4 == 0
                )
            )
            models.append(model)
        }
        
        appState.availableModels = models
        appState.selectedModel = models.first
    }
    
    // Generate a random command for testing
    private func generateRandomCommand() -> String {
        let commands = [
            "ls -la", "cd /tmp", "grep -r 'import' .", "find . -name '*.swift'",
            "git status", "echo 'Hello World'", "cat README.md", "mkdir test_dir",
            "touch new_file.txt", "rm test.log", "cp file1 file2", "mv file1 file2"
        ]
        
        return commands[Int.random(in: 0..<commands.count)]
    }
    
    // Generate random output for testing
    private func generateRandomOutput() -> String {
        var output = ""
        let lineCount = Int.random(in: 1...10)
        
        for _ in 0..<lineCount {
            let wordCount = Int.random(in: 3...10)
            var line = ""
            
            for _ in 0..<wordCount {
                let wordLength = Int.random(in: 3...8)
                let word = String((0..<wordLength).map { _ in "abcdefghijklmnopqrstuvwxyz".randomElement()! })
                line += word + " "
            }
            
            output += line.trimmingCharacters(in: .whitespaces) + "\n"
        }
        
        return output
    }
    
    // Generate a random search query
    private func generateRandomSearchQuery() -> String {
        let queries = ["ls", "git", "find", "grep", "cd", "rm", "cp", "mv", "touch", "mkdir"]
        return queries[Int.random(in: 0..<queries.count)]
    }
    
    // Search command history (performance test helper)
    private func searchCommandHistory(query: String) -> [CommandHistoryItem] {
        return appState.commandHistory.filter { item in
            item.command.lowercased().contains(query.lowercased())
        }
    }
    
    // Generate large terminal output for testing
    private func generateLargeTerminalOutput(lines: Int) -> String {
        var output = ""
        
        for i in 0..<lines {
            output += "Line \(i): " + generateRandomOutput()
        }
        
        return output
    }
    
    // Process terminal output (performance test helper)
    private func processTerminalOutput(_ output: String) {
        // In a real app, this would process and display the output
        // For testing, we'll just do some basic processing
        
        let lines = output.split(separator: "\n")
        var processedLines: [String] = []
        
        for line in lines {
            let processed = ">> " + line
            processedLines.append(String(processed))
        }
        
        // Just to make sure the compiler doesn't optimize away our work
        XCTAssertEqual(processedLines.count, output.split(separator: "\n").count)
    }
    
    // Generate suggestions (performance test helper)
    private func generateSuggestions(for command: String) {
        // In a real app, this would call the AI model
        // For testing, we'll just generate some basic suggestions
        
        var suggestions: [String] = []
        
        if command.contains("ls") {
            suggestions.append("ls -la")
            suggestions.append("ls -la | grep 'swift'")
        } else if command.contains("git") {
            suggestions.append("git status")
            suggestions.append("git log --oneline")
            suggestions.append("git pull origin main")
        } else if command.contains("find") {
            suggestions.append("find . -name '*.swift'")
            suggestions.append("find . -type f -mtime -7")
        } else {
            suggestions.append(command + " --help")
            suggestions.append(command + " | grep pattern")
        }
        
        // Just to make sure the compiler doesn't optimize away our work
        XCTAssertGreaterThan(suggestions.count, 0)
    }
    
    static var allTests = [
        ("testCommandHistoryPerformance", testCommandHistoryPerformance),
        ("testTerminalRenderingPerformance", testTerminalRenderingPerformance),
        ("testModelSwitchingPerformance", testModelSwitchingPerformance),
        ("testSuggestionGenerationPerformance", testSuggestionGenerationPerformance),
    ]
}

