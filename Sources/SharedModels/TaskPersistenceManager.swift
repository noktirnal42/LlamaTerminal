import Foundation
import os.log

/// Manages persistence of application state and task recovery
public actor TaskPersistenceManager {
    /// Logger for tracking persistence operations
    private let logger = Logger(subsystem: "com.llamaterminal", category: "TaskPersistenceManager")
    
    /// Singleton instance
    public static let shared = TaskPersistenceManager()
    
    /// Base directory for all persistent data
    private let persistenceDirectory: URL
    
    /// File URLs for different persistence types
    private let commandHistoryURL: URL
    private let aiPreferencesURL: URL
    private let terminalStateURL: URL
    private let taskStateURL: URL
    
    /// Initialize with default storage locations
    private init() {
        // Set up directory in Application Support
        let appSupportDir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("LlamaTerminal", isDirectory: true)
        
        self.persistenceDirectory = appSupportDir
        
        // Set up file paths for different data types
        self.commandHistoryURL = appSupportDir.appendingPathComponent("command_history.json")
        self.aiPreferencesURL = appSupportDir.appendingPathComponent("ai_preferences.json")
        self.terminalStateURL = appSupportDir.appendingPathComponent("terminal_state.json")
        self.taskStateURL = appSupportDir.appendingPathComponent("tasks", isDirectory: true)
        
        // Create directories if they don't exist
        try? FileManager.default.createDirectory(
            at: persistenceDirectory,
            withIntermediateDirectories: true
        )
        
        try? FileManager.default.createDirectory(
            at: taskStateURL,
            withIntermediateDirectories: true
        )
        
        logger.info("TaskPersistenceManager initialized with storage at \(persistenceDirectory.path)")
    }
    
    // MARK: - Command History Persistence
    
    /// Saves command history to persistent storage
    /// - Parameter history: Command history entries to save
    public func saveCommandHistory(_ history: [CommandHistoryEntry]) async {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            
            // Limit the size of history to save (e.g., last 1000 commands)
            let limitedHistory = history.suffix(1000)
            let data = try encoder.encode(limitedHistory)
            
            try data.write(to: commandHistoryURL, options: .atomic)
            logger.info("Command history saved: \(limitedHistory.count) entries")
        } catch {
            logger.error("Failed to save command history: \(error.localizedDescription)")
        }
    }
    
    /// Loads command history from persistent storage
    /// - Returns: Array of command history entries
    public func loadCommandHistory() async -> [CommandHistoryEntry] {
        do {
            guard FileManager.default.fileExists(atPath: commandHistoryURL.path) else {
                logger.info("No command history file found")
                return []
            }
            
            let data = try Data(contentsOf: commandHistoryURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let history = try decoder.decode([CommandHistoryEntry].self, from: data)
            logger.info("Loaded command history: \(history.count) entries")
            return history
        } catch {
            logger.error("Failed to load command history: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - AI Preferences Persistence
    
    /// Saves AI preferences to persistent storage
    /// - Parameter preferences: AI preferences to save
    public func saveAIPreferences(_ preferences: AIPreferences) async {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(preferences)
            
            try data.write(to: aiPreferencesURL, options: .atomic)
            logger.info("AI preferences saved")
        } catch {
            logger.error("Failed to save AI preferences: \(error.localizedDescription)")
        }
    }
    
    /// Loads AI preferences from persistent storage
    /// - Returns: AI preferences or default values if not found
    public func loadAIPreferences() async -> AIPreferences {
        do {
            guard FileManager.default.fileExists(atPath: aiPreferencesURL.path) else {
                logger.info("No AI preferences file found, using defaults")
                return AIPreferences()
            }
            
            let data = try Data(contentsOf: aiPreferencesURL)
            let decoder = JSONDecoder()
            
            let preferences = try decoder.decode(AIPreferences.self, from: data)
            logger.info("Loaded AI preferences")
            return preferences
        } catch {
            logger.error("Failed to load AI preferences: \(error.localizedDescription)")
            return AIPreferences()
        }
    }
    
    // MARK: - Terminal State Persistence
    
    /// Saves terminal state to persistent storage
    /// - Parameter state: Terminal state to save
    public func saveTerminalState(_ state: TerminalState) async {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(state)
            
            try data.write(to: terminalStateURL, options: .atomic)
            logger.info("Terminal state saved")
        } catch {
            logger.error("Failed to save terminal state: \(error.localizedDescription)")
        }
    }
    
    /// Loads terminal state from persistent storage
    /// - Returns: Terminal state or default values if not found
    public func loadTerminalState() async -> TerminalState {
        do {
            guard FileManager.default.fileExists(atPath: terminalStateURL.path) else {
                logger.info("No terminal state file found, using defaults")
                return TerminalState()
            }
            
            let data = try Data(contentsOf: terminalStateURL)
            let decoder = JSONDecoder()
            
            let state = try decoder.decode(TerminalState.self, from: data)
            logger.info("Loaded terminal state")
            return state
        } catch {
            logger.error("Failed to load terminal state: \(error.localizedDescription)")
            return TerminalState()
        }
    }
    
    // MARK: - Task State Management
    
    /// Saves task state before execution
    /// - Parameters:
    ///   - task: Task information
    ///   - id: Unique task identifier
    /// - Returns: Task recovery ID
    public func saveTaskState(_ task: TaskState, id: UUID? = nil) async -> UUID {
        let taskID = id ?? UUID()
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            
            // Create a recovery record with metadata
            var taskRecord = task
            taskRecord.id = taskID
            taskRecord.updatedAt = Date()
            
            // Save task state
            let data = try encoder.encode(taskRecord)
            let taskFileURL = taskStateURL.appendingPathComponent("\(taskID.uuidString).json")
            
            try data.write(to: taskFileURL, options: .atomic)
            logger.info("Task state saved with ID: \(taskID.uuidString)")
            
            return taskID
        } catch {
            logger.error("Failed to save task state: \(error.localizedDescription)")
            return taskID
        }
    }
    
    /// Updates an existing task state
    /// - Parameters:
    ///   - taskID: Task identifier
    ///   - update: Closure that updates the task state
    /// - Returns: Updated task state
    public func updateTaskState(
        _ taskID: UUID,
        update: (inout TaskState) -> Void
    ) async -> TaskState? {
        do {
            let taskFileURL = taskStateURL.appendingPathComponent("\(taskID.uuidString).json")
            
            // Check if task exists
            guard FileManager.default.fileExists(atPath: taskFileURL.path) else {
                logger.warning("Task not found for updating: \(taskID.uuidString)")
                return nil
            }
            
            // Load existing task
            let data = try Data(contentsOf: taskFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            var taskState = try decoder.decode(TaskState.self, from: data)
            
            // Update the task
            update(&taskState)
            taskState.updatedAt = Date()
            
            // Save updated task
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            
            let updatedData = try encoder.encode(taskState)
            try updatedData.write(to: taskFileURL, options: .atomic)
            
            logger.info("Task state updated: \(taskID.uuidString)")
            return taskState
        } catch {
            logger.error("Failed to update task state: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Loads a task state by ID
    /// - Parameter taskID: Task identifier
    /// - Returns: Task state if found
    public func loadTaskState(_ taskID: UUID) async -> TaskState? {
        do {
            let taskFileURL = taskStateURL.appendingPathComponent("\(taskID.uuidString).json")
            
            guard FileManager.default.fileExists(atPath: taskFileURL.path) else {
                logger.warning("Task not found: \(taskID.uuidString)")
                return nil
            }
            
            let data = try Data(contentsOf: taskFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let taskState = try decoder.decode(TaskState.self, from: data)
            logger.info("Loaded task state: \(taskID.uuidString)")
            
            return taskState
        } catch {
            logger.error("Failed to load task state: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Lists all pending tasks that can be recovered
    /// - Returns: Array of task states
    public func listPendingTasks() async -> [TaskState] {
        do {
            let fileManager = FileManager.default
            
            // Get all task files
            let taskFiles = try fileManager.contentsOfDirectory(
                at: taskStateURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            ).filter { $0.pathExtension == "json" }
            
            // Load each task
            var tasks: [TaskState] = []
            for taskFile in taskFiles {
                do {
                    let data = try Data(contentsOf: taskFile)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    
                    let task = try decoder.decode(TaskState.self, from: data)
                    
                    // Only include tasks that are not completed
                    if task.status != .completed && task.status != .failed {
                        tasks.append(task)
                    }
                } catch {
                    // Skip files that can't be decoded
                    logger.error("Failed to decode task file \(taskFile.lastPathComponent): \(error.localizedDescription)")
                    continue
                }
            }
            
            // Sort by last updated time
            tasks.sort { $0.updatedAt > $1.updatedAt }
            
            logger.info("Found \(tasks.count) pending tasks")
            return tasks
        } catch {
            logger.error("Failed to list pending tasks: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Completes a task and archives its state
    /// - Parameter taskID: Task identifier
    public func completeTask(_ taskID: UUID) async {
        do {
            let taskFileURL = taskStateURL.appendingPathComponent("\(taskID.uuidString).json")
            
            // Check if task exists
            guard FileManager.default.fileExists(atPath: taskFileURL.path) else {
                logger.warning("Task not found for completion: \(taskID.uuidString)")
                return
            }
            
            // Update task status to completed
            await updateTaskState(taskID) { task in
                task.status = .completed
                task.completedAt = Date()
            }
            
            // Move to completed folder (optional archiving)
            let completedDir = taskStateURL.appendingPathComponent("completed", isDirectory: true)
            try FileManager.default.createDirectory(at: completedDir, withIntermediateDirectories: true)
            
            let archivedFileURL = completedDir.appendingPathComponent("\(taskID.uuidString).json")
            try FileManager.default.moveItem(at: taskFileURL, to: archivedFileURL)
            
            logger.info("Task completed and archived: \(taskID.uuidString)")
        } catch {
            logger.error("Failed to complete task: \(error.localizedDescription)")
        }
    }
    
    /// Marks a task as failed
    /// - Parameters:
    ///   - taskID: Task identifier
    ///   - error: Error information
    public func failTask(_ taskID: UUID, error: String) async {
        await updateTaskState(taskID) { task in
            task.status = .failed
            task.error = error
            task.completedAt = Date()
        }
        
        logger.warning("Task marked as failed: \(taskID.uuidString) - \(error)")
    }
    
    /// Recovers from a crash by checking for incomplete tasks
    /// - Returns: Array of tasks that need recovery
    public func recoverFromCrash() async -> [TaskState] {
        // Find tasks that were in progress
        let pendingTasks = await listPendingTasks()
        
        // Filter to only tasks that were actually started
        let recoveryTasks = pendingTasks.filter { $0.status == .inProgress }
        
        if !recoveryTasks.isEmpty {
            logger.info("Found \(recoveryTasks.count) tasks to recover")
        }
        
        return recoveryTasks
    }
    
    /// Prioritizes and sorts tasks for recovery
    /// - Parameter tasks: Tasks to sort
    /// - Returns: Sorted tasks
    public func prioritizeRecoveryTasks(_ tasks: [TaskState]) -> [TaskState] {
        // First, sort by recovery priority (higher priority first)
        let sortedByPriority = tasks.sorted { task1, task2 in
            // Get priority - critical tasks first
            let priority1 = task1.recoveryPriority
            let priority2 = task2.recoveryPriority
            
            if priority1 != priority2 {
                return priority1 > priority2
            }
            
            // If same priority, sort by time (newer first)
            return task1.updatedAt > task2.updatedAt
        }
        
        // Then group by whether they can be auto-recovered
        let (autoRecover, manualRecover) = sortedByPriority.reduce(into: ([], [])) { result, task in
            if task.canAutoRecover {
                result.0.append(task)
            } else {
                result.1.append(task)
            }
        }
        
        // Auto-recoverable tasks first, then manual recovery tasks
        return autoRecover + manualRecover
    }
    
    /// Handles recovery of a specific task
    /// - Parameter task: Task to recover
    /// - Returns: Success status
    public func handleTaskRecovery(_ task: TaskState) async -> Bool {
        logger.info("Recovering task: \(task.id?.uuidString ?? "unknown") - \(task.description)")
        
        // Update task status to indicate recovery attempt
        if let id = task.id {
            await updateTaskState(id) { task in
                task.status = .recovering
                task.retryCount += 1
            }
        }
        
        // The actual recovery logic depends on the task type
        switch task.type {
        case .aiCommand:
            return await recoverAICommand(task)
        case .userCommand:
            return await recoverUserCommand(task)
        case .fileOperation:
            return await recoverFileOperation(task)
        case .sessionState:
            return await recoverSessionState(task)
        default:
            logger.warning("Unknown task type for recovery: \(task.type)")
            return false
        }
    }
    
    /// Recovers an AI-generated command
    /// - Parameter task: AI command task to recover
    /// - Returns: Whether recovery was successful
    private func recoverAICommand(_ task: TaskState) async -> Bool {
        // We need access to the AI coordinator for this
        // In a real implementation, we would inject this dependency
        guard let commandData = task.data as? AICommandData,
              let aiCoordinator = getAICoordinator() else {
            logger.error("Failed to recover AI command: missing data or coordinator")
            return false
        }
        
        // Attempt to re-execute through AI coordinator
        do {
            logger.info("Recovering AI command: \(commandData.command)")
            
            // Convert AIMode from string
            let aiMode: AIMode = AIMode(rawValue: commandData.aiMode) ?? .auto
            
            // Re-execute the command through the AI coordinator
            let result = try await aiCoordinator.reExecuteCommand(
                commandData.command,
                mode: aiMode,
                context: commandData.context ?? [:]
            )
            
            // Mark task as completed
            if let taskID = task.id {
                await completeTask(taskID)
            }
            
            logger.info("AI command recovery successful")
            return true
        } catch {
            logger.error("AI command recovery failed: \(error.localizedDescription)")
            
            // Mark task as failed
            if let taskID = task.id {
                await failTask(taskID, error: error.localizedDescription)
            }
            return false
        }
    }
    
    /// Recovers a user command
    /// - Parameter task: User command task to recover
    /// - Returns: Whether recovery was successful
    private func recoverUserCommand(_ task: TaskState) async -> Bool {
        guard let commandData = task.data as? UserCommandData else {
            logger.error("Failed to recover user command: missing data")
            return false
        }
        
        logger.info("Recovering user command: \(commandData.command)")
        
        do {
            // Get command execution service
            let executionService = CommandExecutionService()
            
            // Change working directory if specified
            if let workingDir = commandData.workingDirectory {
                try executionService.changeWorkingDirectory(workingDir)
            }
            
            // Set environment variables if specified
            if let env = commandData.environment {
                executionService.updateEnvironment(env)
            }
            
            // Execute the command
            let result = try await executionService.executeCommand(commandData.command)
            
            // Log result
            logger.info("Recovered command executed with exit code: \(result.exitCode)")
            
            // Mark task as completed
            if let taskID = task.id {
                await completeTask(taskID)
            }
            
            return result.isSuccessful
        } catch {
            logger.error("User command recovery failed: \(error.localizedDescription)")
            
            // Mark task as failed
            if let taskID = task.id {
                await failTask(taskID, error: error.localizedDescription)
            }
            return false
        }
    }
    
    /// Recovers a file operation
    /// - Parameter task: File operation task to recover
    /// - Returns: Whether recovery was successful
    private func recoverFileOperation(_ task: TaskState) async -> Bool {
        guard let fileData = task.data as? FileOperationData else {
            logger.error("Failed to recover file operation: missing data")
            return false
        }
        
        logger.info("Recovering file operation: \(fileData.operation.rawValue) on \(fileData.sourcePath)")
        
        do {
            let fileManager = FileManager.default
            
            // Handle different file operations
            switch fileData.operation {
            case .write:
                // Re-write the file
                if let content = fileData.content {
                    try content.write(
                        to: URL(fileURLWithPath: fileData.sourcePath),
                        atomically: true,
                        encoding: .utf8
                    )
                }
                
            case .append:
                // Re-append to the file
                if let content = fileData.content {
                    let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: fileData.sourcePath))
                    fileHandle.seekToEndOfFile()
                    if let data = content.data(using: .utf8) {
                        fileHandle.write(data)
                    }
                    fileHandle.closeFile()
                }
                
            case .move:
                // Re-move the file
                if let destPath = fileData.destinationPath {
                    try fileManager.moveItem(
                        atPath: fileData.sourcePath,
                        toPath: destPath
                    )
                }
                
            case .copy:
                // Re-copy the file
                if let destPath = fileData.destinationPath {
                    try fileManager.copyItem(
                        atPath: fileData.sourcePath,
                        toPath: destPath
                    )
                }
                
            case .createDirectory:
                // Re-create the directory
                try fileManager.createDirectory(
                    atPath: fileData.sourcePath,
                    withIntermediateDirectories: true
                )
                
            case .delete:
                // For delete operations, we need to be more careful
                // We'll only recover deletes if explicitly requested
                if task.context?["forceRecoverDelete"] == "true" {
                    try fileManager.removeItem(atPath: fileData.sourcePath)
                } else {
                    logger.warning("Skipping recovery of delete operation for safety")
                }
                
            case .read:
                // Read operations don't need recovery
                logger.info("Read operation doesn't need recovery")
            }
            
            // Mark task as completed
            if let taskID = task.id {
                await completeTask(taskID)
            }
            
            return true
        } catch {
            logger.error("File operation recovery failed: \(error.localizedDescription)")
            
            // Mark task as failed
            if let taskID = task.id {
                await failTask(taskID, error: error.localizedDescription)
            }
            return false
        }
    }
    
    /// Recovers terminal session state
    /// - Parameter task: Session state task to recover
    /// - Returns: Whether recovery was successful
    private func recoverSessionState(_ task: TaskState) async -> Bool {
        guard let sessionData = task.data as? SessionStateData else {
            logger.error("Failed to recover session state: missing data")
            return false
        }
        
        logger.info("Recovering session state for session \(sessionData.sessionId)")
        
        // In a real implementation, we would find the terminal session by ID
        // and restore its state. For now, we'll just mark it as complete.
        if let taskID = task.id {
            await completeTask(taskID)
        }
        
        return true
    }
    
    /// Gets the AITerminalCoordinator for task recovery
    /// In a real implementation, this would be injected as a dependency
    private func getAICoordinator() -> AITerminalCoordinator? {
        // This is a placeholder - in a real app this would come from the AppState
        return AITerminalCoordinator()
    }
}</replace

