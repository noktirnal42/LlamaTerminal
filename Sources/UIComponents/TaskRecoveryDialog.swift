import SwiftUI
import SharedModels

/// Dialog for recovering tasks from previous sessions
public struct TaskRecoveryDialog: View {
    /// Binding to control sheet presentation
    @Binding var isPresented: Bool
    
    /// Tasks to recover
    let tasks: [TaskState]
    
    /// Callback when recovery is confirmed
    let onRecover: ([TaskState]) -> Void
    
    /// Callback when recovery is canceled
    let onSkip: () -> Void
    
    /// Selected tasks for recovery
    @State private var selectedTasks: Set<UUID> = []
    
    /// Initialize with recovery tasks and callbacks
    /// - Parameters:
    ///   - isPresented: Binding to control dialog presentation
    ///   - tasks: Tasks that can be recovered
    ///   - onRecover: Callback for recovery
    ///   - onSkip: Callback for skipping recovery
    public init(
        isPresented: Binding<Bool>,
        tasks: [TaskState],
        onRecover: @escaping ([TaskState]) -> Void,
        onSkip: @escaping () -> Void
    ) {
        self._isPresented = isPresented
        self.tasks = tasks
        self.onRecover = onRecover
        self.onSkip = onSkip
        
        // Auto-select non-high-risk tasks by default
        let nonRiskyTaskIds = tasks
            .filter { task in
                !task.description.contains("rm ") && 
                !task.type.rawValue.contains("file") &&
                task.status != .failed
            }
            .compactMap { $0.id }
        
        self._selectedTasks = State(initialValue: Set(nonRiskyTaskIds))
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("Recover Tasks from Previous Session")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                
                Text("The following tasks were interrupted and can be recovered.")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            // Task list
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if tasks.isEmpty {
                        Text("No tasks to recover")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ForEach(tasks) { task in
                            TaskRecoveryRow(
                                task: task,
                                isSelected: selectedTasks.contains(task.id ?? UUID()),
                                onToggle: { isSelected in
                                    if let id = task.id {
                                        if isSelected {
                                            selectedTasks.insert(id)
                                        } else {
                                            selectedTasks.remove(id)
                                        }
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 300)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            // Actions
            HStack(spacing: 16) {
                Button("Skip Recovery") {
                    onSkip()
                    isPresented = false
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Button("Recover Selected (\(selectedTasks.count))") {
                    let tasksToRecover = tasks.filter { task in
                        if let id = task.id {
                            return selectedTasks.contains(id)
                        }
                        return false
                    }
                    onRecover(tasksToRecover)
                    isPresented = false
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(selectedTasks.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500)
    }
}

/// Individual row for a task in the recovery dialog
private struct TaskRecoveryRow: View {
    /// Task to display
    let task: TaskState
    
    /// Whether this task is selected
    let isSelected: Bool
    
    /// Callback when selection changes
    let onToggle: (Bool) -> Void
    
    /// Date formatter for timestamps
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    
    /// Icon for task type
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
    
    /// Color for task type
    private var taskColor: Color {
        switch task.type {
        case .aiCommand:
            return .blue
        case .userCommand:
            return .green
        case .fileOperation:
            return .orange
        case .sessionState:
            return .purple
        default:
            return .gray
        }
    }
    
    /// Whether the task is high risk
    private var isHighRisk: Bool {
        task.description.contains("rm ") || 
        task.type.rawValue.contains("file")
    }
    
    var body: some View {
        HStack {
            // Checkbox
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            
            // Icon
            Image(systemName: taskIcon)
                .foregroundColor(taskColor)
                .frame(width: 24)
            
            // Task info
            VStack(alignment: .leading, spacing: 4) {
                Text(task.description)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack {
                    Text(task.type.rawValue.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(dateFormatter.string(from: task.updatedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Risk indicator
            if isHighRisk {
                Text("High Risk")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.2))
                    .foregroundColor(.red)
                    .cornerRadius(4)
            }
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }
}

