import SwiftUI
import SharedModels

/// Displays the progress of ongoing tasks
public struct TaskProgressView: View {
    /// Tasks being tracked
    let tasks: [UUID: TaskState]
    
    /// Whether the view is expanded
    @State private var isExpanded: Bool = false
    
    /// Initializes with active tasks
    /// - Parameter tasks: Tasks to display
    public init(tasks: [UUID: TaskState]) {
        self.tasks = tasks
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack {
                Text("Tasks")
                    .font(.headline)
                
                Text("(\(tasks.count))")
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button {
                    withAnimation {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Task list
            if isExpanded && !tasks.isEmpty {
                Divider()
                
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(tasks.values)) { task in
                            TaskProgressRow(task: task)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 200)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.95))
        .cornerRadius(8)
        .shadow(radius: 2)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }
}

/// Individual row for a task in the progress view
private struct TaskProgressRow: View {
    /// Task to display
    let task: TaskState
    
    /// Color based on task status
    private var statusColor: Color {
        switch task.status {
        case .pending:
            return .yellow
        case .inProgress:
            return .blue
        case .paused:
            return .orange
        case .recovering:
            return .purple
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
    
    /// Icon based on task type
    private var taskIcon: String {
        switch task.type {
        case .aiCommand:
            return "wand.and.stars"
        case .userCommand:
            return "terminal"
        case .fileOperation:
            return "doc"
        case .sessionState:
            return "rectangle.connected.to.line.below"
        default:
            return "questionmark.circle"
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            // Task icon
            Image(systemName: taskIcon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            // Task description
            Text(task.description)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            // Progress indicator for in-progress tasks
            if task.status == .inProgress {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            } else {
                // Status text for other states
                Text(task.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundColor(statusColor)
            }
        }
        .padding(4)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(4)
    }
}

