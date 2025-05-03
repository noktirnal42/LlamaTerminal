import Foundation

/// Represents different AI interaction modes
public enum AIMode: String, Codable, CaseIterable, Identifiable {
    /// AI features are disabled
    case disabled
    
    /// AI suggests and explains commands
    case assistant
    
    /// AI executes commands automatically when safe
    case autonomous
    
    /// AI provides explanations without execution
    case educational
    
    /// Dispatch mode - works with multi-step tasks
    case dispatch
    
    /// Code-specific assistance mode
    case code
    
    /// Command-specific assistance mode
    case command
    
    /// Auto mode for general assistance
    case auto
    
    public var id: String { self.rawValue }
    
    /// User-friendly display name for the mode
    public var displayName: String {
        switch self {
        case .disabled: return "AI Disabled"
        case .auto: return "Auto Mode"
        case .dispatch: return "Dispatch Mode"
        case .code: return "Code Assistant"
        case .command: return "Command Assistant"
        case .assistant: return "AI Assistant"
        case .autonomous: return "AI Autonomous"
        case .educational: return "AI Educational"
        }
    }
    
    /// System icon representing the mode
    public var systemImage: String {
        switch self {
        case .disabled: return "brain.slash"
        case .auto: return "brain"
        case .dispatch: return "list.bullet.rectangle"
        case .code: return "curlybraces"
        case .command: return "terminal"
        case .assistant: return "brain.head.profile"
        case .autonomous: return "bolt.shield"
        case .educational: return "book"
        }
    }
    
    /// Keyboard shortcut key for this mode
    public var shortcutKey: String {
        switch self {
        case .disabled:
            return "0"
        case .auto:
            return "1"
        case .dispatch:
            return "2"
        case .code:
            return "3"
        case .command:
            return "4"
        case .assistant:
            return "5"
        case .autonomous:
            return "6"
        case .educational:
            return "7"
        }
    }
}

