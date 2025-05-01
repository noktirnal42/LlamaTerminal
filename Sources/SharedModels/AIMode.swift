import SwiftUI

/// AI modes available for terminal assistant
public enum AIMode: String, CaseIterable, Identifiable {
    case disabled
    case auto
    case dispatch
    case code
    case command

    public var id: String { self.rawValue }

    public var displayName: String {
        switch self {
        case .disabled: return "AI Disabled"
        case .auto: return "Auto Mode"
        case .dispatch: return "Dispatch Mode"
        case .code: return "Code Assistant"
        case .command: return "Command Assistant"
        }
    }

    public var systemImage: String {
        switch self {
        case .disabled: return "brain.slash"
        case .auto: return "brain"
        case .dispatch: return "list.bullet.rectangle"
        case .code: return "curlybraces"
        case .command: return "terminal"
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
        }
    }
}

