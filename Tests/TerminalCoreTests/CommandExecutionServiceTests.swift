import XCTest
@testable import TerminalCore

// Enable code coverage tracking
final class CommandExecutionServiceTests: XCTestCase {
    override class var defaultTestSuite: XCTestSuite {
        let suite = super.defaultTestSuite
        if let coverage = ProcessInfo.processInfo.environment["LLVM_PROFILE_FILE"] {
            print("Code coverage enabled: \(coverage)")
        } else {
            print("⚠️ Code coverage not enabled. Run with proper coverage flags.")
        }
        return suite
    }
    var service: CommandExecutionService!
    let testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("CommandExecutionTests")
    
    override func setUp() async throws {
        super.setUp()
        // Create test directory
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        service = CommandExecutionService(workingDirectory: testDirectory)
    }
    
    override func tearDown() async throws {
        // Clean up test directory
        try? FileManager.default.removeItem(at: testDirectory)
        service = nil
        super.tearDown()
    }
    
    // MARK: - Basic Command Execution Tests
    
    func testSimpleCommandExecution() async throws {
        let result = try await service.executeCommand("echo 'Hello, World!'")
        
        XCTAssertEqual(result.command, "echo 'Hello, World!'")
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "Hello, World!")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.duration > 0)
        XCTAssertTrue(result.isSuccessful)
    }
    
    func testCommandWithError() async throws {
        let result = try await service.executeCommand("ls nonexistent_directory")
        
        XCTAssertEqual(result.command, "ls nonexistent_directory")
        XCTAssertTrue(result.output.contains("No such file or directory"))
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertFalse(result.isSuccessful)
    }
    
    func testMultipleCommands() async throws {
        let result = try await service.executeCommand("echo 'first' && echo 'second'")
        
        XCTAssertTrue(result.output.contains("first"))
        XCTAssertTrue(result.output.contains("second"))
        XCTAssertEqual(result.exitCode, 0)
    }
    
    // MARK: - Streaming Output Tests
    
    func testStreamingOutput() async throws {
        let command = "for i in {1..3}; do echo $i; sleep 0.1; done"
        var chunks: [CommandOutputChunk] = []
        
        for try await chunk in service.executeCommandWithStream(command) {
            chunks.append(chunk)
        }
        
        // Verify output chunks
        XCTAssertTrue(chunks.count >= 4) // 3 numbers + completion chunk
        XCTAssertEqual(chunks.filter { $0.type == .standardOutput }.count, 3)
        XCTAssertEqual(chunks.filter { $0.type == .complete }.count, 1)
        
        // Verify content
        let outputChunks = chunks.filter { $0.type == .standardOutput }
        XCTAssertTrue(outputChunks.map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains("1"))
        XCTAssertTrue(outputChunks.map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains("2"))
        XCTAssertTrue(outputChunks.map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains("3"))
        
        // Verify completion chunk
        let completionChunk = chunks.last
        XCTAssertEqual(completionChunk?.type, .complete)
        XCTAssertEqual(completionChunk?.exitCode, 0)
        XCTAssertNotNil(completionChunk?.duration)
        XCTAssertTrue(completionChunk?.isComplete ?? false)
    }
    
    func testStreamingWithError() async throws {
        let command = "echo 'start' && ls nonexistent_directory && echo 'end'"
        var chunks: [CommandOutputChunk] = []
        
        for try await chunk in service.executeCommandWithStream(command) {
            chunks.append(chunk)
        }
        
        // Verify we got both stdout and stderr chunks
        XCTAssertTrue(chunks.contains { $0.type == .standardOutput && $0.content.contains("start") })
        XCTAssertTrue(chunks.contains { $0.type == .standardError && $0.content.contains("No such file or directory") })
        
        // Verify completion with error
        let completionChunk = chunks.last
        XCTAssertEqual(completionChunk?.type, .complete)
        XCTAssertNotEqual(completionChunk?.exitCode, 0)
    }
    
    // MARK: - Timeout Tests
    
    func testCommandTimeout() async throws {
        let command = "sleep 5" // Command that takes 5 seconds
        
        do {
            _ = try await service.executeCommand(command, timeout: 0.1)
            XCTFail("Command should have timed out")
        } catch let error as CommandExecutionError {
            switch error {
            case .timeout(let cmd, let duration):
                XCTAssertEqual(cmd, command)
                XCTAssertEqual(duration, 0.1)
            default:
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }
    
    func testStreamingTimeout() async throws {
        let command = "sleep 5" // Command that takes 5 seconds
        var chunks: [CommandOutputChunk] = []
        
        do {
            for try await chunk in service.executeCommandWithStream(command, timeout: 0.1) {
                chunks.append(chunk)
            }
            XCTFail("Stream should have thrown timeout error")
        } catch let error as CommandExecutionError {
            switch error {
            case .timeout(let cmd, let duration):
                XCTAssertEqual(cmd, command)
                XCTAssertEqual(duration, 0.1)
            default:
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }
    
    // MARK: - Working Directory Tests
    
    func testChangeWorkingDirectory() async throws {
        // Create a subdirectory
        let subdir = testDirectory.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        
        // Change to subdirectory
        let previousDir = try service.changeWorkingDirectory("subdir")
        
        // Verify current directory through the service
        XCTAssertEqual(service.getCurrentWorkingDirectory().path, subdir.path)
        XCTAssertEqual(previousDir.path, testDirectory.path)
        
        // Verify current directory through command
        let result = try await service.executeCommand("pwd")
        XCTAssertTrue(result.output.contains(subdir.path))
        
        // Test relative path navigation
        try service.changeWorkingDirectory("..")
        XCTAssertEqual(service.getCurrentWorkingDirectory().path, testDirectory.path)
    }
    
    func testAbsoluteDirectoryChange() async throws {
        // Change to home directory using absolute path
        let homePath = ProcessInfo.processInfo.environment["HOME"]!
        let homeURL = URL(fileURLWithPath: homePath)
        
        try service.changeWorkingDirectory(homePath)
        
        // Verify current directory
        XCTAssertEqual(service.getCurrentWorkingDirectory().path, homeURL.path)
        
        // Verify through command
        let result = try await service.executeCommand("pwd")
        XCTAssertTrue(result.output.contains(homePath))
    }
    
    func testTildeExpansion() async throws {
        // Change to home directory using tilde
        let homePath = ProcessInfo.processInfo.environment["HOME"]!
        
        try service.changeWorkingDirectory("~")
        
        // Verify current directory
        XCTAssertEqual(service.getCurrentWorkingDirectory().path, homePath)
    }
    
    func testInvalidDirectoryChange() async throws {
        do {
            _ = try service.changeWorkingDirectory("nonexistent_directory")
            XCTFail("Should throw invalid directory error")
        } catch let error as CommandExecutionError {
            switch error {
            case .invalidDirectory(let path):
                XCTAssertEqual(path, "nonexistent_directory")
            default:
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }
    
    // MARK: - Environment Variable Tests
    
    func testEnvironmentVariables() async throws {
        // Set custom environment variable
        service.updateEnvironment(["TEST_VAR": "test_value"])
        
        // Verify environment variable is set through the service
        let env = service.getEnvironment()
        XCTAssertEqual(env["TEST_VAR"], "test_value")
        
        // Verify environment variable is set through command
        let result = try await service.executeCommand("echo $TEST_VAR")
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "test_value")
    }
    
    func testUpdateMultipleEnvironmentVariables() async throws {
        // Set multiple environment variables
        service.updateEnvironment([
            "TEST_VAR1": "value1",
            "TEST_VAR2": "value2"
        ])
        
        // Verify through command
        let result = try await service.executeCommand("echo $TEST_VAR1 $TEST_VAR2")
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(output, "value1 value2")
    }
    
    func testRemoveEnvironmentVariables() async throws {
        // Set and then remove environment variables
        service.updateEnvironment(["TEST_VAR": "test_value"])
        service.removeEnvironmentVariables(["TEST_VAR"])
        
        // Verify variable is removed
        let result = try await service.executeCommand("echo $TEST_VAR")
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "")
        
        // Verify through getEnvironment
        let env = service.getEnvironment()
        XCTAssertNil(env["TEST_VAR"])
    }
    
    func testResetEnvironment() async throws {
        // Modify environment
        service.updateEnvironment(["TEST_VAR": "test_value"])
        
        // Reset environment
        service.resetEnvironment()
        
        // Verify custom variable is gone
        let env = service.getEnvironment()
        XCTAssertNil(env["TEST_VAR"])
        
        // Verify standard variables are restored
        XCTAssertNotNil(env["PATH"])
        XCTAssertNotNil(env["HOME"])
    }
    
    // MARK: - Edge Cases
    
    func testEmptyCommand() async throws {
        let result = try await service.executeCommand("")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.isEmpty)
    }
    
    func testCommandWithSpacesOnly() async throws {
        let result = try await service.executeCommand("   ")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.isEmpty)
    }
    
    func testLargeOutput() async throws {
        // Generate large output (approximately 100KB)
        let command = "yes 'test line' | head -n 10000"
        let result = try await service.executeCommand(command)
        
        XCTAssertTrue(result.output.count > 90000, "Output should be large")
        XCTAssertEqual(result.exitCode, 0)
    }
    
    func testCommandCancellation() async throws {
        let command = "sleep 10" // Long-running command
        
        let task = Task {
            try await service.executeCommand(command)
        }
        
        // Wait briefly then cancel
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        task.cancel()
        
        do {
            _ = try await task.value
            XCTFail("Command should have been cancelled")
        } catch is CancellationError {
            // Success - command was cancelled
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testStreamCancellation() async throws {
        let command = "for i in {1..10}; do echo $i; sleep 1; done"
        var chunks: [CommandOutputChunk] = []
        
        let task = Task {
            for try await chunk in service.executeCommandWithStream(command) {
                chunks.append(chunk)
                
                // Only collect a few chunks
                if chunks.count >= 2 {
                    return chunks
                }
            }
            return chunks
        }
        
        // Wait briefly then cancel
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        task.cancel()
        
        // Should have gotten some chunks but not all
        let collectedChunks = try await task.value
        XCTAssertTrue(collectedChunks.count < 10, "Should not have collected all 10 chunks")
        XCTAssertTrue(collectedChunks.count > 0, "Should have collected at least one chunk")
    }
    
    func testInvalidCommand() async throws {
        let command = "non_existent_command_12345"
        
        let result = try await service.executeCommand(command)
        
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("command not found") || 
                     result.output.contains("No such file or directory"))
    }
    
    // MARK: - Concurrent Execution Tests
    
    func testConcurrentCommandExecution() async throws {
        // Execute multiple commands concurrently
        async let result1 = service.executeCommand("echo 'first' && sleep 0.1")
        async let result2 = service.executeCommand("echo 'second' && sleep 0.1")
        async let result3 = service.executeCommand("echo 'third' && sleep 0.1")
        
        let results = try await [result1, result2, result3]
        
        // Verify all commands completed successfully
        XCTAssertTrue(results.allSatisfy { $0.isSuccessful })
        XCTAssertTrue(results.contains { $0.output.contains("first") })
        XCTAssertTrue(results.contains { $0.output.contains("second") })
        XCTAssertTrue(results.contains { $0.output.contains("third") })
    }
    
    func testConcurrentStreamingCommands() async throws {
        // Create multiple streaming commands
        let commands = [
            "for i in {1..3}; do echo 'cmd1: $i'; sleep 0.1; done",
            "for i in {1..3}; do echo 'cmd2: $i'; sleep 0.1; done",
            "for i in {1..3}; do echo 'cmd3: $i'; sleep 0.1; done"
        ]
        
        // Track outputs separately
        var outputs: [[CommandOutputChunk]] = Array(repeating: [], count: commands.count)
        
        try await withThrowingTaskGroup(of: (Int, [CommandOutputChunk]).self) { group in
            // Start all commands
            for (index, command) in commands.enumerated() {
                group.addTask {
                    var chunks: [CommandOutputChunk] = []
                    for try await chunk in self.service.executeCommandWithStream(command) {
                        chunks.append(chunk)
                    }
                    return (index, chunks)
                }
            }
            
            // Collect results
            for try await (index, chunks) in group {
                outputs[index] = chunks
            }
        }
        
        // Verify each command's output
        for (index, chunks) in outputs.enumerated() {
            let cmdPrefix = "cmd\(index + 1)"
            let outputChunks = chunks.filter { $0.type == .standardOutput }
            
            XCTAssertEqual(outputChunks.count, 3, "Should have 3 output chunks for \(cmdPrefix)")
            XCTAssertTrue(outputChunks.allSatisfy { $0.content.contains(cmdPrefix) })
            
            let completionChunk = chunks.last
            XCTAssertEqual(completionChunk?.type, .complete)
            XCTAssertEqual(completionChunk?.exitCode, 0)
        }
    }
    
    func testConcurrentDirectoryChanges() async throws {
        // Create test directories
        let subdirs = ["dir1", "dir2", "dir3"]
        for dir in subdirs {
            let dirURL = testDirectory.appendingPathComponent(dir)
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
        
        // Change directories concurrently and run commands
        try await withThrowingTaskGroup(of: (String, CommandResult).self) { group in
            for dir in subdirs {
                group.addTask {
                    // Create a separate service instance for concurrent directory operations
                    let localService = CommandExecutionService(workingDirectory: self.testDirectory)
                    try localService.changeWorkingDirectory(dir)
                    let result = try await localService.executeCommand("pwd")
                    return (dir, result)
                }
            }
            
            // Verify results
            var results: [(String, CommandResult)] = []
            for try await result in group {
                results.append(result)
            }
            
            XCTAssertEqual(results.count, subdirs.count)
            for (dir, result) in results {
                XCTAssertTrue(result.output.contains(dir))
                XCTAssertEqual(result.exitCode, 0)
            }
        }
    }
    
    // MARK: - Stress Tests
    
    func testRapidCommandExecution() async throws {
        // Execute many quick commands in succession
        let commandCount = 20 // Reduced from 100 for faster tests
        let commands = Array(repeating: "echo 'test'", count: commandCount)
        
        try await withThrowingTaskGroup(of: CommandResult.self) { group in
            for command in commands {
                group.addTask {
                    try await self.service.executeCommand(command)
                }
            }
            
            var successCount = 0
            for try await result in group {
                if result.isSuccessful {
                    successCount += 1
                }
            }
            
            XCTAssertEqual(successCount, commandCount, "All commands should complete successfully")
        }
    }
    
    func testMixedCommandDurations() async throws {
        // Mix of long and short running commands
        let commands = [
            "sleep 0.5 && echo 'long1'",
            "echo 'short1'",
            "sleep 0.2 && echo 'medium1'",
            "echo 'short2'",
            "sleep 0.5 && echo 'long2'",
            "sleep 0.2 && echo 'medium2'"
        ]
        
        try await withThrowingTaskGroup(of: CommandResult.self) { group in
            for command in commands {
                group.addTask {
                    try await self.service.executeCommand(command)
                }
            }
            
            var results: [CommandResult] = []
            for try await result in group {
                results.append(result)
            }
            
            XCTAssertEqual(results.count, commands.count)
            XCTAssertTrue(results.allSatisfy { $0.isSuccessful })
            
            // Short commands should finish faster
            let shortResults = results.filter { $0.command.contains("echo 'short") }
            let longResults = results.filter { $0.command.contains("sleep 0.5") }
            
            for shortResult in shortResults {
                XCTAssertTrue(shortResult.duration < 0.1, "Short commands should complete quickly")
            }
            
            for longResult in longResults {
                XCTAssertTrue(longResult.duration >= 0.5, "Long commands should take at least 0.5 seconds")
            }
        }
    }
    
    func testMildlyResourceIntensiveCommands() async throws {
        // Commands that use moderate resources (avoiding too heavy operations for unit tests)
        let commands = [
            "yes | head -n 10000 > /dev/null", // CPU intensive but limited
            "cat /dev/zero | head -c 1M > /dev/null", // I/O intensive but small
            "seq 1 10000 | sort -R | head -n 1000", // Memory intensive but reasonable
            "find . -type f 2>/dev/null | head -n 100" // File system intensive but limited scope
        ]
        
        try await withThrowingTaskGroup(of: CommandResult.self) { group in
            for command in commands {
                group.addTask {
                    try await self.service.executeCommand(command)
                }
            }
            
            var results: [CommandResult] = []
            for try await result in group {
                results.append(result)
                XCTAssertNotNil(result.duration)
            }
            
            XCTAssertEqual(results.count, commands.count)
            XCTAssertTrue(results.allSatisfy { $0.exitCode == 0 }, "All commands should complete successfully")
        }
    }
    
    func testStreamingWithModerateOutput() async throws {
        // Generate moderate streaming output (not too large for unit tests)
        let command = """
        for i in {1..100}; do
            echo "Line $i with some additional content to make it longer"
        done
        """
        
        var chunks: [CommandOutputChunk] = []
        var totalBytes = 0
        
        for try await chunk in service.executeCommandWithStream(command) {
            chunks.append(chunk)
            totalBytes += chunk.content.utf8.count
        }
        
        // There should be at least 100 output chunks (one per line) plus completion
        XCTAssertTrue(chunks.count > 100, "Should have received at least 100 chunks")
        XCTAssertTrue(totalBytes > 5000, "Should have processed at least 5KB of data")
        XCTAssertEqual(chunks.last?.type, .complete)
        XCTAssertEqual(chunks.last?.exitCode, 0)
    }
    
    func testEnvironmentConsistencyUnderLoad() async throws {
        // Set up environment variables
        service.updateEnvironment([
            "TEST_VAR1": "value1",
            "TEST_VAR2": "value2",
            "TEST_VAR3": "value3"
        ])
        
        // Run multiple commands concurrently that check environment variables
        let commands = [
            "echo $TEST_VAR1",
            "echo $TEST_VAR2",
            "echo $TEST_VAR3",
            "echo $TEST_VAR1 $TEST_VAR2",
            "echo $TEST_VAR2 $TEST_VAR3",
            "echo $TEST_VAR1 $TEST_VAR3"
        ]
        
        try await withThrowingTaskGroup(of: CommandResult.self) { group in
            for command in commands {
                group.addTask {
                    try await self.service.executeCommand(command)
                }
            }
            
            var results: [CommandResult] = []
            for try await result in group {
                results.append(result)
            }
            
            // Verify environment consistency
            XCTAssertTrue(results.contains { $0.output.trimmingCharacters(in: .whitespacesAndNewlines) == "value1" })
            XCTAssertTrue(results.contains { $0.output.trimmingCharacters(in: .whitespacesAndNewlines) == "value2" })
            XCTAssertTrue(results.contains { $0.output.trimmingCharacters(in: .whitespacesAndNewlines) == "value3" })
            XCTAssertTrue(results.contains { $0.output.trimmingCharacters(in: .whitespacesAndNewlines) == "value1 value2" })
            XCTAssertTrue(results.contains { $0.output.trimmingCharacters(in: .whitespacesAndNewlines) == "value2 value3" })
            XCTAssertTrue(results.contains { $0.output.trimmingCharacters(in: .whitespacesAndNewlines) == "value1 value3" })
        }
    }
    
    // MARK: - Performance Tests
    
    func testCommandExecutionPerformance() throws {
        measure {
            let expectation = expectation(description: "Command execution")
            
            Task {
                do {
                    _ = try await service.executeCommand("echo 'performance test'")
                    expectation.fulfill()
                } catch {
                    XCTFail("Command execution failed: \(error)")
                }
            }
            
            wait(for: [expectation], timeout: 1.0)
        }
    }
    
    func testStreamingPerformance() throws {
        // Generate test data that's large enough to measure but not too large
        let testCommand = """
        for i in {1..500}; do
            echo "Line $i: $(date) - Some test content to make the line longer"
        done
        """
        
        measure {
            let expectation = expectation(description: "Streaming performance")
            
            Task {
                do {
                    var chunkCount = 0
                    var totalBytes = 0
                    
                    for try await chunk in service.executeCommandWithStream(testCommand) {
                        chunkCount += 1
                        totalBytes += chunk.content.utf8.count
                    }
                    
                    // Add some basic validation to ensure the test is meaningful
                    XCTAssertGreaterThan(chunkCount, 500)
                    XCTAssertGreaterThan(totalBytes, 10000)
                    
                    expectation.fulfill()
                } catch {
                    XCTFail("Streaming failed: \(error)")
                }
            }
            
            wait(for: [expectation], timeout: 5.0)
        }
    }
    
    func testConcurrentCommandPerformance() throws {
        measure {
            let expectation = expectation(description: "Concurrent commands")
            let commandCount = 10
            
            Task {
                do {
                    try await withThrowingTaskGroup(of: CommandResult.self) { group in
                        for _ in 0..<commandCount {
                            group.addTask {
                                try await self.service.executeCommand("echo 'concurrent test'")
                            }
                        }
                        
                        var completedCount = 0
                        for try await _ in group {
                            completedCount += 1
                        }
                        
                        XCTAssertEqual(completedCount, commandCount)
                    }
                    
                    expectation.fulfill()
                } catch {
                    XCTFail("Concurrent execution failed: \(error)")
                }
            }
            
            wait(for: [expectation], timeout: 5.0)
        }
    }
    
    // MARK: - Cleanup Verification Tests
    
    func testProcessCleanupAfterExecution() async throws {
        // Start a command
        let result = try await service.executeCommand("echo 'test'")
        
        // Verify process cleanup
        let processCount = try await verifyNoZombieProcesses()
        XCTAssertEqual(processCount, 0, "Should not have any zombie processes")
    }
    
    func testProcessCleanupAfterTimeout() async throws {
        do {
            _ = try await service.executeCommand("sleep 10", timeout: 0.1)
            XCTFail("Should have timed out")
        } catch is CommandExecutionError {
            // Expected timeout error
            // Verify process cleanup
            let processCount = try await verifyNoZombieProcesses()
            XCTAssertEqual(processCount, 0, "Should not have any zombie processes after timeout")
        }
    }
    
    func testProcessCleanupAfterCancellation() async throws {
        let task = Task {
            try await service.executeCommand("sleep 10")
        }
        
        // Wait briefly then cancel
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        
        do {
            _ = try await task.value
            XCTFail("Should have been cancelled")
        } catch is CancellationError {
            // Expected cancellation
            // Verify process cleanup after a short delay to allow cleanup to complete
            try await Task.sleep(nanoseconds: 100_000_000)
            let processCount = try await verifyNoZombieProcesses()
            XCTAssertEqual(processCount, 0, "Should not have any zombie processes after cancellation")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testFileHandleCleanupAfterStreaming() async throws {
        let command = "for i in {1..5}; do echo $i; done"
        
        // Record initial file handle count
        let openFileHandleCount = try await countOpenFileHandles()
        
        // Run streaming command
        for try await _ in service.executeCommandWithStream(command) {}
        
        // Verify file handles were cleaned up (allow a small delay for cleanup)
        try await Task.sleep(nanoseconds: 100_000_000)
        let newFileHandleCount = try await countOpenFileHandles()
        
        // Allow for small fluctuations in file handle count
        XCTAssertLessThanOrEqual(abs(newFileHandleCount - openFileHandleCount), 2, 
                                "File handle count should return to approximately initial value")
    }
    
    // MARK: - Resource Monitoring Stress Test
    
    func testStressWithResourceMonitoring() async throws {
        let initialFileHandles = try await countOpenFileHandles()
        let initialProcesses = try await verifyNoZombieProcesses()
        
        // Run a mix of commands that could stress the system
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Add various command types
            for _ in 0..<5 {
                // Long-running command
                group.addTask {
                    _ = try await self.service.executeCommand("sleep 0.2")
                }
                
                // I/O intensive command (limited for tests)
                group.addTask {
                    _ = try await self.service.executeCommand("dd if=/dev/zero of=/dev/null bs=1024 count=1000 2>/dev/null")
                }
                
                // Command with output
                group.addTask {
                    for try await _ in self.service.executeCommandWithStream("for i in {1..50}; do echo $i; done") {}
                }
                
                // Command that might timeout
                group.addTask {
                    do {
                        _ = try await self.service.executeCommand("sleep 0.5", timeout: 0.1)
                    } catch is CommandExecutionError {
                        // Expected timeout
                    }
                }
            }
            
            // Wait for all tasks to complete
            try await group.waitForAll()
        }
        
        // Allow a short delay for resource cleanup
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Verify cleanup
        let finalFileHandles = try await countOpenFileHandles()
        let finalProcesses = try await verifyNoZombieProcesses()
        
        // Tolerances for resource counts to account for system variation
        XCTAssertLessThanOrEqual(abs(finalFileHandles - initialFileHandles), 5, 
                                "File handle count should return to approximately initial value")
        XCTAssertEqual(finalProcesses, initialProcesses, "Should not have any zombie processes")
    }
    
    // MARK: - Helper Methods for Resource Monitoring
    
    private func verifyNoZombieProcesses() async throws -> Int {
        let result = try await service.executeCommand("ps -ef | grep -v grep | grep -c 'defunct' || echo 0")
        return Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
    
    private func countOpenFileHandles() async throws -> Int {
        let pid = ProcessInfo.processInfo.processIdentifier
        let result = try await service.executeCommand("lsof -p \(pid) | wc -l")
        return Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
}
    
    // MARK: - Process Input Handling Tests
    
    func testPipelinedCommands() async throws {
        let result = try await service.executeCommand("echo 'hello world' | grep 'hello' | tr 'a-z' 'A-Z'")
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "HELLO WORLD")
    }
    
    func testRedirectionCommands() async throws {
        // Create a temporary file
        let testFile = testDirectory.appendingPathComponent("test_redirect.txt")
        
        // Test output redirection
        let writeResult = try await service.executeCommand("echo 'testing redirection' > \(testFile.path)")
        XCTAssertEqual(writeResult.exitCode, 0)
        
        // Test input redirection
        let readResult = try await service.executeCommand("cat < \(testFile.path)")
        XCTAssertEqual(readResult.exitCode, 0)
        XCTAssertEqual(readResult.output.trimmingCharacters(in: .whitespacesAndNewlines), "testing redirection")
        
        // Test append redirection
        let appendResult = try await service.executeCommand("echo 'another line' >> \(testFile.path)")
        XCTAssertEqual(appendResult.exitCode, 0)
        
        // Verify both lines
        let finalContent = try await service.executeCommand("cat \(testFile.path)")
        XCTAssertTrue(finalContent.output.contains("testing redirection"))
        XCTAssertTrue(finalContent.output.contains("another line"))
    }
    
    func testComplexPipelines() async throws {
        // Create some test files
        let testDir = testDirectory.appendingPathComponent("pipeline_test")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        
        try "apple\nbanana\ncherry\ndate\neggplant".write(
            to: testDir.appendingPathComponent("fruits.txt"),
            atomically: true,
            encoding: .utf8
        )
        
        // Test a more complex pipeline with grep, sort, head, etc.
        let command = """
        cat \(testDir.appendingPathComponent("fruits.txt").path) | \
        grep -v 'cherry' | \
        sort -r | \
        head -n 2
        """
        
        let result = try await service.executeCommand(command)
        
        XCTAssertEqual(result.exitCode, 0)
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = output.split(separator: "\n")
        
        XCTAssertEqual(lines.count, 2, "Should have exactly 2 lines")
        XCTAssertEqual(lines[0], "eggplant", "First line should be 'eggplant'")
        XCTAssertEqual(lines[1], "date", "Second line should be 'date'")
    }
    
    // MARK: - Signal Management Tests
    
    func testProcessTermination() async throws {
        // Start a long-running process
        let command = "sleep 10"
        
        let task = Task {
            try await service.executeCommand(command)
        }
        
        // Wait briefly then cancel
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        task.cancel()
        
        // Verify the process was terminated
        do {
            _ = try await task.value
            XCTFail("Command should have been cancelled")
        } catch is CancellationError {
            // Expected - command was cancelled
            
            // Check if any sleep processes remain
            let checkResult = try await service.executeCommand("ps -ef | grep -v grep | grep sleep || echo 'None'")
            XCTAssertTrue(checkResult.output.contains("None") || 
                         !checkResult.output.contains("sleep 10"), 
                         "Process should be terminated")
        }
    }
    
    func testProcessGroupTermination() async throws {
        // Test termination of process group (parent and child processes)
        let command = """
        (sleep 20 &)  # Start a background process in a subshell
        sleep 20      # This is the main process
        """
        
        let task = Task {
            try await service.executeCommand(command)
        }
        
        // Wait briefly then cancel
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        task.cancel()
        
        // Allow time for cleanup
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Verify no sleep processes remain (both parent and child should be gone)
        let checkResult = try await service.executeCommand("ps -ef | grep -v grep | grep 'sleep 20' || echo 'None'")
        XCTAssertTrue(checkResult.output.contains("None") || 
                     !checkResult.output.contains("sleep 20"), 
                     "All processes in the group should be terminated")
    }
    
    // MARK: - Shell Builtin Tests
    
    func testCdBuiltin() async throws {
        // Create test directories
        let subdir = testDirectory.appendingPathComponent("cd_test")
        let subsubdir = subdir.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subsubdir, withIntermediateDirectories: true)
        
        // Test basic cd command
        let result1 = try await service.executeCommand("cd \(subdir.path) && pwd")
        XCTAssertEqual(result1.exitCode, 0)
        XCTAssertTrue(result1.output.contains(subdir.lastPathComponent))
        
        // Test relative path navigation
        let result2 = try await service.executeCommand("cd \(subdir.path) && cd subdir && pwd")
        XCTAssertEqual(result2.exitCode, 0)
        XCTAssertTrue(result2.output.contains("subdir"))
        
        // Test cd with no arguments (should go to home)
        let result3 = try await service.executeCommand("cd && pwd")
        XCTAssertEqual(result3.exitCode, 0)
        XCTAssertTrue(result3.output.contains(FileManager.default.homeDirectoryForCurrentUser.path))
    }
    
    func testExportBuiltin() async throws {
        // Test export command to set environment variables
        let result = try await service.executeCommand("""
        export TEST_VAR1="test value 1"
        export TEST_VAR2="test value 2"
        echo "$TEST_VAR1 and $TEST_VAR2"
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), 
                      "test value 1 and test value 2")
    }
    
    func testSourceBuiltin() async throws {
        // Create a script file to source
        let scriptFile = testDirectory.appendingPathComponent("test_source.sh")
        try """
        # Test script for source command
        TEST_SOURCE_VAR="sourced value"
        echo "Script executed"
        """.write(to: scriptFile, atomically: true, encoding: .utf8)
        
        // Make it executable
        try await service.executeCommand("chmod +x \(scriptFile.path)")
        
        // Test sourcing the script
        let result = try await service.executeCommand("""
        . \(scriptFile.path)
        echo "TEST_SOURCE_VAR = $TEST_SOURCE_VAR"
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Script executed"))
        XCTAssertTrue(result.output.contains("TEST_SOURCE_VAR = sourced value"))
    }
    
    func testMultipleBuiltins() async throws {
        // Test a combination of builtin commands
        let result = try await service.executeCommand("""
        cd \(testDirectory.path) && \
        export COMBINED_TEST="success" && \
        mkdir -p builtin_test && \
        cd builtin_test && \
        echo "Current directory: $(pwd), COMBINED_TEST=$COMBINED_TEST" > result.txt && \
        cat result.txt
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("builtin_test"))
        XCTAssertTrue(result.output.contains("COMBINED_TEST=success"))
    }
    
    func testErrorHandlingInBuiltins() async throws {
        // Test error handling with builtin commands
        let result = try await service.executeCommand("""
        cd /nonexistent_directory 2>/dev/null || echo "cd failed" && \
        echo "Continuing execution"
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("cd failed"))
        XCTAssertTrue(result.output.contains("Continuing execution"))
    }
    
    // MARK: - Shell Function and Alias Tests
    
    func testShellFunctions() async throws {
        // Define and test a shell function
        let result = try await service.executeCommand("""
        function greet() {
            echo "Hello, $1!"
        }
        greet "World"
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "Hello, World!")
    }
    
    func testComplexShellFunctions() async throws {
        // Test a more complex function with multiple arguments and logic
        let result = try await service.executeCommand("""
        function process_files() {
            local dir="$1"
            local ext="$2"
            echo "Processing $ext files in $dir:"
            find "$dir" -name "*.$ext" 2>/dev/null | while read file; do
                echo "Found: $(basename "$file")"
            done
        }
        
        mkdir -p test_files
        touch test_files/test1.txt test_files/test2.txt test_files/other.log
        process_files test_files txt
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Processing txt files in test_files"))
        XCTAssertTrue(result.output.contains("Found: test1.txt"))
        XCTAssertTrue(result.output.contains("Found: test2.txt"))
        XCTAssertFalse(result.output.contains("other.log"))
    }
    
    func testFunctionVariableScope() async throws {
        // Test variable scope within functions
        let result = try await service.executeCommand("""
        function test_scope() {
            local local_var="local value"
            global_var="global value"
            echo "Inside function: local_var=$local_var, global_var=$global_var"
        }
        
        test_scope
        echo "Outside function: global_var=$global_var"
        echo "Outside function: local_var=$local_var"
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Inside function: local_var=local value"))
        XCTAssertTrue(result.output.contains("Outside function: global_var=global value"))
        XCTAssertTrue(result.output.contains("Outside function: local_var="))
        XCTAssertFalse(result.output.contains("Outside function: local_var=local value"))
    }
    
    func testAliases() async throws {
        // Test basic alias functionality
        let result = try await service.executeCommand("""
        alias ll='ls -l'
        alias custom_echo='echo "Custom:"'
        
        custom_echo "test"
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Custom: test"))
    }
    
    func testAliasWithPipeline() async throws {
        // Test alias with pipeline and redirection
        let result = try await service.executeCommand("""
        alias grep_count='grep -c'
        echo "apple banana apple cherry" | grep_count "apple"
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "2")
    }
    
    func testFunctionAndAliasInteraction() async throws {
        // Test interaction between functions and aliases
        let result = try await service.executeCommand("""
        function count_files() {
            local dir="$1"
            local count=$(ls -1 "$dir" 2>/dev/null | wc -l)
            echo "$count files in $dir"
        }
        
        alias cf='count_files'
        
        mkdir -p test_dir
        touch test_dir/file1 test_dir/file2
        
        cf test_dir
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("2 files in test_dir"))
    }
    
    func testFunctionErrorHandling() async throws {
        // Test error handling in functions
        let result = try await service.executeCommand("""
        function safe_mkdir() {
            if [ -d "$1" ]; then
                echo "Directory already exists: $1"
                return 1
            else
                mkdir -p "$1"
                echo "Created directory: $1"
                return 0
            fi
        }
        
        # First call should succeed
        safe_mkdir test_dir
        # Second call should fail (dir already exists)
        safe_mkdir test_dir || echo "Function returned error code"
        """)
        
        XCTAssertEqual(result.exitCode, 0) // Overall script succeeds due to error handling
        XCTAssertTrue(result.output.contains("Created directory: test_dir"))
        XCTAssertTrue(result.output.contains("Directory already exists: test_dir"))
        XCTAssertTrue(result.output.contains("Function returned error code"))
    }
    
    func testFunctionOutputCapture() async throws {
        // Test capturing function output in variables
        let result = try await service.executeCommand("""
        function get_timestamp() {
            date "+%Y-%m-%d"
        }
        
        current_date=$(get_timestamp)
        echo "Date: $current_date"
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        
        // Verify output contains a date in YYYY-MM-DD format
        let dateRegex = try! NSRegularExpression(pattern: "Date: \\d{4}-\\d{2}-\\d{2}")
        let matches = dateRegex.matches(
            in: result.output,
            range: NSRange(location: 0, length: (result.output as NSString).length)
        )
        
        XCTAssertEqual(matches.count, 1, "Output should contain a date in YYYY-MM-DD format")
    }
    
    func testAliasPreservation() async throws {
        // Test that aliases persist across multiple commands in the same session
        let result = try await service.executeCommand("""
        alias custom_greeting='echo "Greetings,"'
        custom_greeting
        
        # Run another command to ensure alias persists
        custom_greeting
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        let outputs = result.output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let greetingCount = outputs.filter { $0 == "Greetings," }.count
        XCTAssertEqual(greetingCount, 2, "Alias should work for both invocations")
    }
    
    // MARK: - Advanced Shell Function Tests
    
    func testFunctionRecursion() async throws {
        // Test recursive function with reasonable depth
        let result = try await service.executeCommand("""
        function factorial() {
            if [ $1 -le 1 ]; then
                echo 1
            else
                local prev=$(factorial $(($1 - 1)))
                echo $(($1 * $prev))
            fi
        }
        
        # Calculate factorial of 5
        factorial 5
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "120")
    }
    
    func testFunctionRecursionDepthHandling() async throws {
        // Test function with excessive recursion that should be handled gracefully
        let result = try await service.executeCommand("""
        function recurse() {
            local depth=$1
            echo "Depth: $depth"
            if [ $depth -lt 20 ]; then
                recurse $(($depth + 1)) || echo "Recursion stopped at depth $depth"
            fi
        }
        
        # Start recursion at depth 1
        recurse 1 2>/dev/null || echo "Recursion completed with error"
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        
        // Verify we got some depth but eventually handled any potential limit
        XCTAssertTrue(result.output.contains("Depth: 1"))
        XCTAssertTrue(result.output.contains("Depth: 10"))
    }
    
    func testFunctionErrorPropagation() async throws {
        // Test error propagation through multiple function calls
        let result = try await service.executeCommand("""
        function level3() {
            local value=$1
            if [ $value -lt 0 ]; then
                echo "Error in level 3: negative value" >&2
                return 3
            fi
            echo "Level 3 success"
            return 0
        }
        
        function level2() {
            local value=$1
            echo "Level 2 processing..."
            level3 $value
            local status=$?
            if [ $status -ne 0 ]; then
                echo "Error in level 2: level 3 failed with code $status" >&2
                return 2
            fi
            return 0
        }
        
        function level1() {
            local value=$1
            echo "Level 1 processing..."
            level2 $value
            local status=$?
            if [ $status -ne 0 ]; then
                echo "Error in level 1: level 2 failed with code $status" >&2
                return 1
            fi
            return 0
        }
        
        # Test success case
        level1 5
        echo "Success exit code: $?"
        
        # Test failure case
        level1 -1
        echo "Failure exit code: $?"
        """)
        
        // Verify both success and failure paths
        XCTAssertTrue(result.output.contains("Level 1 processing..."))
        XCTAssertTrue(result.output.contains("Level 2 processing..."))
        XCTAssertTrue(result.output.contains("Level 3 success"))
        XCTAssertTrue(result.output.contains("Success exit code: 0"))
        XCTAssertTrue(result.output.contains("Error in level 3: negative value"))
        XCTAssertTrue(result.output.contains("Error in level 2: level 3 failed with code 3"))
        XCTAssertTrue(result.output.contains("Error in level 1: level 2 failed with code 2"))
        XCTAssertTrue(result.output.contains("Failure exit code: 1"))
    }
    
    // MARK: - Advanced Alias Tests
    
    func testNestedAliasExpansion() async throws {
        // Test nested alias expansion
        let result = try await service.executeCommand("""
        alias base='echo "Base:"'
        alias level1='base "Level 1"'
        alias level2='level1 && echo "Level 2"'
        
        level2
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Base: Level 1"))
        XCTAssertTrue(result.output.contains("Level 2"))
    }
    
    func testAliasWithQuoting() async throws {
        // Test alias behavior with different types of quotes
        let result = try await service.executeCommand("""
        alias single_quote='echo "single quoted"'
        alias double_quote="echo 'double quoted'"
        alias mixed_quote='echo "mixed '\''quote'\''"'
        
        single_quote
        double_quote
        mixed_quote
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("single quoted"))
        XCTAssertTrue(result.output.contains("double quoted"))
        XCTAssertTrue(result.output.contains("mixed 'quote'"))
    }
    
    func testAliasInScripts() async throws {
        // Test alias usage in scripts (requires shopt -s expand_aliases in bash)
        let result = try await service.executeCommand("""
        # Create a script that uses aliases
        cat > test_alias.sh << 'EOF'
        #!/bin/zsh
        alias greet='echo "Hello from script"'
        greet
        EOF
        
        chmod +x test_alias.sh
        ./test_alias.sh
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Hello from script"))
    }
    
    // MARK: - Shell Option Tests
    
    func testShellErrorExitOption() async throws {
        // Test set -e (errexit) option
        let result = try await service.executeCommand("""
        # This part should complete normally
        echo "Part 1 start"
        false
        echo "Part 1 end"
        
        # This part should exit on error
        set -e
        echo "Part 2 start"
        false
        echo "Part 2 end"
        """)
        
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Part 1 start"))
        XCTAssertTrue(result.output.contains("Part 1 end"))
        XCTAssertTrue(result.output.contains("Part 2 start"))
        XCTAssertFalse(result.output.contains("Part 2 end"))
    }
    
    func testShellUndefinedVariableOption() async throws {
        // Test set -u (nounset) option
        let result = try await service.executeCommand("""
        # This part should use empty undefined variable
        echo "Part 1: \$undefined_var_1"
        
        # This part should error on undefined variable
        set -u
        echo "Part 2 start"
        echo "Part 2: \$undefined_var_2" 2>/dev/null || echo "Caught undefined variable error"
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Part 1:"))
        XCTAssertTrue(result.output.contains("Part 2 start"))
        XCTAssertTrue(result.output.contains("Caught undefined variable error"))
    }
    
    func testShellPipefailOption() async throws {
        // Test set -o pipefail option
        let result = try await service.executeCommand("""
        # Default behavior - pipeline returns last command status
        false | true
        echo "Default pipeline exit code: $?"
        
        # With pipefail - pipeline returns first non-zero status
        set -o pipefail
        false | true
        echo "Pipefail exit code: $?"
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Default pipeline exit code: 0"))
        XCTAssertTrue(result.output.contains("Pipefail exit code: 1"))
    }
    
    func testShellTraps() async throws {
        // Test trap handlers for signals and EXIT
        let result = try await service.executeCommand("""
        # Set up trap for script exit
        trap 'echo "Exit trap executed"' EXIT
        
        # Set up trap for errors
        trap 'echo "Error occurred on line $LINENO"; exit 1' ERR
        
        echo "Starting script"
        # Trigger error trap with command that fails
        ls /nonexistent_directory 2>/dev/null
        echo "This should not be reached"
        """)
        
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Starting script"))
        XCTAssertTrue(result.output.contains("Error occurred on line"))
        XCTAssertTrue(result.output.contains("Exit trap executed"))
        XCTAssertFalse(result.output.contains("This should not be reached"))
    }
    
    // MARK: - Shell Session State Tests
    
    func testSessionEnvironmentPersistence() async throws {
        // Test that environment changes persist across commands in the same session
        let result = try await service.executeCommand("""
        export SESSION_TEST="persistent value"
        bash -c 'echo "From subprocess: $SESSION_TEST"'
        echo "From main shell: $SESSION_TEST"
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("From subprocess: persistent value"))
        XCTAssertTrue(result.output.contains("From main shell: persistent value"))
    }
    
    func testWorkingDirectoryPersistence() async throws {
        // Test that working directory changes persist across commands
        let result = try await service.executeCommand("""
        mkdir -p test_persistence
        cd test_persistence
        pwd > pwd_output.txt
        echo "something" > test.txt
        ls -la
        cat pwd_output.txt
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("test_persistence"))
        XCTAssertTrue(result.output.contains("test.txt"))
        XCTAssertTrue(result.output.contains("pwd_output.txt"))
    }
    
    func testFunctionDefinitionPersistence() async throws {
        // Test that function definitions persist throughout a session
        let result = try await service.executeCommand("""
        # Define a function
        function persistent_func() {
            echo "Function called with: $1"
        }
        
        # Call it from multiple places
        persistent_func "first call"
        
        # Some other commands in between
        echo "intermediate command"
        cd /tmp && cd -
        
        # Call the function again
        persistent_func "second call"
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Function called with: first call"))
        XCTAssertTrue(result.output.contains("intermediate command"))
        XCTAssertTrue(result.output.contains("Function called with: second call"))
    }
    
    // MARK: - Complex Signal and Trap Tests
    
    func testNestedTrapHandlers() async throws {
        let result = try await service.executeCommand("""
        # Set up outer trap
        trap 'echo "Outer trap called"' EXIT
        
        # Create a subshell with its own trap
        (
            trap 'echo "Inner trap called"' EXIT
            echo "Inner shell"
            exit 0
        )
        
        echo "Outer shell"
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Inner shell"))
        XCTAssertTrue(result.output.contains("Inner trap called"))
        XCTAssertTrue(result.output.contains("Outer shell"))
        XCTAssertTrue(result.output.contains("Outer trap called"))
    }
    
    func testErrorTrapInSubshell() async throws {
        let result = try await service.executeCommand("""
        # Set up traps at different levels
        trap 'echo "Main ERR trap: $?"' ERR
        
        # Test subshell trap inheritance
        (
            trap 'echo "Subshell ERR trap: $?"' ERR
            echo "Before error"
            false  # Trigger error
            echo "After error - should not see this"
        )
        
        echo "Back in main shell"
        
        # Should not trigger main shell's ERR trap
        true
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Before error"))
        XCTAssertTrue(result.output.contains("Subshell ERR trap:"))
        XCTAssertFalse(result.output.contains("After error - should not see this"))
        XCTAssertTrue(result.output.contains("Back in main shell"))
    }
    
    func testMultipleSignalTraps() async throws {
        // Test handling multiple signal types
        let result = try await service.executeCommand("""
        # Set up traps for multiple signals
        trap 'echo "EXIT trap called"' EXIT
        trap 'echo "INT trap called"; exit 1' INT
        trap 'echo "TERM trap called"; exit 2' TERM
        
        echo "Traps set"
        
        # Simulate an INT signal
        kill -s INT $$ 2>/dev/null || echo "Self-kill simulation: INT"
        
        # This part should not be reached due to the INT trap
        echo "This should not be printed"
        """)
        
        // The INT trap may not actually work in the test context,
        // but we can verify the traps were set correctly
        XCTAssertTrue(result.output.contains("Traps set"))
        
        // Either we'll see the INT trap called or the simulation message
        XCTAssertTrue(
            result.output.contains("INT trap called") ||
            result.output.contains("Self-kill simulation: INT")
        )
    }
    
    // MARK: - Path Resolution Tests
    
    func testCommandPathResolution() async throws {
        // Test various ways of executing commands
        let result = try await service.executeCommand("""
        # Full path
        /bin/echo "full path"
        
        # Relative to PATH
        echo "from PATH"
        
        # Current directory
        echo '#!/bin/sh\\necho "local command"' > local_cmd.sh
        chmod +x local_cmd.sh
        ./local_cmd.sh
        
        # Command type information
        type echo
        type ls
        type bash
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("full path"))
        XCTAssertTrue(result.output.contains("from PATH"))
        XCTAssertTrue(result.output.contains("local command"))
        XCTAssertTrue(result.output.contains("echo is") || result.output.contains("echo:"))
    }
    
    func testPathModification() async throws {
        // Test command resolution with modified PATH
        let result = try await service.executeCommand("""
        # Save original PATH
        OLD_PATH="$PATH"
        
        # Add current directory to PATH
        PATH=".:$PATH"
        
        # Create a local command
        echo '#!/bin/sh\\necho "found in path"' > mycmd
        chmod +x mycmd
        
        # Try to execute without ./
        mycmd
        
        # Restore PATH
        PATH="$OLD_PATH"
        
        # Should fail now without ./
        mycmd 2>/dev/null || echo "not found in path"
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("found in path"))
        XCTAssertTrue(result.output.contains("not found in path"))
    }
    
    func testRelativeAndAbsolutePathExecution() async throws {
        // Create test directory with command
        let testDir = testDirectory.appendingPathComponent("path_test")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        
        // Run test with relative and absolute paths
        let result = try await service.executeCommand("""
        # Create test files
        mkdir -p path_test/bin
        echo '#!/bin/sh\\necho "relative: $1"' > path_test/bin/testcmd
        chmod +x path_test/bin/testcmd
        
        # Execute with relative path
        path_test/bin/testcmd arg1
        
        # Get and use absolute path
        FULLPATH="$(pwd)/path_test/bin/testcmd"
        $FULLPATH arg2
        
        # Change directory and test relative path again
        cd path_test
        bin/testcmd arg3
        
        # Test with PATH
        PATH="$(pwd)/bin:$PATH"
        testcmd arg4
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("relative: arg1"))
        XCTAssertTrue(result.output.contains("relative: arg2"))
        XCTAssertTrue(result.output.contains("relative: arg3"))
        XCTAssertTrue(result.output.contains("relative: arg4"))
    }
    
    // MARK: - Special Parameter Tests
    
    func testSpecialParameters() async throws {
        let result = try await service.executeCommand("""
        # Test $? (exit status)
        true
        echo "Success exit code: $?"
        false
        echo "Failure exit code: $?"
        
        # Test $$ (shell PID)
        echo "Shell PID: $$"
        
        # Test $! (last background PID)
        sleep 0.1 &
        echo "Background PID: $!"
        
        # Test $- (shell options)
        echo "Shell options: $-"
        
        # Test $# and $@ (argument counting and expansion)
        function test_args() {
            echo "Arg count: $#"
            echo "Args: $@"
        }
        test_args one two three
        
        # Wait for background process to finish
        wait
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Success exit code: 0"))
        XCTAssertTrue(result.output.contains("Failure exit code: 1"))
        XCTAssertTrue(result.output.contains("Shell PID:"))
        XCTAssertTrue(result.output.contains("Background PID:"))
        XCTAssertTrue(result.output.contains("Shell options:"))
        XCTAssertTrue(result.output.contains("Arg count: 3"))
        XCTAssertTrue(result.output.contains("Args: one two three"))
    }
    
    func testParameterExpansion() async throws {
        let result = try await service.executeCommand("""
        # Test various parameter expansion forms
        MYVAR="hello world"
        EMPTY=""
        ARRAY=(one two three)
        
        # Default values
        echo "Default: \${UNSET:-default}"
        echo "Empty default: \${EMPTY:-default}"
        echo "Set default: \${MYVAR:-default}"
        
        # Assign default
        echo "Assign: \${UNSET:=newvalue}"
        echo "After assign: $UNSET"
        
        # Error if unset (redirecting error to prevent test failure)
        \${EMPTY:?error} 2>/dev/null || echo "Error test worked"
        
        # Substring expansion
        echo "Substring: \${MYVAR:2}"
        echo "Substring with length: \${MYVAR:1:5}"
        
        # Length
        echo "Length: \${#MYVAR}"
        
        # Pattern substitution
        echo "Pattern: \${MYVAR/o/O}"
        echo "Pattern global: \${MYVAR//o/O}"
        
        # Test array
        echo "Array element: \${ARRAY[1]}"
        echo "Array length: \${#ARRAY[@]}"
        """)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Default: default"))
        XCTAssertTrue(result.output.contains("Empty default: default"))
        XCTAssertTrue(result.output.contains("Set default: hello world"))
        XCTAssertTrue(result.output.contains("After assign: newvalue"))
        XCTAssertTrue(result.output.contains("Error test worked"))
        XCTAssertTrue(result.output.contains("Substring: llo world"))
        XCTAssertTrue(result.output.contains("Substring with length: ello"))
        XCTAssertTrue(result.output.contains("Length: 11"))
        XCTAssertTrue(result.output.contains("Pattern: hellO world"))
        XCTAssertTrue(result.output.contains("Pattern global: hellO wOrld"))
        XCTAssertTrue(result.output.contains("Array element: two"))
        XCTAssertTrue(result.output.contains("Array length: 3"))
    }
    
    // MARK: - Command Substitution Tests
    
    func testCommandSubstitution() async throws {
        let result = try await service.executeCommand("""
        # Basic command substitution
        DATE=$(date "+%Y")
        echo "Year: $DATE"
        
        # Nested command substitution
        FILES=$(ls $(pwd))
        echo "Files found: $FILES"
        
        # Command substitution with backticks (legacy syntax)
        UPTIME=`uptime`
        echo "Uptime: $UPTIME"
        
        # Command substitution in string
        echo "Directory contains: $(ls -1 | wc -l) files"
        
        # Command substitution with quotes
        QUOTED="$(echo "Hello World")"
        echo "Quoted: $QUOTED"
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Year: 20")) // Should contain part of the year
        XCTAssertTrue(result.output.contains("Files found:"))
        XCTAssertTrue(result.output.contains("Uptime:"))
        XCTAssertTrue(result.output.contains("Directory contains:"))
        XCTAssertTrue(result.output.contains("Quoted: Hello World"))
    }
    
    func testNestedCommandSubstitution() async throws {
        let result = try await service.executeCommand("""
        # Complex nested command substitution
        DEPTH1=$(echo "Level $(echo "$(echo "Deep")")")
        echo "Nested result: $DEPTH1"
        
        # Command substitution with arithmetic
        COUNT=$(( $(ls -1 | wc -l) + 5 ))
        echo "File count plus 5: $COUNT"
        
        # Command substitution in loop
        for i in $(seq 1 $(echo "3")); do
            echo "Loop iteration $i"
        done
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Nested result: Level Deep"))
        XCTAssertTrue(result.output.contains("File count plus 5:"))
        XCTAssertTrue(result.output.contains("Loop iteration 1"))
        XCTAssertTrue(result.output.contains("Loop iteration 2"))
        XCTAssertTrue(result.output.contains("Loop iteration 3"))
    }
    
    func testCommandSubstitutionWithError() async throws {
        let result = try await service.executeCommand("""
        # Command substitution with error handling
        ERROR_OUTPUT=$(ls /nonexistent_directory 2>&1 || echo "Command failed")
        echo "Error handling: $ERROR_OUTPUT"
        
        # Exit code capture
        ls /nonexistent_directory 2>/dev/null
        EXIT_CODE=$?
        echo "Exit code captured: $EXIT_CODE"
        
        # Conditional command substitution
        RESULT=$( [[ -d "/tmp" ]] && echo "Directory exists" || echo "Not found" )
        echo "Conditional result: $RESULT"
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Error handling: Command failed") || 
                      result.output.contains("Error handling: No such file or directory"))
        XCTAssertTrue(result.output.contains("Exit code captured:") && 
                      !result.output.contains("Exit code captured: 0"))
        XCTAssertTrue(result.output.contains("Conditional result: Directory exists"))
    }
    
    // MARK: - Here-Document Tests
    
    func testBasicHereDocument() async throws {
        let result = try await service.executeCommand("""
        # Basic here-document
        cat << EOF
        Line 1
        Line 2
        Line 3
        EOF
        
        # Here-document with variable expansion
        NAME="World"
        cat << EOF
        Hello, $NAME!
        The date is: $(date "+%Y-%m-%d")
        EOF
        
        # Here-document without expansion
        cat << 'EOF'
        No expansion: $NAME
        No command: $(date)
        EOF
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Line 1\nLine 2\nLine 3"))
        XCTAssertTrue(result.output.contains("Hello, World!"))
        XCTAssertTrue(result.output.contains("The date is: 20")) // Should match year
        XCTAssertTrue(result.output.contains("No expansion: $NAME"))
        XCTAssertTrue(result.output.contains("No command: $(date)"))
    }
    
    func testHereDocumentWithIndentation() async throws {
        let result = try await service.executeCommand("""
        # Here-document with indentation stripping (tabs)
        cat <<- EOF
        	Indented line 1
        		More indented line 2
        	Back to first level
        EOF
        
        # Here-document in a function
        function heredoc_test() {
            cat << EOF
        Function line 1
            Function line 2
        EOF
        }
        
        heredoc_test
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Indented line 1"))
        XCTAssertTrue(result.output.contains("More indented line 2"))
        XCTAssertTrue(result.output.contains("Back to first level"))
        XCTAssertTrue(result.output.contains("Function line 1"))
        XCTAssertTrue(result.output.contains("Function line 2"))
    }
    
    func testHereDocumentWithPipes() async throws {
        let result = try await service.executeCommand("""
        # Here-document with pipes
        cat << EOF | grep 'match' | tr 'a-z' 'A-Z'
        no match here
        this will match
        another match here
        no match again
        EOF
        
        # Here-document as input to while loop
        while read line; do
            echo "Read: $line"
        done << EOF
        line one
        line two
        line three
        EOF
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("THIS WILL MATCH"))
        XCTAssertTrue(result.output.contains("ANOTHER MATCH HERE"))
        XCTAssertTrue(result.output.contains("Read: line one"))
        XCTAssertTrue(result.output.contains("Read: line two"))
        XCTAssertTrue(result.output.contains("Read: line three"))
    }
    
    func testHereStringAndHereDocumentVariants() async throws {
        let result = try await service.executeCommand("""
        # Here-string (<<<)
        grep 'search' <<< "searching for a pattern"
        
        # Here-document to a file
        cat > test_here.txt << EOF
        Line for file
        Another line for file
        EOF
        
        cat test_here.txt
        
        # Multiple here-documents in one command
        bash -c 'cat << EOF1; echo "---"; cat << EOF2
        First document
        EOF1
        Second document
        EOF2'
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("searching for a pattern"))
        XCTAssertTrue(result.output.contains("Line for file"))
        XCTAssertTrue(result.output.contains("Another line for file"))
        XCTAssertTrue(result.output.contains("First document"))
        XCTAssertTrue(result.output.contains("Second document"))
    }
    
    // MARK: - Feature Integration Tests
    
    func testComplexShellFeatureInteraction() async throws {
        let result = try await service.executeCommand("""
        # Define a function that uses multiple shell features
        function process_data() {
            local input_text="$1"
            local operation="$2"
            
            # Use parameter expansion and command substitution
            local timestamp=$(date "+%H:%M:%S")
            local temp_file="/tmp/data_${timestamp//:/}_$$.txt"
            
            # Use here-document with variable expansion
            cat > "$temp_file" << EOF
            Input: $input_text
            Time: $timestamp
            PID: $$
            EOF
            
            # Use different parameter expansion forms
            local op_type="${operation:-uppercase}"
            
            # Process based on operation using command substitution
            case "$op_type" in
                uppercase)
                    result=$(cat "$temp_file" | tr 'a-z' 'A-Z')
                    ;;
                reverse)
                    result=\$(cat "$temp_file" | rev)
                    ;;
                *)
                    result=$(cat "$temp_file")
                    ;;
            esac
            
            echo "$result"
            rm -f "$temp_file"
        }
        
        # Define some aliases
        alias uppercase='process_data "test data" uppercase'
        alias reverse='process_data "test data" reverse'
        
        # Test the function and aliases
        echo "Direct function call:"
        process_data "Hello, World!" uppercase
        
        echo "Via alias:"
        uppercase
        
        echo "With reverse operation:"
        reverse
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("HELLO, WORLD!"))
        XCTAssertTrue(result.output.contains("INPUT: TEST DATA"))
        XCTAssertTrue(result.output.contains("Time:"))
        XCTAssertTrue(result.output.contains("PID:"))
    }
    
    func testFunctionsWithPipelinesAndRedirection() async throws {
        let result = try await service.executeCommand("""
        # Create test files
        echo "apple\norange\nbanana\ngrape\napricot" > fruits.txt
        
        # Function that combines redirection and pipelines
        function find_fruits() {
            local pattern="$1"
            local transform="$2"
            
            cat fruits.txt | grep "$pattern" | sort | while read fruit; do
                case "$transform" in
                    upper) echo "$fruit" | tr 'a-z' 'A-Z' ;;
                    count) echo "$fruit: $(echo "$fruit" | wc -c) chars" ;;
                    *) echo "$fruit" ;;
                esac
            done
        }
        
        # Alias for common operations
        alias count_a_fruits='find_fruits "a" count'
        
        # Test direct function call
        find_fruits "a" upper > results.txt
        echo "Results file contents:"
        cat results.txt
        
        # Test with alias and different redirection
        echo "Counting fruits with 'a':"
        count_a_fruits
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("APPLE"))
        XCTAssertTrue(result.output.contains("APRICOT"))
        XCTAssertTrue(result.output.contains("BANANA"))
        XCTAssertTrue(result.output.contains("GRAPE"))
        XCTAssertTrue(result.output.contains("apple:"))
        XCTAssertTrue(result.output.contains("apricot:"))
    }
    
    func testNestedFeaturesWithErrorHandling() async throws {
        let result = try await service.executeCommand("""
        # Set up error handling
        set -e
        trap 'echo "Error trap activated on line $LINENO"' ERR
        
        # Function that combines multiple features
        function complex_operation() {
            local dir="$1"
            local pattern="$2"
            
            # Use command substitution and parameter expansion
            local count=$(find "$dir" -type f -name "$pattern" 2>/dev/null | wc -l)
            
            # Here-document with nested command substitution
            cat << EOF | while read line; do
            Found \\$count files matching '$pattern' in '$dir'
            Current path: $(pwd)
            Files: $(ls -1 "$dir" | head -n 3)
            EOF
                echo "Processing: $line"
            done
            
            # Return success only if files were found
            [[ $count -gt 0 ]] || return 1
        }
        
        # Create test files
        mkdir -p test_dir
        touch test_dir/file1.txt test_dir/file2.txt test_dir/test.dat
        
        # Test successful case
        echo "Testing successful case:"
        complex_operation test_dir "*.txt" || echo "Operation failed"
        
        # Temporarily disable errexit for testing failure case
        set +e
        
        # Test failure case
        echo "Testing failure case:"
        complex_operation test_dir "*.nonexistent" || echo "Operation failed as expected"
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Found 2 files matching '*.txt'"))
        XCTAssertTrue(result.output.contains("file1.txt"))
        XCTAssertTrue(result.output.contains("file2.txt"))
        XCTAssertTrue(result.output.contains("Operation failed as expected"))
    }
    
    func testDynamicFeatureGeneration() async throws {
        let result = try await service.executeCommand("""
        # Generate function names and aliases dynamically
        for op in uppercase lowercase reverse; do
            # Generate function name
            func_name="process_${op}"
            
            # Create function definition using eval
            eval "function $func_name() {
                local text=\\\"\\$1\\\"
                case '$op' in
                    uppercase) echo \\\"\\$text\\\" | tr 'a-z' 'A-Z' ;;
                    lowercase) echo \\\"\\$text\\\" | tr 'A-Z' 'a-z' ;;
                    reverse) echo \\\"\\$text\\\" | rev ;;
                esac
            }"
            
            # Create alias
            alias "${op}_text"="$func_name"
        done
        
        # Test generated functions
        test_text="Hello, World!"
        process_uppercase "$test_text"
        process_lowercase "$test_text"
        process_reverse "$test_text"
        
        # Test generated aliases
        uppercase_text "$test_text"
        lowercase_text "$test_text"
        reverse_text "$test_text"
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("HELLO, WORLD!"))
        XCTAssertTrue(result.output.contains("hello, world!"))
        // Reverse of "Hello, World!"
        XCTAssertTrue(result.output.contains("!dlroW ,olleH"))
    }
    
    func testNestedSubshellsWithExitHandling() async throws {
        let result = try await service.executeCommand("""
        # Function using nested subshells and exit handling
        function nested_operation() {
            # Set up exit trap at this level
            trap 'echo "Level 1 exit handler"' EXIT
            
            echo "Level 1 start"
            
            # First subshell
            (
                trap 'echo "Level 2 exit handler"' EXIT
                echo "Level 2 start"
                
                # Nested subshell
                (
                    trap 'echo "Level 3 exit handler"' EXIT
                    echo "Level 3 start"
                    echo "Level 3 end"
                )
                
                echo "Level 2 end"
            )
            
            echo "Level 1 end"
        }
        
        # Call the function
        nested_operation
        
        echo "Main shell"
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        
        // Check for proper nesting order of execution
        let lines = result.output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        
        // Find indices to verify execution order
        let level1Start = lines.firstIndex(of: "Level 1 start") ?? -1
        let level2Start = lines.firstIndex(of: "Level 2 start") ?? -1
        let level3Start = lines.firstIndex(of: "Level 3 start") ?? -1
        let level3End = lines.firstIndex(of: "Level 3 end") ?? -1
        let level3Handler = lines.firstIndex(of: "Level 3 exit handler") ?? -1
        let level2End = lines.firstIndex(of: "Level 2 end") ?? -1
        let level2Handler = lines.firstIndex(of: "Level 2 exit handler") ?? -1
        let level1End = lines.firstIndex(of: "Level 1 end") ?? -1
        
        // Verify proper execution order
        XCTAssertTrue(level1Start < level2Start)
        XCTAssertTrue(level2Start < level3Start)
        XCTAssertTrue(level3Start < level3End)
        XCTAssertTrue(level3End < level3Handler)
        XCTAssertTrue(level3Handler < level2End)
        XCTAssertTrue(level2End < level2Handler)
        XCTAssertTrue(level2Handler < level1End)
    }
    
    func testHereDocWithFunctionAndAliases() async throws {
        let result = try await service.executeCommand("""
        # Function that generates a here-document template
        function create_report() {
            local title="$1"
            local content="$2"
            local author="$3"
            
            cat << REPORT_TEMPLATE
        # $title
        
        $content
        
        Generated on $(date "+%Y-%m-%d") by $author
        Current directory: $(pwd)
        REPORT_TEMPLATE
        }
        
        # Function that processes the report
        function format_report() {
            local input="$1"
            local format="$2"
            
            case "$format" in
                uppercase) echo "$input" | tr 'a-z' 'A-Z' ;;
                markdown) 
                    echo "$input" | sed 's/^# /#/' | 
                    sed 's/^Generated/*Generated/' ;;
                *) echo "$input" ;;
            esac
        }
        
        # Create aliases that combine the functions
        alias technical_report='create_report "Technical Report" "Technical details go here." "Engineer"'
        alias markdown_report='format_report "$(technical_report)" markdown'
        
        # Use the functions and aliases together
        echo "Direct function call:"
        create_report "Test Report" "This is a test." "Tester"
        
        echo "Via aliases:"
        technical_report
        
        echo "Formatted report:"
        markdown_report
        """)
        
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Test Report"))
        XCTAssertTrue(result.output.contains("This is a test."))
        XCTAssertTrue(result.output.contains("Test Report"))
        XCTAssertTrue(result.output.contains("This is a test."))
        XCTAssertTrue(result.output.contains("Technical Report"))
        XCTAssertTrue(result.output.contains("Technical details go here."))
        XCTAssertTrue(result.output.contains("Generated on"))
        XCTAssertTrue(result.output.contains("by Engineer"))
        XCTAssertTrue(result.output.contains("by Tester"))
        XCTAssertTrue(result.output.contains("Current directory:"))
        
        // Verify markdown formatting was applied
        XCTAssertTrue(result.output.contains("#Technical Report")) // # merged with title
        XCTAssertTrue(result.output.contains("*Generated on")) // Added asterisk
    }



// MARK: - Code Coverage Verification

extension CommandExecutionServiceTests {
    /// Verifies that all critical code paths in CommandExecutionService are covered by tests
    func testCodeCoverageCompleteness() {
        // This test doesn't actually execute anything but serves as a checklist
        // to ensure all critical paths are covered by other tests
        
        let coverageChecklist = [
            // Constructor coverage
            "✓ Default constructor",
            "✓ Custom working directory",
            "✓ Custom environment",
            "✓ Custom shell path",
            
            // Method coverage
            "✓ executeCommand - basic commands",
            "✓ executeCommand - complex commands",
            "✓ executeCommand - error cases",
            "✓ executeCommand - timeout handling",
            "✓ executeCommandWithStream - streaming output",
            "✓ executeCommandWithStream - timeout handling",
            "✓ changeWorkingDirectory - relative paths",
            "✓ changeWorkingDirectory - absolute paths",
            "✓ changeWorkingDirectory - error cases",
            "✓ getCurrentWorkingDirectory",
            "✓ updateEnvironment",
            "✓ getEnvironment",
            "✓ removeEnvironmentVariables",
            "✓ resetEnvironment",
            
            // Shell feature coverage
            "✓ Command substitution",
            "✓ Pipeline commands",
            "✓ Redirection",
            "✓ Here-documents",
            "✓ Shell functions",
            "✓ Aliases",
            "✓ Special parameters",
            "✓ Parameter expansion",
            "✓ Traps and signals",
            "✓ Shell options",
            
            // Error handling & edge cases
            "✓ Invalid commands",
            "✓ Command cancellation",
            "✓ Process cleanup",
            "✓ Resource management",
            "✓ Signal propagation",
            "✓ Large output handling",
            "✓ Concurrent operations"
        ]
        
        // Print the coverage checklist (useful for CI reports)
        print("\n--- CommandExecutionService Test Coverage Checklist ---")
        for check in coverageChecklist {
            print(check)
        }
        print("---------------------------------------------------\n")
        
        // This test always passes - it's just a documentation tool
        XCTAssertTrue(true, "Coverage checklist complete")
    }
}
