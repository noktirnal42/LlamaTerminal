import Foundation
import SwiftTerm
import SwiftUI

/// Implementation of terminal configuration
public class DefaultTerminalConfiguration: TerminalConfiguration {
    
    // MARK: - Properties
    
    /// Terminal type to use
    private let terminalType: String = "xterm-256color"
    
    /// Full reset sequence
    private let fullResetSequence: [String] = [
        "\u{1b}c",         // RIS - Full terminal reset
        "\u{1b}[!p",       // DECSTR - Soft reset
        "\u{1b}[?47l",     // Use normal screen buffer
        "\u{1b}[?1049l",   // Use normal screen buffer (alternate method)
        "\u{1b}[2J",       // Clear screen
        "\u{1b}[H",        // Home cursor
        "\u{1b}[?25h",     // Show cursor
        "\u{1b}[?7h",      // Enable line wrapping
        "\u{1b}[?12l",     // Disable local echo (CRITICAL for proper echo behavior)
        "\u{1b}[4l",       // Reset insert mode
        "\u{1b}[20h",      // Set newline mode (LNM)
        "\u{1b}]0;LlamaTerminal\u{7}" // Set window title
    ]
    
    /// Refresh sequence
    private let refreshSequence: [String] = [
        "\u{1b}[?25h",    // Show cursor
        "\u{1b}[?7h",     // Enable line wrapping
        "\u{1b}[?2004h",  // Enable bracketed paste mode
        "\u{1b}[?12l",    // Disable local echo (crucial for proper echo behavior)
        "\u{1b}[4l",      // Reset insert mode (crucial for proper cursor behavior)
        "\u{1b}[20h",     // Set newline mode (LNM)
    ]
    
    /// Initial stty commands for proper terminal behavior
    private let initialSttyCommands: [String] = [
        "stty sane",                  // Reset to sane terminal settings (primary reset)
        "stty echo",                  // Ensure echo is on (basic setting)
        "stty icrnl onlcr",           // Handle line endings (crucial for proper display)
    ]
    
    /// Enhanced stty commands for better terminal behavior
    private let enhancedSttyCommands: [String] = [
        "stty echoe echok echoke",    // Enhanced echo control options
        "stty icanon",                // Enable canonical mode
        "stty erase '^?'",            // Set erase character
        "stty intr '^C'",             // Set interrupt character
        "stty isig",                  // Enable signals
        "stty ixon",                  // Enable flow control
    ]
    
    /// Additional stty commands for optimal terminal behavior
    private let additionalSttyCommands: [String] = [
        "stty susp '^Z'",             // Set suspend character
        "stty werase '^W'",           // Set word erase
        "stty kill '^U'",             // Set line kill
        "stty -tostop",               // Prevent background processes from stopping on output
        "stty -echoctl",              // Don't echo control characters as ^X
        "setopt INTERACTIVE_COMMENTS", // Allow comments
        "export TERM=xterm-256color",  // Ensure terminal type is set properly
    ]
    
    /// Delegate for executing shell commands
    public weak var shellCommandDelegate: ShellCommandExecutor?
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Implementation
    
    /// Configures the terminal with basic settings
    /// - Parameter terminalView: Terminal view to configure
    public func configureTerminal(terminalView: SwiftTerm.TerminalView) {
        print("[TerminalConfiguration] Configuring terminal with basic settings")
        
        // Configure terminal colors
        terminalView.configureNativeColors()
        
        // Configure terminal options
        if let terminal = terminalView.terminal {
            if let options = terminal.options {
                options.insert(.cursorBlink)
                options.insert(.cursorVisible)
                options.insert(.bracketedPaste)
                options.insert(.allowMouseReporting)
            }
        }
        
        // Apply refresh sequence
        let refreshText = refreshSequence.joined()
        terminalView.feed(text: refreshText)
    }
    
    /// Initializes the terminal with full settings
    /// - Parameter terminalView: Terminal view to initialize
    public func initializeTerminal(terminalView: SwiftTerm.TerminalView) {
        print("[TerminalConfiguration] Initializing terminal with full settings")
        
        // Reset terminal to initial state
        if let terminal = terminalView.terminal {
            terminal.resetToInitialState()
        }
        
        // Clear screen and home cursor
        terminalView.feed(text: "\u{1b}[2J\u{1b}[H")
        
        // Apply full configuration
        configureTerminal(terminalView: terminalView)
        
        // Ensure window has focus
        if let window = terminalView.window {
            DispatchQueue.main.async {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(terminalView)
            }
        }
    }
    
    /// Performs a complete terminal reset
    /// - Parameter terminalView: Terminal view to reset
    public func resetTerminal(terminalView: SwiftTerm.TerminalView) {
        print("[TerminalConfiguration] Performing full terminal reset")
        
        // Reset terminal to initial state
        if let terminal = terminalView.terminal {
            terminal.resetToInitialState()
        }
        
        // Apply full reset sequence
        let resetText = fullResetSequence.joined()
        terminalView.feed(text: resetText)
        
        // Give terminal a moment to process, then clear screen once more
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            terminalView.feed(text: "\u{1b}[2J\u{1b}[H\u{1b}[?25h") // Clear, home cursor, show cursor
        }
    }
    
    /// Updates the terminal size
    /// - Parameters:
    ///   - terminalView: Terminal view to update
    ///   - rows: Number of rows
    ///   - cols: Number of columns
    public func updateTerminalSize(terminalView: SwiftTerm.TerminalView, rows: Int, cols: Int) {
        print("[TerminalConfiguration] Updating terminal size to \(cols)x\(rows)")
        
        // Update terminal about its new size
        let sizeSequence = "\u{1b}[8;\(rows);\(cols)t"
        terminalView.feed(text: sizeSequence)
    }
    
    /// Configures the PTY for proper input/echo behavior
    /// - Parameter shellCommandExecutor: Executor for shell commands
    public func configurePTY(shellCommandExecutor: ShellCommandExecutor) {
        print("[TerminalConfiguration] Configuring PTY for proper input/echo behavior")
        
        // Configure PTY in stages for better reliability
        
        // Stage 1: Basic configuration
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            for command in initialSttyCommands {
                shellCommandExecutor.executeCommand(command)
                try? await Task.sleep(for: .milliseconds(50))
            }
            
            // Stage 2: Enhanced configuration
            try? await Task.sleep(for: .milliseconds(100))
            for command in enhancedSttyCommands {
                shellCommandExecutor.executeCommand(command)
                try? await Task.sleep(for: .milliseconds(50))
            }
            
            // Stage 3: Additional configuration
            try? await Task.sleep(for: .milliseconds(100))
            for command in additionalSttyCommands {
                shellCommandExecutor.executeCommand(command)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
    
    /// Creates default environment variables for the terminal
    /// - Returns: Dictionary of environment variables
    public func createEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        
        // Terminal behavior variables
        environment["TERM"] = terminalType
        environment["TERMINFO"] = "/usr/share/terminfo"
        environment["COLORTERM"] = "truecolor"
        environment["INSIDE_LLAMA_TERMINAL"] = "1"
        
        // Colors and display variables
        environment["CLICOLOR"] = "1"
        environment["CLICOLOR_FORCE"] = "1"
        
        // Shell variables
        environment["SHELL"] = "/bin/zsh"
        environment["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["HOME"] = ProcessInfo.processInfo.environment["HOME"]
        environment["USER"] = ProcessInfo.processInfo.environment["USER"]
        environment["LOGNAME"] = ProcessInfo.processInfo.environment["USER"]
        
        // Use current directory
        environment["PWD"] = FileManager.default.currentDirectoryPath
        
        // Let shell handle its own initialization (don't override PS1)
        environment.removeValue(forKey: "ZDOTDIR")
        environment.removeValue(forKey: "PS1")
        
        return environment
    }
}

/// Protocol for executing shell commands
public protocol ShellCommandExecutor: AnyObject {
    /// Executes a shell command
    /// - Parameter command: Command to execute
    func executeCommand(_ command: String)
}

