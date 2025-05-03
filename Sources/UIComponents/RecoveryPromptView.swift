import SwiftUI
import SharedModels

/// View for prompting the user about task recovery
public struct RecoveryPromptView: View {
    /// Tasks to recover
    let tasks: [TaskState]
    
    /// Callback when recovery is accepted
    let onAccept: () -> Void
    
    /// Callback when recovery is declined
    let onDecline: () -> Void
    
    /// Whether some tasks are high risk
    private var hasHighRiskTasks: Bool {
        tasks.contains { task in
            // Check for high risk tasks like file operations or rm commands
            task.type == .fileOperation || 
            (task.type == .aiCommand && task.description.contains("rm"))
        }
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                
                Text("Recovery Available")
                    .font(.title2.bold())
                
                Text("Found \(tasks.count) tasks from a previous session that can be recovered.")
                    .font(.body)
                    .multilineTextAlignment(.center)
            }
            
            // Warning for high risk tasks
            if hasHighRiskTasks {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    
                    Text("Some tasks involve file operations or potentially destructive commands. Review carefully before recovery.")
                        .font(.callout)
                        .foregroundColor(.orange)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Task summary
            VStack(alignment: .leading, spacing: 4) {
                Text("Task Summary:")
                    .font(.headline)
                
                Text("• \(tasks.filter { $0.type == .aiCommand }.count) AI commands")
                Text("• \(tasks.filter { $0.type == .userCommand }.count) User commands")
                Text("• \(tasks.filter { $0.type == .fileOperation }.count) File operations")
                Text("• \(tasks.filter { $0.type == .sessionState }.count) Session states")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            
            // Actions
            HStack(spacing: 20) {
                Button("Skip Recovery") {
                    onDecline()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Recover Tasks") {
                    onAccept()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

