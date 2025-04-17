import Foundation

/// Handler for Dispatch Mode - focuses on executing a series of planned steps
public actor DispatchModeHandler: AIModeHandler {
    // MARK: - Properties

    /// The AI model used by this handler
    public let model: String

    /// Current state of the handler
    private var state: AIModeState = AIModeState()

    /// Service for executing commands
    private let commandService: CommandService

    /// Service for parsing and analyzing commands
    private let parsingService: CommandParsingService

    /// Task plan tracking
    private var taskPlan: [AIAction] = []
    private var currentStep: Int = 0
    private var taskContext: [String] = []

    // MARK: - Initialization

    /// Initializes a new handler with the specified AI model
    /// - Parameter model: Name of the AI model to use
    public init(model: String) {
        self.model = model
        self.commandService = CommandService()
        self.parsingService = CommandParsingService()
    }

    /// Initializes a new handler with the specified AI model and services
    /// - Parameters:
    ///   - model: Name of the AI model to use
    ///   - commandService: Service for executing commands
    ///   - parsingService: Service for parsing and analyzing commands
    public init(
        model: String,
        commandService: CommandService,
        parsingService: CommandParsingService
    ) {
        self.model = model
        self.commandService = commandService
        self.parsingService = parsingService
    }

    // MARK: - AIModeHandler Implementation

    /// Gets the current state of the handler
    public func getState() -> AIModeState {
        return state
    }

    /// Processes new terminal input to create a task plan
    /// - Parameter input: User's terminal input
    /// - Returns: Response with the initial actions
    public func processInput(_ input: String) async throws -> AIModeResponse {
        // Reset task context
        taskContext = ["Original task: \(input)"]

        // Generate a plan of actions for the task
        let actions = try await generateTaskPlan(for: input)

        // Update state and tracking
        taskPlan = actions
        currentStep = 0
        state.pendingActions = actions

        // Return first action to execute
        return AIModeResponse(
            actions: [actions.first].compactMap { $0 },
            context: "Task planned with \(actions.count) steps"
        )
    }

    /// Handles the result of a command execution
    /// - Parameter result: CommandResult
    /// - Returns: Response with next action or completion summary
    public func handleCommandResult(_ result: CommandResult) async throws -> AIModeResponse {
        // Record result
        taskContext.append("Step \(currentStep + 1) result: \(result.command)")
        taskContext.append("Output: \(result.output)")

        // Handle command failure
        if result.exitCode != 0 {
            // Try to generate recovery actions
            let recoveryActions = try await generateRecoveryPlan(for: result)

            if recoveryActions.isEmpty {
                // If no recovery is possible, reset and report failure
                await reset()
                return AIModeResponse(context: "Task failed: Unable to recover from error")
            }

            // Update plan with recovery actions
            taskPlan = recoveryActions
            currentStep = 0
            state.pendingActions = recoveryActions

            return AIModeResponse(
                actions: [recoveryActions[0]],
                context: "Recovery plan created"
            )
        }

        // Move to next step
        currentStep += 1

        // Check for task completion
        if currentStep >= taskPlan.count {
            let summary = await generateCompletionSummary()
            await reset()
            return AIModeResponse(context: summary)
        }

        // Continue with the next step
        return AIModeResponse(
            actions: [taskPlan[currentStep]],
            context: "Proceeding with step \(currentStep + 1) of \(taskPlan.count)"
        )
    }

    /// Resets the handler state
    public func reset() async {
        state = AIModeState()
        taskPlan = []
        currentStep = 0
        taskContext = []
    }

    // MARK: - Private Methods

    /// Generates a task plan for the given input
    /// - Parameter input: User's terminal input
    /// - Returns: Array of actions to execute
    private func generateTaskPlan(for input: String) async throws -> [AIAction] {
        // TODO: Implement AI-based task planning
        // For now, implement a simple parser-based approach

        let taskComponents = input.split(separator: "&&").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var actions: [AIAction] = []
        for command in taskComponents {
            // Need to await the actor-isolated method
            let requiresConfirmation = await parsingService.requiresConfirmation(command)

            actions.append(
                AIAction(
                    type: .executeCommand,
                    content: command,
                    requiresConfirmation: requiresConfirmation,
                    metadata: [:]
                ))
        }

        return actions
    }

    /// Generates a recovery plan when a command fails
    /// - Parameter result: Failed command result
    /// - Returns: Array of recovery actions
    private func generateRecoveryPlan(for result: CommandResult) async throws -> [AIAction] {
        // TODO: Implement AI-based recovery planning
        // For now, implement a simple recovery approach

        // Simple recovery plan: just echo the error
        let recoveryCommand =
            "echo \"Error recovery: Command '\(result.command)' failed with exit code \(result.exitCode)\""

        return [
            AIAction(
                type: .executeCommand,
                content: recoveryCommand,
                requiresConfirmation: false,
                metadata: [:]
            )
        ]
    }

    /// Generates a summary of the task execution
    /// - Returns: Summary text
    private func generateCompletionSummary() async -> String {
        // TODO: Implement AI-based summary generation
        // For now, return a simple summary

        return "Task completed successfully (\(taskPlan.count) steps executed)"
    }
}
