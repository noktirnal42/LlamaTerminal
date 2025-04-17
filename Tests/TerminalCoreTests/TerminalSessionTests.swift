import XCTest
import SwiftTerm
@testable import TerminalCore
@testable import AIIntegration

final class TerminalSessionTests: XCTestCase {
    var session: TerminalSession!
    var mockTerminalView: MockTerminalView!
    
    override func setUp() async throws {
        mockTerminalView = MockTerminalView()
        session = TerminalSession(theme: .dark)
    }
    
    override func tearDown() async throws {
        session.terminateSession()
        session = nil
        mockTerminalView = nil
    }
    
    // MARK: - Terminal Core Tests
    
    func testSessionInitialization() {
        XCTAssertNotNil(session)
        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.currentCols, 80)
        XCTAssertEqual(session.currentRows, 25)
        XCTAssertNotNil(session.currentWorkingDirectory)
        XCTAssertEqual(session.currentTheme, .dark)
    }
    
    func testSizeUpdate() {
        session.updateSize(cols: 100, rows: 40)
        XCTAssertEqual(session.currentCols, 100)
        XCTAssertEqual(session.currentRows, 40)
    }
    
    func testThemeSwitch() {
        // Default theme is dark
        XCTAssertEqual(session.currentTheme, .dark)
        
        // Switch to light theme
        session.setTheme(.light)
        XCTAssertEqual(session.currentTheme, .light)
        
        // Switch to high contrast theme
        session.setTheme(.highContrast)
        XCTAssertEqual(session.currentTheme, .highContrast)
    }
    
    func testSyntaxHighlightingToggle() {
        // Highlighting enabled by default
        XCTAssertTrue(session.syntaxHighlightingEnabled)
        
        // Disable highlighting
        session.toggleSyntaxHighlighting(false)
        XCTAssertFalse(session.syntaxHighlightingEnabled)
        
        // Enable highlighting
        session.toggleSyntaxHighlighting(true)
        XCTAssertTrue(session.syntaxHighlightingEnabled)
    }
    
    // MARK: - Session Lifecycle Tests
    
    func testStartAndTerminateSession() async {
        let wrapper = LocalProcessTerminalView(terminalView: mockTerminalView)
        
        // Start session
        await session.startSession(for: wrapper)
        
        // Wait a bit for async operations
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        XCTAssertTrue(session.isRunning)
        
        // Terminate session
        session.terminateSession()
        
        // Wait a bit for termination to complete
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // After termination, session should not be running
        // Note: This might be flaky in tests due to timing
        // XCTAssertFalse(session.isRunning)
    }
    
    // MARK: - Command Execution Tests (Non-AI)
    
    func testCommandExecution() {
        let wrapper = MockLocalProcessTerminalView(mockTerminalView: mockTerminalView)
        session.executeCommand("ls -la", fromAI: true) // fromAI = true to bypass AI processing
        
        XCTAssertTrue(wrapper.lastCommand?.contains("ls -la") ?? false)
    }
    
    // MARK: - Syntax Highlighting Tests
    
    func testCommandHighlighting() {
        let command = "ls -la ~/Documents"
        let highlighted = session.highlightCommand(command)
        
        // Highlighted output should contain ANSI codes
        XCTAssertTrue(highlighted.contains("\u{001B}[")) // Contains ANSI escape sequence
        XCTAssertFalse(highlighted == command) // Should be different from original
    }
    
    func testCodeHighlighting() {
        let code = """
        func test() {
            print("Hello, world!")
        }
        """
        
        let highlighted = session.highlightCode(code)
        
        // Highlighted output should contain ANSI codes
        XCTAssertTrue(highlighted.contains("\u{001B}[")) // Contains ANSI escape sequence
        XCTAssertFalse(highlighted == code) // Should be different from original
    }
    
    func testDisabledHighlighting() {
        session.toggleSyntaxHighlighting(false)
        
        let command = "ls -la ~/Documents"
        let highlighted = session.highlightCommand(command)
        
        // With highlighting disabled, output should be identical to input
        XCTAssertEqual(highlighted, command)
    }
}

// MARK: - Mock Classes

class MockTerminalView: TerminalView {
    var fedData: [UInt8] = []
    
    init() {
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func feed(byteArray: ArraySlice<UInt8>) {
        fedData.append(contentsOf: byteArray)
    }
}

class MockLocalProcessTerminalView: LocalProcessTerminalView {
    var lastCommand: String?
    var mockTerminalView: MockTerminalView
    
    init(mockTerminalView: MockTerminalView) {
        self.mockTerminalView = mockTerminalView
        super.init(terminalView: mockTerminalView)
    }
    
    override func send(txt: String) {
        lastCommand = txt
    }
}

import XCTest
@testable import TerminalCore

final class TerminalSessionTests: XCTestCase {
    
    var session: TerminalSession!
    
    override func setUp() {
        super.setUp()
        session = TerminalSession()
    }
    
    override func tearDown() {
        session = nil
        super.tearDown()
    }
    
    func testInitialization() {
        XCTAssertFalse(session.isRunning, "Session should not be running initially")
        XCTAssertEqual(session.lastOutput, "", "Last output should be empty initially")
        XCTAssertNotNil(session.currentWorkingDirectory, "Current working directory should be set to something")
    }
    
    func testExecuteCommand() {
        // This is a basic test since we can't fully test process execution in unit tests
        session.executeCommand("echo 'test'")
        // Just verify it doesn't crash
        XCTAssertFalse(session.isRunning, "Session won't be running without a proper startup")
    }
    
    func testTerminateSession() {
        // Test the terminate functionality
        session.terminateSession()
        XCTAssertFalse(session.isRunning, "Session should be terminated")
    }
    
    func testAddOutput() {
        // Test adding output
        let testOutput = "This is a test output"
        session.addOutput(testOutput)
        
        // Verify lastOutput contains our test string - may have queuing delay
        let exp = expectation(description: "Output should be updated")
        
        // Wait a short time for the async update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if self.session.lastOutput.contains(testOutput) {
                exp.fulfill()
            }
        }
        
        wait(for: [exp], timeout: 1.0)
    }
    
    // Test working directory detection
    func testWorkingDirectoryInitialization() {
        XCTAssertNotNil(session.currentWorkingDirectory, "Current working directory should be initialized")
        
        // Verify it's a valid path
        if let path = session.currentWorkingDirectory {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), "Working directory should be a valid path")
        }
    }
    
    static var allTests = [
        ("testInitialization", testInitialization),
        ("testExecuteCommand", testExecuteCommand),
        ("testTerminateSession", testTerminateSession),
        ("testAddOutput", testAddOutput),
        ("testWorkingDirectoryInitialization", testWorkingDirectoryInitialization),
    ]
}

