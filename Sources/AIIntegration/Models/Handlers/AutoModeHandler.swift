import Foundation

/// Handler for Auto Mode - provides automatic assistance based on terminal activity
public actor AutoModeHandler: AIModeHandler {
    // MARK: - Properties

    /// The AI model used by this handler
    public let model: String

    /// Current state of the handler
    private var state: AIModeState = AIModeState()

    /// Service for executing commands
    private let commandService: CommandService

    /// Service for parsing and analyzing commands
    private let parsingService: CommandParsingService

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

    /// Processes new terminal input
    /// - Parameter input: User's terminal input
    /// - Returns: Response with command suggestions
    public func processInput(_ input: String) async throws -> AIModeResponse {
        // Generate suggestions based on the input
        let suggestions = try await generateSuggestions(for: input)

        return AIModeResponse(
            suggestions: suggestions,
            context: "Based on your command"
        )
    }

    /// Handles the result of a command execution
    /// - Parameter result: Result of command execution
    /// - Returns: Response with context-specific feedback
    public func handleCommandResult(_ result: CommandResult) async throws -> AIModeResponse {
        // Analyze the command result
        let analysis = try await analyzeCommandResult(result)

        return AIModeResponse(
            suggestions: analysis.suggestions,
            context: analysis.context
        )
    }

    /// Resets the handler state
    public func reset() async {
        state = AIModeState()
    }

    // MARK: - Private Methods

    /// Generates command suggestions based on user input
    /// - Parameter input: User's terminal input
    /// - Returns: Array of command suggestions
    private func generateSuggestions(for input: String) async throws -> [CommandSuggestion] {
        // TODO: Implement AI-based suggestion generation
        // For now, implement a simple pattern-matching approach

        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedInput.hasPrefix("git") {
            return [
                CommandSuggestion(
                    command: "git status",
                    explanation: "Check the status of your git repository",
                    safetyLevel: .safe
                ),
                CommandSuggestion(
                    command: "git pull",
                    explanation: "Pull latest changes from the remote repository",
                    safetyLevel: .safe
                ),
            ]
        } else if trimmedInput.hasPrefix("ls") {
            return [
                CommandSuggestion(
                    command: "ls -la",
                    explanation: "List all files with detailed information",
                    safetyLevel: .safe
                )
            ]
        }

        // Default suggestions
        return [
            CommandSuggestion(
                command: "echo $PATH",
                explanation: "Display your PATH environment variable",
                safetyLevel: .safe
            )
        ]
    }

    /// Analyzes a command result and generates feedback
    /// - Parameter result: Result of command execution
    /// - Returns: Command suggestions and context based on result
    private func analyzeCommandResult(_ result: CommandResult) async throws -> (
        suggestions: [CommandSuggestion], context: String?
    ) {
        // TODO: Implement AI-based result analysis
        // For now, implement a simple pattern-matching approach

        // Check for error code
        if result.exitCode != 0 {
            // Suggest error recovery
            return (
                suggestions: [
                    CommandSuggestion(
                        command: "echo $?",
                        explanation: "Display the exit code of the previous command",
                        safetyLevel: .safe
                    )
                ],
                context: "The command failed with exit code \(result.exitCode)"
            )
        }

        // Check for git commands
        if result.command.hasPrefix("git") {
            return (
                suggestions: [
                    CommandSuggestion(
                        command: "git log --oneline -n 5",
                        explanation: "Show recent commit history",
                        safetyLevel: .safe
                    )
                ],
                context: "Git command completed successfully"
            )
        }

        // Default analysis
        return (
            suggestions: [],
            context: "Command completed successfully"
        )
    }
}
