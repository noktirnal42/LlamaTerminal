import Foundation

/// Handler for Auto Mode - provides context-aware suggestions based on terminal activity
public actor AutoModeHandler: AIModeHandler {
    // MARK: - Properties
    
    /// The AI model used by this handler
    public let model: String
    
    /// Current state of the handler
    private var state: AIModeState = AIModeState()
    
    /// Service for parsing and analyzing commands
    private let parsingService: CommandParsingService
    
    /// Service for AI completions
    private let completionService: ChatCompletionService
    
    /// Current AI model details
    private var aiModel: AIModel?
    
    /// Context tracking
    private var contextHistory: [ContextEntry] = []
    private let maxContextSize = 50 // Maximum number of entries to keep
    
    /// Pattern detector for identifying common tasks
    private let patternDetector = CommandPatternDetector()
    
    /// Cooldown mechanism to avoid too frequent suggestions
    private var lastSuggestionTime: Date = Date.distantPast
    private let suggestionCooldown: TimeInterval = 5.0 // Seconds between suggestions
    
    /// Structure to track context entries with timestamps
    private struct ContextEntry: Codable, Sendable {
        let timestamp: Date
        let content: String
        let isCommand: Bool
        let exitCode: Int?
        
        init(content: String, isCommand: Bool, exitCode: Int? = nil) {
            self.timestamp = Date()
            self.content = content
            self.isCommand = isCommand
            self.exitCode = exitCode
        }
    }
    
    // MARK: - Initialization
    
    /// Initializes a new handler with the specified AI model
    /// - Parameter model: Name of the AI model to use
    public init(model: String) {
        self.model = model
        self.parsingService = CommandParsingService()
        self.completionService = ChatCompletionService()
    }
    
    /// Initializes a new handler with the specified AI model and services
    /// - Parameters:
    ///   - model: Name of the AI model to use
    ///   - parsingService: Service for parsing and analyzing commands
    ///   - completionService: Service for AI completions
    ///   - aiModel: The AI model details
    public init(
        model: String,
        parsingService: CommandParsingService,
        completionService: ChatCompletionService = ChatCompletionService(),
        aiModel: AIModel? = nil
    ) {
        self.model = model
        self.parsingService = parsingService
        self.completionService = completionService
        self.aiModel = aiModel
    }
    
    // MARK: - AIModeHandler Implementation
    
    /// Gets the current state of the handler
    public func getState() -> AIModeState {
        return state
    }
    
    /// Processes new terminal input
    /// - Parameter input: User's terminal input
    /// - Returns: Response with suggestions
    public func processInput(_ input: String) async throws -> AIModeResponse {
        // Add to context history
        addToContext(input, isCommand: true)
        
        // Check if this is a complex command that might need assistance
        let isComplex = isComplexCommand(input)
        
        // Detect command pattern
        let detectedPattern = patternDetector.detectPattern(in: input)
        
        // If command is complex or matches a known pattern, generate suggestions
        if isComplex || detectedPattern != nil {
            return try await generateSuggestions(
                for: input,
                patternType: detectedPattern,
                priority: .immediate
            )
        }
        
        // For simple commands, don't generate immediate suggestions
        // but update state for potential future suggestions
        state.context.append(input)
        
        // Return empty response
        return AIModeResponse()
    }
    
    /// Handles the result of a command execution
    /// - Parameter result: CommandResult
    /// - Returns: Response with next action or completion summary
    public func handleCommandResult(_ result: CommandResult) async throws -> AIModeResponse {
        // Add result to context history
        addToContext("Output: \(result.output)", isCommand: false, exitCode: result.exitCode)
        
        // Check for error condition
        let hasError = result.exitCode != 0
        
        // If command failed, offer help
        if hasError {
            return try await generateErrorAssistance(for: result)
        }
        
        // If enough context has built up, check for proactive suggestion opportunity
        if shouldGenerateProactiveSuggestion() {
            return try await generateProactiveSuggestion()
        }
        
        // No immediate suggestion needed
        return AIModeResponse()
    }
    
    /// Resets the handler state
    public func reset() async {
        state = AIModeState()
        contextHistory = []
    }
    
    // MARK: - Private Methods
    
    /// Adds an entry to the context history with tracking information
    /// - Parameters:
    ///   - content: The content to add
    ///   - isCommand: Whether this is a command or output
    ///   - exitCode: Optional exit code for command results
    private func addToContext(_ content: String, isCommand: Bool, exitCode: Int? = nil) {
        let entry = ContextEntry(content: content, isCommand: isCommand, exitCode: exitCode)
        contextHistory.append(entry)
        
        // Limit context size by removing oldest entries when exceeding maximum
        if contextHistory.count > maxContextSize {
            contextHistory.removeFirst(contextHistory.count - maxContextSize)
        }
        
        // Update state context as well
        state.context.append(content)
        if state.context.count > maxContextSize {
            state.context.removeFirst(state.context.count - maxContextSize)
        }
    }
    
    /// Determines if a command is complex enough to warrant suggestions
    /// - Parameter command: The command string
    /// - Returns: True if complex
    private func isComplexCommand(_ command: String) -> Bool {
        // Check for pipes, redirections, multiple commands, etc.
        let hasComplexOperators = command.contains("|") || 
                                  command.contains(">") || 
                                  command.contains("<") ||
                                  command.contains("&&") ||
                                  command.contains("||") ||
                                  command.contains(";")
        
        // Check for complex tools
        let complexTools = ["find", "grep", "sed", "awk", "xargs", "curl", "docker", "kubectl"]
        let usesComplexTool = complexTools.contains { command.hasPrefix($0) }
        
        // Check for flags
        let hasManyFlags = command.matches(of: /\s-{1,2}[a-zA-Z0-9]+/).count >= 3
        
        return hasComplexOperators || usesComplexTool || hasManyFlags
    }
    
    /// Checks if enough time has passed and context accumulated to generate a proactive suggestion
    /// - Returns: True if should generate suggestion
    private func shouldGenerateProactiveSuggestion() -> Bool {
        // Check cooldown timer
        let now = Date()
        let timeSinceLastSuggestion = now.timeIntervalSince(lastSuggestionTime)
        guard timeSinceLastSuggestion >= suggestionCooldown else {
            return false
        }
        
        // Need at least a few context entries to make useful suggestions
        guard contextHistory.count >= 3 else {
            return false
        }
        
        // Detect patterns in recent history that suggest assistance could be helpful
        let recentCommands = contextHistory.suffix(5).filter { $0.isCommand }.map { $0.content }
        let hasRepeatedCommands = Set(recentCommands).count < recentCommands.count
        
        // Check for error patterns
        let recentErrors = contextHistory.suffix(5).filter { ($0.exitCode ?? 0) != 0 }.count
        
        return hasRepeatedCommands || recentErrors >= 1
    }
    
    /// Generates proactive suggestions based on context history
    /// - Returns: Response with suggestions
    private func generateProactiveSuggestion() async throws -> AIModeResponse {
        // Update suggestion timer
        lastSuggestionTime = Date()
        
        // Prepare context for AI by extracting relevant parts of history
        let relevantContext = prepareContextForAI()
        
        // Create system message for proactive suggestion generation
        let systemPrompt = """
        You are an AI terminal assistant that proactively helps users.
        Analyze the command history and suggest ways to improve efficiency or solve recurring issues.
        
        Focus on these types of suggestions:
        1. More efficient alternatives to repeated commands
        2. Useful shortcut commands or aliases
        3. Solutions for recurring errors
        4. Command enhancements that would save time
        
        Respond with a small number of highly relevant suggestions in this format:
        
        SUGGESTIONS:
        - Suggestion: <command>
          Explanation: <brief explanation>
          Safety: <safe/moderate/destructive>
        
        - Suggestion: <command>
          Explanation: <brief explanation>
          Safety: <safe/moderate/destructive>
        
        END SUGGESTIONS
        
        Keep your suggestions focused, practical, and specifically relevant to what the user is doing.
        Consider the most recent commands more heavily than older ones.
        If no suggestions are appropriate, respond with "NO_SUGGESTIONS".
        """
        
        // Generate proactive suggestions
        let suggestion = try await generateAIResponse(
            systemPrompt: systemPrompt,
            userMessage: "Command History:\n\(relevantContext)",
            temperature: 0.4
        )
        
        // Parse the suggestion into a response
        return try await parseSuggestionResponse(suggestion, priority: .background)
    }
    
    /// Generates suggestions for a specific input
    /// - Parameters:
    ///   - input: The user input
    ///   - patternType: Optional detected pattern type
    ///   - priority: Suggestion priority
    /// - Returns: Response with suggestions
    private func generateSuggestions(
        for input: String,
        patternType: CommandPatternType?,
        priority: SuggestionPriority
    ) async throws -> AIModeResponse {
        // Update suggestion timer
        lastSuggestionTime = Date()
        
        // Prepare context for AI
        let relevantContext = prepareContextForAI()
        
        // Create system message based on the pattern type and input
        let systemPrompt = createSystemPrompt(for: patternType, input: input)
        
        // Generate suggestions from AI
        let userMessage = """
        Command: \(input)
        
        Recent Context:
        \(relevantContext)
        """
        
        let aiResponse = try await generateAIResponse(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            temperature: priority == .immediate ? 0.5 : 0.7
        )
        
        // Parse the AI response into structured suggestions
        return try await parseSuggestionResponse(aiResponse, priority: priority)
    }
    
    /// Generates assistance for error recovery
    /// - Parameter result: The failed command result
    /// - Returns: Response with suggestions
    private func generateErrorAssistance(for result: CommandResult) async throws -> AIModeResponse {
        // Update suggestion timer
        lastSuggestionTime = Date()
        
        // Create system message focused on error recovery
        let systemPrompt = """
        You are an AI terminal assistant specialized in fixing command errors.
        Analyze the failed command and its error output to suggest solutions.
        
        Respond with specific command suggestions in this format:
        
        ERROR ANALYSIS:
        <brief analysis of the error>
        
        SUGGESTIONS:
        - Suggestion: <command>
          Explanation: <explanation of how this fixes the issue>
          Safety: <safe/moderate/destructive>
        
        - Suggestion: <command>
          Explanation: <explanation of how this fixes the issue>
          Safety: <safe/moderate/destructive>
        
        END SUGGESTIONS
        
        Focus on practical solutions that are most likely to resolve the issue.
        """
        
        // Prepare context including recent commands
        let recentCommands = contextHistory.suffix(5)
            .filter { $0.isCommand }
            .map { $0.content }
            .joined(separator: "\n")
        
        // Generate error assistance
        let userMessage = """
        Failed Command: \(result.command)
        Exit Code: \(result.exitCode)
        Error Output:
        \(result.output)
        
        Recent Commands:
        \(recentCommands)
        """
        
        let aiResponse = try await generateAIResponse(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            temperature: 0.4  // Lower temperature for more focused error help
        )
        
        // Parse the AI response with high priority since this is error recovery
        return try await parseSuggestionResponse(aiResponse, priority: .immediate)
    }
    
    /// Prepares the context history for AI input
    /// - Returns: Formatted context string
    private func prepareContextForAI() -> String {
        // Extract the most recent and relevant context entries
        let entries = contextHistory.suffix(20)
        
        // Format the entries for AI consumption
        var formattedEntries: [String] = []
        
        for entry in entries {
            let timestamp = timestampFormatter.string(from: entry.timestamp)
            let prefix = entry.isCommand ? "Command" : "Output"
            let status = entry.exitCode.map { code in
                code == 0 ? "Success" : "Error (code \(code))"
            } ?? ""
            
            formattedEntries.append("[\(timestamp)] \(prefix): \(entry.content) \(status)")
        }
        
        return formattedEntries.joined(separator: "\n")
    }
    
    /// Creates a system prompt based on the detected pattern and input
    /// - Parameters:
    ///   - patternType: The detected command pattern
    ///   - input: The user input
    /// - Returns: Customized system prompt
    private func createSystemPrompt(for patternType: CommandPatternType?, input: String) -> String {
        let basePrompt = """
        You are an AI terminal assistant that provides helpful suggestions.
        Analyze the command and context to provide targeted assistance.
        
        Respond with actionable suggestions in this format:
        
        SUGGESTIONS:
        - Suggestion: <command>
          Explanation: <brief explanation>
          Safety: <safe/moderate/destructive>
        
        - Suggestion: <command>
          Explanation: <brief explanation>
          Safety: <safe/moderate/destructive>
        
        END SUGGESTIONS
        
        Keep your suggestions relevant, practical, and specifically focused on the user's current task.
        Suggest only 2-3 of the most helpful commands.
        If no suggestions are appropriate, respond with "NO_SUGGESTIONS".
        """
        
        // If we detected a specific pattern, add specialized instructions
        if let patternType = patternType {
            switch patternType {
            case .fileManagement:
                return basePrompt + "\n\nThis command involves file operations. Focus on efficient file management, backup suggestions, or improved syntax for file operations."
                
            case .searchPattern:
                return basePrompt + "\n\nThis command involves searching. Suggest more efficient search approaches, filtering options, or ways to process the search results."
                
            case .networkOperation:
                return basePrompt +

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
