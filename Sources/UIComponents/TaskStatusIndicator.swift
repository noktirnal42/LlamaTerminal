import SwiftUI
import SharedModels

/// A small indicator showing task activity status
public struct TaskStatusIndicator: View {
    /// Active tasks count
    let activeTasksCount: Int
    
    /// Callback when clicked
    let onClick: () -> Void
    
    /// Pulse animation state
    @State private var pulse: Bool = false
    
    public var body: some View {
        Button(action: onClick) {
            HStack(spacing: 4) {
                if activeTasksCount > 0 {
                    // Active tasks indicator
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulse ? 1.2 : 1.0)
                        .animation(
                            pulse ? 
                                Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true) : 
                                .default,
                            value: pulse
                        )
                        .onAppear {
                            pulse = true
                        }
                        .onDisappear {
                            pulse = false
                        }
                }
                
                Text("Tasks: \(activeTasksCount)")
                    .font(.caption)
                    .foregroundColor(activeTasksCount > 0 ? .primary : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(activeTasksCount > 0 ? 0.15 : 0.05))
            )
        }
        .buttonStyle(.plain)
    }
}

