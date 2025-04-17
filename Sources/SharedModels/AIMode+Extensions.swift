import SwiftUI

// NOTE: This file was moved from Sources/App/AIMode+Extensions.swift

// Removed duplicate AIMode enum definition.
// The primary definition is in AppState.swift (or should be moved to its own file).

extension AIMode {
    /// Keyboard shortcut key for this mode
    public var shortcutKey: String { // Made public
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

