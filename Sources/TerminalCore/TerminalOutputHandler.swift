import Foundation
import SwiftTerm

/// Default implementation of terminal output handling
public class DefaultTerminalOutputHandler: TerminalOutputHandler {
    
    // MARK: - Properties
    
    /// Last processed output
    public private(set) var lastOutput: String = ""
    
    /// Output buffer for assembling complete sequences
    private var outputBuffer: Data = Data()
    
    /// Lock for synchronizing output operations
    private let outputLock = NSLock()
    
    /// Maximum size of the output buffer
    private let maxBufferSize: Int = 8192
    
    /// Current cursor position (if tracked)
    private var cursorPosition: CursorPosition?
    
    /// Whether to track cursor position
    private var trackCursorPosition: Bool = true
    
    /// Output state for tracking escape sequences
    private var outputState: OutputState = .normal
    
    /// Current escape sequence being processed
    private var currentEscapeSequence: String = ""
    
    /// Whether syntax highlighting is enabled
    private var syntaxHighlightingEnabled: Bool = true
    
    /// Output processing delegate
    public weak var outputProcessingDelegate: OutputProcessingDelegate?
    
    // MARK: - Initialization
    
    /// Initializes a new terminal output handler
    public init() {}
    
    // MARK: - Implementation
    
    /// Processes output data from the terminal process
    /// - Parameters:
    ///   - data: Output data
    ///   - terminalView: Terminal view to display output on
    ///   - highlighter: Syntax highlighter for output processing
    public func processOutput(data: ArraySlice<UInt8>, terminalView: SwiftTerm.TerminalView?, highlighter: SyntaxHighlighter?) {
        // Lock for thread safety
        outputLock.lock()
        defer { outputLock.unlock() }
        
        // Buffer output
        bufferOutput(data)
        
        // Process buffered output
        if !outputBuffer.isEmpty {
            // Process and update buffer
            let processedData = processBufferedOutput(highlighter: highlighter)
            
            // Feed processed data to terminal view
            if let terminalView = terminalView {
                // Create a copy of the data for sending
                let dataToSend = processedData
                
                // Feed data on main thread if needed
                if Thread.isMainThread {
                    terminalView.feed(byteArray: dataToSend)
                } else {
                    DispatchQueue.main.async {
                        terminalView.feed(byteArray: dataToSend)
                    }
                }
            }
            
            // Extract string representation for analysis
            if let outputString = String(bytes: processedData, encoding: .utf8) {
                // Update last output
                lastOutput = outputString
                
                // Notify delegate
                outputProcessingDelegate?.didProcessOutput(outputString)
                
                // Track cursor position if enabled
                if trackCursorPosition {
                    updateCursorPosition(from: outputString)
                }
            }
        }
    }
    
    /// Enables or disables syntax highlighting
    /// - Parameter enabled: Whether syntax highlighting is enabled
    public func setSyntaxHighlighting(_ enabled: Bool) {
        syntaxHighlightingEnabled = enabled
    }
    
    /// Enables or disables cursor position tracking
    /// - Parameter enabled: Whether cursor position tracking is enabled
    public func setCursorPositionTracking(_ enabled: Bool) {
        trackCursorPosition = enabled
    }
    
    /// Resets the output state
    public func resetState() {
        outputLock.lock()
        defer { outputLock.unlock() }
        
        outputBuffer = Data()
        outputState = .normal
        currentEscapeSequence = ""
        cursorPosition = nil
    }
    
    // MARK: - Private Methods
    
    /// Buffers output data
    /// - Parameter data: Output data to buffer
    private func bufferOutput(_ data: ArraySlice<UInt8>) {
        // Add to buffer
        outputBuffer.append(contentsOf: data)
        
        // Limit buffer size
        if outputBuffer.count > maxBufferSize {
            print("[OutputHandler] Warning: Output buffer exceeded \(maxBufferSize) bytes, truncating")
            outputBuffer = outputBuffer.suffix(maxBufferSize)
        }
    }
    
    /// Processes buffered output
    /// - Parameter highlighter: Syntax highlighter to use
    /// - Returns: Processed output data
    private func processBufferedOutput(highlighter: SyntaxHighlighter?) -> ArraySlice<UInt8> {
        // Extract output data
        let outputData = outputBuffer
        
        // Clear buffer after extraction
        outputBuffer = Data()
        
        // Apply syntax highlighting if enabled
        if syntaxHighlightingEnabled, let highlighter = highlighter, let text = String(bytes: outputData, encoding: .utf8) {
            // Apply syntax highlighting
            let highlightedText = highlighter.highlightForTerminal(text: text, theme: .dark)
            
            // Convert back to data
            if let highlightedData = highlightedText.data(using: .utf8) {
                return ArraySlice(highlightedData)
            }
        }
        
        // Return original data if no highlighting applied
        return ArraySlice(outputData)
    }
    
    /// Updates cursor position based on output
    /// - Parameter output: Output string
    private func updateCursorPosition(from output: String) {
        var newPosition = cursorPosition ?? CursorPosition(row: 0, column: 0)
        
        // Process output character by character
        var index = output.startIndex
        var inEscapeSequence = false
        var escapeSequence = ""
        
        while index < output.endIndex {
            let char = output[index]
            
            if inEscapeSequence {
                escapeSequence.append(char)
                
                // Check for end of escape sequence
                if char.isLetter || char == "~" {
                    // Process escape sequence
                    processEscapeSequence(escapeSequence, position: &newPosition)
                    inEscapeSequence = false
                    escapeSequence = ""
                }
            } else if char == "\u{1B}" { // Escape character
                inEscapeSequence = true
            } else {
                // Normal character processing
                switch char {
                case "\r": // Carriage return
                    newPosition.column = 0
                    
                case "\n": // Line feed
                    newPosition.row += 1
                    
                case "\t": // Tab
                    newPosition.column += (8 - (newPosition.column % 8))
                    
                case "\b": // Backspace
                    if newPosition.column > 0 {
                        newPosition.column -= 1
                    }
                    
                default:
                    // Normal character
                    newPosition.column += 1
                }
            }
            
            index = output.index(after: index)
        }
        
        // Update cursor position
        cursorPosition = newPosition
    }
    
    /// Processes an escape sequence for cursor positioning
    /// - Parameters:
    ///   - sequence: Escape sequence
    ///   - position: Cursor position to update
    private func processEscapeSequence(_ sequence: String, position: inout CursorPosition) {
        // Check for cursor movement sequences
        if sequence.hasPrefix("[") {
            // Extract parameters
            let commandChar = sequence.last ?? Character(" ")
            let paramString = sequence.dropFirst().dropLast()
            let params = paramString.split(separator: ";").compactMap { Int($0) }
            
            switch commandChar {
            case "A": // Cursor up
                let count = params.first ?? 1
                position.row = max(0, position.row - count)
                
            case "B": // Cursor down
                let count = params.first ?? 1
                position.row += count
                
            case "C": // Cursor forward
                let count = params.first ?? 1
                position.column += count
                
            case "D": // Cursor backward
                let count = params.first ?? 1
                position.column = max(0, position.column - count)
                
            case "G": // Cursor horizontal absolute
                if let column = params.first {
                    position.column = max(0, column - 1)
                }
                
            case "H", "f": // Cursor position
                if params.count >= 2 {
                    position.row = max(0, (params[0] - 1))
                    position.column = max(0, (params[1] - 1))
                } else if params.count == 1 {
                    position.row = max(0, (params[0] - 1))
                    position.column = 0
                } else {
                    position.row = 0
                    position.column = 0
                }
                
            case "J": // Erase in display
                if params.isEmpty || params.first == 0 {
                    // Erase from cursor to end of screen
                } else if params.first == 1 {
                    // Erase from start of screen to cursor
                } else if params.first == 2 {
                    // Erase entire screen
                    position.row = 0
                    position.column = 0
                }
                
            case "K": // Erase in line
                if params.isEmpty || params.first == 0 {
                    // Erase from cursor to end of line
                } else if params.first == 1 {
                    // Erase from start of line to cursor
                } else if params.first == 2 {
                    // Erase entire line
                    position.column = 0
                }
                
            default:
                break
            }
        }
    }
}

/// Cursor position in the terminal
public struct CursorPosition: Equatable {
    /// Row (0-based)
    public var row: Int
    
    /// Column (0-based)
    public var column: Int
    
    /// Initializes a new cursor position
    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}

/// Output state for tracking escape sequences
private enum OutputState {
    /// Normal output
    case normal
    
    /// Inside escape sequence
    case escape
    
    /// Inside CSI sequence
    case csi
    
    /// Inside OSC sequence
    case osc
}

/// Protocol for output processing notifications
public protocol OutputProcessingDelegate: AnyObject {
    /// Called when output has been processed
    /// - Parameter output: Processed output
    func didProcessOutput(_ output: String)
}

