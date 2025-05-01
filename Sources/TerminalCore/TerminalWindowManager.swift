import Foundation
import SwiftTerm
import AppKit

/// Manages window focus and terminal view state
public class DefaultTerminalWindowManager: TerminalWindowManager {
    
    // MARK: - Properties
    
    /// Terminal configuration for reset sequences
    private let terminalConfiguration: TerminalConfiguration
    
    /// Monitor for tracking window focus changes
    private var focusMonitor: Any?
    
    /// Tracks whether input is enabled
    private var inputEnabled: Bool = false
    
    /// Tracks focus state
    private var hasFocus: Bool = false
    
    /// Tracks activation attempts to prevent loops
    private var activationAttemptCount: Int = 0
    
    /// Maximum activation attempts before backing off
    private let maxActivationAttempts: Int = 3
    
    /// Time of last activation attempt
    private var lastActivationTime: Date = Date.distantPast
    
    /// Minimum time between activation attempts
    private let minActivationInterval: TimeInterval = 1.0
    
    /// Delegate for terminal configuration updates
    public weak var configurationDelegate: TerminalConfigurationDelegate?
    
    // MARK: - Initialization
    
    /// Initializes a new window manager
    /// - Parameter terminalConfiguration: Terminal configuration to use
    public init(terminalConfiguration: TerminalConfiguration) {
        self.terminalConfiguration = terminalConfiguration
        
        // Set up focus monitoring
        setupFocusMonitoring()
    }
    
    deinit {
        // Clean up
        if let monitor = focusMonitor {
            NotificationCenter.default.removeObserver(monitor)
        }
    }
    
    // MARK: - Focus Monitoring
    
    /// Sets up monitoring for window focus changes
    private func setupFocusMonitoring() {
        // Monitor main window becoming key (gaining focus)
        focusMonitor = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let window = notification.object as? NSWindow {
                self?.windowDidGainFocus(window)
            }
        }
        
        // Monitor main window resigning key (losing focus)
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let window = notification.object as? NSWindow {
                self?.windowDidLoseFocus(window)
            }
        }
    }
    
    /// Handles window gaining focus
    /// - Parameter window: Window that gained focus
    private func windowDidGainFocus(_ window: NSWindow) {
        print("[WindowManager] Window gained focus")
        
        // Update state
        hasFocus = true
        
        // Reset activation count when window naturally gains focus
        activationAttemptCount = 0
        
        // Find terminal view if it's the first responder
        if let terminalView = window.firstResponder as? TerminalView {
            // Refresh terminal state when focus is gained
            configurationDelegate?.refreshTerminal(terminalView)
            
            // Enable input after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.inputEnabled = true
            }
        }
    }
    
    /// Handles window losing focus
    /// - Parameter window: Window that lost focus
    private func windowDidLoseFocus(_ window: NSWindow) {
        print("[WindowManager] Window lost focus")
        
        // Update state
        hasFocus = false
        
        // Temporarily disable input during focus change
        inputEnabled = false
    }
    
    // MARK: - Window Management
    
    /// Activates the window and brings the terminal view to focus
    /// - Parameter terminalView: Terminal view to activate
    public func activateWindow(terminalView: SwiftTerm.TerminalView) {
        guard let window = terminalView.window else {
            print("[WindowManager] Error: Can't activate window, terminalView.window is nil")
            return
        }
        
        // Check if we're attempting activation too frequently
        let now = Date()
        if now.timeIntervalSince(lastActivationTime) < minActivationInterval {
            // Only if we've exceeded max attempts
            if activationAttemptCount >= maxActivationAttempts {
                print("[WindowManager] Backing off from activation attempts due to frequency limit")
                return
            }
        } else {
            // Reset attempt count after sufficient time has passed
            activationAttemptCount = 0
        }
        
        // Update tracking
        lastActivationTime = now
        activationAttemptCount += 1
        
        print("[WindowManager] Activating window (attempt #\(activationAttemptCount))")
        
        // Perform activation sequence on main thread
        DispatchQueue.main.async {
            // First, make window key and order front
            window.makeKeyAndOrderFront(nil)
            
            // Short delay to let window activation take effect
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                // Then make terminal view first responder
                window.makeFirstResponder(terminalView)
                let _ = terminalView.becomeFirstResponder()
                
                // Update state
                self.hasFocus = window.isKeyWindow
                
                // Verify if activation worked
                if !window.isKeyWindow || window.firstResponder !== terminalView {
                    print("[WindowManager] Activation verification failed")
                    
                    // Retry once more with slightly different approach if this is not already a retry
                    if self.activationAttemptCount <= self.maxActivationAttempts {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            // Try more aggressively
                            window.orderFrontRegardless()
                            window.makeFirstResponder(terminalView)
                            self.hasFocus = window.isKeyWindow
                            self.inputEnabled = window.isKeyWindow
                        }
                    }
                } else {
                    print("[WindowManager] Window activated successfully")
                    // Enable input after successful activation
                    self.inputEnabled = true
                }
            }
        }
    }
    
    /// Refreshes the terminal state including escape sequences and focus
    /// - Parameter terminalView: Terminal view to refresh
    public func refreshTerminal(terminalView: SwiftTerm.TerminalView) {
        print("[WindowManager] Refreshing terminal state")
        
        // Apply refresh sequence via terminal configuration
        terminalConfiguration.configureTerminal(terminalView: terminalView)
        
        // Check focus state and correct if needed
        if let window = terminalView.window, !window.isKeyWindow || window.firstResponder !== terminalView {
            // Activate window if it doesn't have focus
            activateWindow(terminalView: terminalView)
        }
        
        // Enable input
        inputEnabled = true
    }
    
    /// Resets the terminal to a fresh state
    /// - Parameter terminalView: Terminal view to reset
    public func resetTerminal(terminalView: SwiftTerm.TerminalView) {
        print("[WindowManager] Resetting terminal to fresh state")
        
        // Temporarily disable input during reset
        inputEnabled = false
        
        // Apply full reset sequence
        terminalConfiguration.resetTerminal(terminalView: terminalView)
        
        // Ensure window is active after reset
        if let window = terminalView.window {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(terminalView)
                
                // Re-enable input after reset
                self.inputEnabled = true
                self.hasFocus = window.isKeyWindow
            }
        }
    }
    
    // MARK: - Input State Management
    
    /// Checks if input is currently enabled
    /// - Parameter terminalView: Terminal view to check
    /// - Returns: Whether input is enabled
    public func isInputEnabled(terminalView: SwiftTerm.TerminalView) -> Bool {
        // Check if window and terminal view are in a state where input is possible
        guard let window = terminalView.window else {
            return false
        }
        
        // Must have focus and input must be enabled
        let hasWindowFocus = window.isKeyWindow
        let isFirstResponder = window.firstResponder === terminalView
        
        // Log detailed state for debugging
        if !hasWindowFocus || !isFirstResponder || !inputEnabled {
            print("[WindowManager] Input disabled: window focus=\(hasWindowFocus), firstResponder=\(isFirstResponder), inputEnabled=\(inputEnabled)")
        }
        
        return hasWindowFocus && isFirstResponder && inputEnabled
    }
    
    /// Forces input state to the given value
    /// - Parameter enabled: Whether input should be enabled
    public func forceInputState(_ enabled: Bool) {
        inputEnabled = enabled
        print("[WindowManager] Input state forced to \(enabled)")
    }
}

/// Protocol for terminal configuration operations
public protocol TerminalConfigurationDelegate: AnyObject {
    /// Refreshes the terminal
    /// - Parameter terminalView: Terminal view to refresh
    func refreshTerminal(_ terminalView: TerminalView)
}

