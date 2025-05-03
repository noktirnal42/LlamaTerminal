import Foundation
import SwiftTerm

/// Default implementation of terminal input handling
public class DefaultTerminalInputHandler: TerminalInputHandler {
    
    // MARK: - Properties
    
    /// Window manager to check input state
    private weak var windowManager: TerminalWindowManager?
    
    /// Buffer for pending input
    private var inputBuffer: Data = Data()
    
    /// Lock for synchronizing input operations
    private let inputLock = NSLock()
    
    /// Whether input handling is active
    private var isHandlingInput: Bool = false
    
    /// Terminal view reference
    private weak var terminalView: TerminalView?
    
    /// Input mode
    private var inputMode: InputMode = .normal
    
    // MARK: - Initialization
    
    /// Initializes a new terminal input handler
    /// - Parameter windowManager: Window manager to check input state
    public init(windowManager: TerminalWindowManager) {
        self.windowManager = windowManager
    }
    
    // MARK: - Implementation
    
    /// Handles input data from the terminal
    /// - Parameters:
    ///   - data: Input data
    ///   - processManager: Process manager to send data to
    public func handleInput(data: ArraySlice<UInt8>, processManager: ProcessManager) {
        // Check if input is allowed
        guard let windowManager = windowManager,
              let terminalView = terminalView,
              windowManager.isInputEnabled(terminalView: terminalView) else {
            print("[InputHandler] Input not enabled or window not focused, buffering input")
            bufferInput(data)
            return
        }
        
        // Lock for thread safety
        inputLock.lock()
        defer { inputLock.unlock() }
        
        // Check if we're already handling input or process is not running
        if isHandlingInput || !processManager.isRunning {
            // Buffer input for later processing
            bufferInput(data)
            return
        }
        
        // Mark as handling input
        isHandlingInput = true
        
        // Process any buffered input first
        if !inputBuffer.isEmpty {
            let bufferedData = inputBuffer
            inputBuffer = Data()
            
            // Process and send buffered input
            let processedData = processInputData(ArraySlice(bufferedData))
            processManager.sendToProcess(data: processedData)
        }
        
        // Process and send current input
        let processedData = processInputData(data)
        processManager.sendToProcess(data: processedData)
        
        // Mark as done handling input
        isHandlingInput = false
    }
    
    /// Prepares input string for sending to terminal
    /// - Parameter input: Raw input string
    /// - Returns: Processed input string
    public func prepareInput(_ input: String) -> String {
        // Apply input mode specific processing
        switch inputMode {
        case .normal:
            // No special processing needed for normal mode
            return input
            
        case .password:
            // In password mode, don't log or modify input
            return input
            
        case .command:
            // In command mode, add newline if not present
            if !input.hasSuffix("\n") {
                return input + "\n"
            }
            return input
        }
    }
    
    /// Sets the current terminal view
    /// - Parameter terminalView: Terminal view to use
    public func setTerminalView(_ terminalView: TerminalView) {
        self.terminalView = terminalView
    }
    
    /// Sets the input mode
    /// - Parameter mode: Mode to set
    public func setInputMode(_ mode: InputMode) {
        print("[InputHandler] Setting input mode to \(mode)")
        self.inputMode = mode
    }
    
    /// Clears the input buffer
    public func clearBuffer() {
        inputLock.lock()
        defer { inputLock.unlock() }
        
        inputBuffer = Data()
        isHandlingInput = false
    }
    
    // MARK: - Private Methods
    
    /// Buffers input for later processing
    /// - Parameter data: Input data
    private func bufferInput(_ data: ArraySlice<UInt8>) {
        inputLock.lock()
        defer { inputLock.unlock() }
        
        // Add to buffer
        inputBuffer.append(contentsOf: data)
        
        // Limit buffer size to prevent memory issues
        if inputBuffer.count > 4096 {
            print("[InputHandler] Warning: Input buffer exceeded 4KB, truncating")
            inputBuffer = inputBuffer.suffix(4096)
        }
    }
    
    /// Processes input data for special handling
    /// - Parameter data: Raw input data
    /// - Returns: Processed input data
    private func processInputData(_ data: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        // Skip processing for empty data
        if data.isEmpty {
            return data
        }
        
        // Check for special keycodes and control characters
        if data.count == 1 {
            let byte = data[data.startIndex]
            
            switch byte {
            case 0x03: // Ctrl+C - Interrupt
                // Always pass through interrupt signal
                print("[InputHandler] Detected Ctrl+C (interrupt)")
                return data
                
            case 0x04: // Ctrl+D - EOF
                // Always pass through EOF signal
                print("[InputHandler] Detected Ctrl+D (EOF)")
                return data
                
            case 0x1A: // Ctrl+Z - Suspend
                // Always pass through suspend signal
                print("[InputHandler] Detected Ctrl+Z (suspend)")
                return data
                
            case 0x1B: // Escape
                // Handle escape sequences
                return data
                
            default:
                break
            }
        }
        
        // Check for escape sequences
        if data.count > 1 && data[data.startIndex] == 0x1B {
            // Pass through escape sequences
            return data
        }
        
        // Process based on input mode
        switch inputMode {
        case .normal:
            // No special processing for normal mode
            return data
            
        case .password:
            // For password mode, don't log the actual content
            print("[InputHandler] Processing password input (content hidden)")
            return data
            
        case .command:
            // Command mode processing
            if let lastByte = data.last, lastByte == 0x0A || lastByte == 0x0D {
                // Command with newline
                print("[InputHandler] Processing command input with newline")
            } else {
                // Command without newline
                print("[InputHandler] Processing command input without newline")
            }
            return data
        }
    }
}

/// Input modes for the terminal
public enum InputMode {
    /// Normal input mode
    case normal
    
    /// Password input mode (no echo)
    case password
    
    /// Command input mode
    case command
}

