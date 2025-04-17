import SwiftUI
import SharedModels

/// Badge indicating the current AI mode
public struct AIModeBadge: View {
    /// The current AI mode
    public let mode: AIMode
    
    /// Creates a new AI mode badge
    /// - Parameter mode: The current AI mode
    public init(mode: AIMode) {
        self.mode = mode
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: mode.systemImage)
                .font(.system(size: 12))
            
            Text(mode.displayName)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(modeColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(modeColor.opacity(0.1))
        .cornerRadius(6)
    }
    
    /// Color associated with the current mode
    private var modeColor: Color {
        switch mode {
        case .disabled:
            return .secondary
        case .auto:
            return .blue
        case .dispatch:
            return .orange
        case .code:
            return .green
        case .command:
            return .purple
        }
    }
}

struct AIModeBadge_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 10) {
            AIModeBadge(mode: .disabled)
            AIModeBadge(mode: .auto)
            AIModeBadge(mode: .dispatch)
            AIModeBadge(mode: .code)
            AIModeBadge(mode: .command)
        }
        .padding()
    }
}
