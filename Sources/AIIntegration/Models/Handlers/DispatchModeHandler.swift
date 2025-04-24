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
    
    /// Service for AI completions
    private let completionService: ChatCompletionService
    
    /// Current AI model details
    private var aiModel: AIModel?

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
        self.completionService = ChatCompletionService()
    }

    /// Initializes a new handler with the specified AI model and services
    /// Initializes a new handler with the specified AI model and services
    /// - Parameters:
    ///   - model: Name of the AI model to use
    ///   - commandService: Service for executing commands
    ///   - parsingService: Service for parsing and analyzing commands
    ///   - completionService: Service for AI completions
    ///   - aiModel: The AI model details
    public init(
        model: String,
        commandService: CommandService,
        parsingService: CommandParsingService,
        completionService: ChatCompletionService = ChatCompletionService(),
        aiModel: AIModel? = nil
    ) {
        self.model = model
        self.commandService = commandService
        self.parsingService = parsingService
        self.completionService = completionService
        self.aiModel = aiModel
    }
    // MARK: - AIModeHandler Implementation

    /// Gets the current state of the handler
    public func getState() -> AIModeState {
        return state
    }

    /// Processes new terminal input to create a task plan
    /// - Parameter input: User's terminal input
    /// Handles the result of a command execution
    /// - Parameter result: CommandResult
    /// - Returns: Response with next action or completion summary
    public func handleCommandResult(_ result: CommandResult) async throws -> AIModeResponse {
        // Record result with timestamp for better context
        let timestamp = ISO8601DateFormatter().string(from: Date())
        taskContext.append("Step \(currentStep + 1) result [at \(timestamp)]: \(result.command)")
        taskContext.append("Exit code: \(result.exitCode)")
        
        // Limit output size but keep important parts
        var truncatedOutput = result.output
        if truncatedOutput.count > 2000 {
            // Keep first and last parts of long outputs
            let firstPart = String(truncatedOutput.prefix(1000))
            let lastPart = String(truncatedOutput.suffix(1000))
            truncatedOutput = firstPart + "\n[...output truncated...]\n" + lastPart
        }
        taskContext.append("Output: \(truncatedOutput)")
        
        // Handle command failure
        if result.exitCode != 0 {
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
        // First, check if we have an AI model to use
        if aiModel == nil {
            // Create a basic AIModel to use for planning
            let capabilities = ModelCapabilities(
                isCodeCapable: false,
                isMultimodal: false, 
                isCommandOptimized: true
            )
            aiModel = AIModel(
                id: model,
                name: model,
                size: 0,
                modified: Date(),
                capabilities: capabilities
            )
        }
        
        guard let aiModel = aiModel else {
            // Fallback to basic parsing if no model is available
            return try await fallbackParsing(for: input)
        }
        
        // Create system message with instructions
        let systemPrompt = """
        You are a terminal assistant that breaks down complex tasks into executable steps.
        Analyze the user's request and create a detailed plan with the necessary commands.
        
        Each command should be assessed for:
        1. Safety - could this command potentially damage the system?
        2. Reversibility - can the effects be undone?
        3. Required permissions - does it need special access?
        4. Dependencies - does it require specific tools to be installed?
        
        Respond with a structured plan in this format:
        
        PLAN:
        - Step 1: <command>
          - Explanation: <what this command does>
          - Safety Level: <safe/moderate/destructive>
          - Requires Confirmation: <true/false>
        
        - Step 2: <command>
          - Explanation: <what this command does>
          - Safety Level: <safe/moderate/destructive>
          - Requires Confirmation: <true/false>
        
        ... and so on for each step
        
        END OF PLAN
        
        Focus on creating a practical and efficient plan that accomplishes the user's request.
        """
        
        let userMessage = "Task: \(input)"
        
        // Create message array for the AI model
        let messages: [ChatMessage] = [
            ChatMessage(role: .system, content: systemPrompt),
            ChatMessage(role: .user, content: userMessage)
        ]
        
        // Determine optimal temperature based on task complexity
        let temperature = input.contains(" && ") || input.contains(";") || input.contains("|") ? 0.3 : 0.7
        
        // Use ChatCompletionService to generate the plan
        var planText = ""
        let completionStream = try await completionService.generateChatCompletion(
            model: aiModel,
            messages: messages,
            temperature: temperature,
            stream: true
        )
        
        // Collect the entire response
        for await chunk in completionStream {
            planText += chunk.content
        }
        
        // Parse the AI-generated plan into actions
        return try await parsePlanToActions(planText)
    }
    
    /// Parses an AI-generated plan into executable actions
    /// - Parameter planText: The AI-generated plan text
    /// - Returns: Array of actions to execute
    private func parsePlanToActions(_ planText: String) async throws -> [AIAction] {
        var actions: [AIAction] = []
        
        // Extract the plan section
        guard let planStartIndex = planText.range(of: "PLAN:")?.upperBound,
              let planEndIndex = planText.range(of: "END OF PLAN")?.lowerBound else {
            // If no properly formatted plan is found, try basic parsing
            return extractCommandsFromText(planText)
        }
        
        let planSection = String(planText[planStartIndex..<planEndIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Split into steps
        let stepRegex = try NSRegularExpression(pattern: #"- Step \d+: (.*?)(?=\n- Step \d+:|$)"#, options: [.dotMatchesLineSeparators])
        let range = NSRange(planSection.startIndex..<planSection.endIndex, in: planSection)
        let matches = stepRegex.matches(in: planSection, options: [], range: range)
        
        for match in matches {
            if let stepRange = Range(match.range, in: planSection) {
                let stepContent = String(planSection[stepRange])
                
                // Extract command
                guard let commandLineRange = stepContent.range(of: #": (.+)$"#, options: .regularExpression) else {
                    continue
                }
                
                let startIndex = stepContent.index(commandLineRange.lowerBound, offsetBy: 2) // Skip ": "
                let command = String(stepContent[startIndex..<commandLineRange.upperBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Extract explanation (for metadata)
                var explanation = ""
                if let explanationRange = stepContent.range(of: #"Explanation: (.+)$"#, options: .regularExpression) {
                    let startIndex = stepContent.index(explanationRange.lowerBound, offsetBy: 13) // Skip "Explanation: "
                    explanation = String(stepContent[startIndex..<explanationRange.upperBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                // Extract safety level
                var safetyLevel = CommandSafetyLevel.safe
                if let safetyRange = stepContent.range(of: #"Safety Level: (.+)$"#, options: .regularExpression) {
                    let startIndex = stepContent.index(safetyRange.lowerBound, offsetBy: 14) // Skip "Safety Level: "
                    let safetyText = String(stepContent[startIndex..<safetyRange.upperBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                    
                    if safetyText.contains("destructive") {
                        safetyLevel = .destructive
                    } else if safetyText.contains("moderate") {
                        safetyLevel = .moderate
                    }
                }
                
                // Extract confirmation requirement
                var requiresConfirmation = safetyLevel != .safe
                if let confirmRange = stepContent.range(of: #"Requires Confirmation: (.+)$"#, options: .regularExpression) {
                    let startIndex = stepContent.index(confirmRange.lowerBound, offsetBy: 23) // Skip "Requires Confirmation: "
                    let confirmText = String(stepContent[startIndex..<confirmRange.upperBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                    
                    requiresConfirmation = confirmText == "true"
                }
                
                // Always require confirmation for destructive commands
                if safetyLevel == .destructive {
                    requiresConfirmation = true
                }
                
                // Create metadata
                var metadata: [String: String] = [:]
                if !explanation.isEmpty {
                    metadata["explanation"] = explanation
                }
                metadata["safetyLevel"] = safetyLevel.rawValue
                
                // Create and add the action
                let action = AIAction(
                    type: .executeCommand,
                    content: command,
                    requiresConfirmation: requiresConfirmation,
                    metadata: metadata
                )
                
                actions.append(action)
            }
        }
        
        // If no actions were parsed, fall back to basic extraction
        if actions.isEmpty {
            return extractCommandsFromText(planText)
        }
        
        return actions
    }
    
    /// Extract commands from unstructured text when parsing fails
    /// - Parameter text: The AI-generated text
    /// - Returns: Array of actions to execute
    private func extractCommandsFromText(_ text: String) -> [AIAction] {
        // Look for command patterns in the text
        let commandPatterns = [
            #"`([^`]+)`"#, // Commands in backticks
            #"```(?:bash|shell)?\s*\n([\s\S]*?)\n```"#, // Commands in code blocks
            #"(?:^|\n)(?:\$\s*|\#\s*)([\w\s\-\./\\=\":;|><&{}[\]()$*?!+^]+)(?:$|\n)"# // Lines starting with $ or #
        ]
        
        var commands: [String] = []
        
        for pattern in commandPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                let matches = regex.matches(in: text, options: [], range: range)
                
                for match in matches {
                    // Extract the command from the captured group
                    if match.numberOfRanges > 1, let captureRange = Range(match.range(at: 1), in: text) {
                        let command = String(text[captureRange])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if !command.isEmpty && !commands.contains(command) {
                            commands.append(command)
                        }
                    }
                }
            }
        }
        
        // Convert commands to actions
        return commands.map { command in
            // Perform basic safety assessment
            let containsDestructiveCommands = command.contains("rm ") || 
                                             command.contains("sudo ") || 
                                             command.contains("dd ") || 
                                             command.contains(":(){:|:&};:") // Fork bomb
            
            let safetyLevel: CommandSafetyLevel = containsDestructiveCommands ? .destructive : .moderate
            
            return AIAction(
                type: .executeCommand,
                content: command,
                require

    /// Generates a recovery plan when a command fails
    /// - Parameter result: Failed command result
    /// - Returns: Array of recovery actions
    private func generateRecoveryPlan(for result: CommandResult) async throws -> [AIAction] {
        guard let aiModel = aiModel else {
            // Fallback to basic recovery if no model is available
            return [
                AIAction(
                    type: .executeCommand,
                    content: "echo \"Error recovery: Command '\(result.command)' failed with exit code \(result.exitCode)\"",
                    requiresConfirmation: false,
                    metadata: ["fallback": "true"]
                )
            ]
        }
        
        // Create system message with instructions for recovery
        let systemPrompt = """
        You are a terminal troubleshooter specialized in fixing command errors.
        Analyze the failed command and its error output to determine what went wrong.
        Then generate a recovery plan with specific steps to fix the issue.
        
        Common error types to consider:
        1. Command not found - Check if software needs to be installed
        2. Permission denied - Consider if sudo is needed
        3. File not found - Check paths, create directories, or download files
        4. Syntax errors - Correct command syntax or format
        5. Network errors - Check connectivity or try alternative sources
        6. Resource limitations - Modify command to use less resources
        
        Respond with a structured recovery plan in this format:
        
        RECOVERY PLAN:
        - Issue Analysis: <brief analysis of what went wrong>
        
        - Step 1: <recovery command>
          - Purpose: <what this step fixes>
          - Safety Level: <safe/moderate/destructive>
          - Requires Confirmation: <true/false>
        
        - Step 2: <recovery command>
          - Purpose: <what this step fixes>
          - Safety Level: <safe/moderate/destructive>
          - Requires Confirmation: <true/false>
        
        ... and so on for each step
        
        - Final Step: <retry original command or alternative>
          - Purpose: <explanation>
          - Safety Level: <safe/moderate/destructive>
          - Requires Confirmation: <true/false>
        
        END OF PLAN
        
        Focus on practical solutions that preserve user data and system integrity.
        Always favor safer approaches when multiple options exist.
        """
        
        // Create user message with full context
        var contextHistory = taskContext.joined(separator: "\n")
        if contextHistory.count > 4000 {
            // Truncate if needed to avoid token limits
            contextHistory = String(contextHistory.suffix(4000))
        }
        
        let userMessage = """
        Failed Command: \(result.command)
        Exit Code: \(result.exitCode)
        Error Output:
        \(result.output)
        
        Context History:
        \(contextHistory)
        """
        
        // Create message array for the AI model
        let messages: [ChatMessage] = [
            ChatMessage(role: .system, content: systemPrompt),
            ChatMessage(role: .user, content: userMessage)
        ]
        
        // Use lower temperature for error recovery (more conservative)
        let temperature = 0.4
        
        // Use ChatCompletionService to generate the recovery plan
        var planText = ""
        do {
            let completionStream = try await completionService.generateChatCompletion(
                model: aiModel,
                messages: messages,
                temperature: temperature,
                stream: true
            )
            
            // Collect the entire response
            for await chunk in completionStream {
                planText += chunk.content
            }
            
            // Parse the AI-generated recovery plan into actions
            var recoveryActions = try await parseRecoveryPlan(planText)
            
            // If we couldn't get a proper plan, return a basic fallback
            if recoveryActions.isEmpty {
                recoveryActions = [
                    AIAction(
                        type: .executeCommand,
                        content: "echo \"Failed to generate recovery plan. Original error: Command '\(result.command)' failed with exit code \(result.exitCode)\"",
                        requiresConfirmation: false,
                        metadata: ["error": "recovery_failed"]
                    )
                ]
            }
            
            return recoveryActions
            
        } catch {
            // Handle AI service errors gracefully
            return [
                AIAction(
                    type: .executeCommand,
                    content: "echo \"Error recovery failed: \(error.localizedDescription)\"",
                    requiresConfirmation: false,
                    metadata: ["error": "service_error"]
                )
            ]
        }
    }
    
    /// Parses an AI-generated recovery plan into executable actions
    /// - Parameter planText: The AI-generated recovery plan text
    /// - Returns: Array of recovery actions
    private func parseRecoveryPlan(_ planText: String) async throws -> [AIAction] {
        var actions: [AIAction] = []
        
        // Extract the plan section
        guard let planStartIndex = planText.range(of: "RECOVERY PLAN:")?.upperBound,
              let planEndIndex = planText.range(of: "END OF PLAN")?.lowerBound else {
            // If no properly formatted plan is found, try basic parsing
            return extractCommandsFromText(planText)
        }
        
        let planSection = String(planText[planStartIndex..<planEndIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Extract issue analysis for context
        var issueAnalysis = ""
        if let analysisRange = planSection.range(of: "- Issue Analysis: (.+?)(?=\n-)", options: [.regularExpression, .dotMatchesLineSeparators]) {
            let startIndex = planSection.index(analysisRange.lowerBound, offsetBy: 17) // Skip "- Issue Analysis: "
            issueAnalysis = String(planSection[startIndex..<analysisRange.upperBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Add analysis as a first informational step if available
        if !issueAnalysis.isEmpty {
            actions.append(
                AIAction(
                    type: .executeCommand,
                    content: "echo \"Analysis: \(issueAnalysis.replacingOccurrences(of: "\"", with: "\\\""))\"",
                    requiresConfirmation: false,
                    metadata: ["type": "analysis"]
                )
            )
        }
        
        // Split into steps (including the final step)
        let stepRegex = try NSRegularExpression(
            pattern: #"- (?:Step \d+|Final Step): (.*?)(?=\n- (?:Step \d+|Final Step):|$)"#,
            options: [.dotMatchesLineSeparators]
        )
        let range = NSRange(planSection.startIndex..<planSection.endIndex, in: planSection)
        let matches = stepRegex.matches(in: planSection, options: [], range: range)
        
        for match in matches {
            if let stepRange = Range(match.range, in: planSection) {
                let stepContent = String(planSection[stepRange])
                
                // Extract command
                guard let commandLineRange = stepContent.range(of: #": (.+)$"#, options: .regularExpression) else {
                    continue
                }
                
                let startIndex = stepContent.index(commandLineRange.lowerBound, offsetBy: 2) // Skip ": "
                let command = String(stepContent[startIndex..<commandLineRange.upperBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Extract purpose (for metadata)
                var purpose = ""
                if let purposeRange = stepContent.range(of: #"Purpose: (.+)$"#, options: .regularExpression) {
                    let startIndex = stepContent.index(purposeRange.lowerBound, offsetBy: 9) // Skip "Purpose: "
                    purpose = String(stepContent[startIndex..<purposeRange.upperBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                // Extract safety level
                var safetyLevel = CommandSafetyLevel.moderate // Default to moderate for recovery
                if let safetyRange = stepContent.range(of: #"Safety Level: (.+)$"#, options: .regularExpression) {
                    let startIndex = stepContent.index(safetyRange.lowerBound, offsetBy: 14) // Skip "Safety Level: "
                    let safetyText = String(stepContent[startIndex..<safetyRange.upperBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                    
                    if safetyText.contains("safe") {
                        safetyLevel = .safe
                    } else if safetyText.contains("destructive") {
                        safetyLevel = .destructive
                    }
                }
                
                // Extract confirmation requirement
                var requiresConfirmation = safetyLevel != .safe // Default based on safety
                if let confirmRange = stepContent.range(of: #"Requires Confirmation: (.+)$"#, options: .regularExpression) {
                    let startIndex = stepContent.index(confirmRange.lowerBound, offsetBy: 23) // Skip "Requires Confirmation: "
                    let confirmText = String(stepContent[startIndex..<confirmRange.upperBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                    
                    requiresConfirmation = confirmText == "true"
                }
                
                // Always require confirmation for destructive commands
                if safetyLevel == .destructive {
                    requiresConfirmation = true
                }
                
                // Create metadata
                var metadata: [String: String] = ["recovery": "true"]
                if !purpose.isEmpty {
                    metadata["purpose"] = purpose
                }
                metadata["safetyLevel"] = safetyLevel.rawValue
                if stepContent.contains("Final Step") {
                    metadata["finalStep"] = "true"
                }
                
                // Create and add the action
                let action = AIAction(
                    type: .executeCommand,
                    content: command,
                    requiresConfirmation: requiresConfirmation,
                    metadata: metadata
                )
                
                actions.append(action)
            }
        }
        
        return actions
    }

    /// Generates a summary of the task execution
    /// - Returns: Summary text
    private func generateCompletionSummary() async -> String {
        // If no AI model is available or context is minimal, return a simple summary
        if aiModel == nil || taskContext.count <= 2 {
            return "Task completed successfully (\(taskPlan.count) steps executed)"
        }
        
        // Calculate basic metrics
        let totalSteps = taskPlan.count
        let executedSteps = currentStep
        let hasRecoveryActions = taskContext.contains { $0.contains("Recovery plan created") }
        
        // Create system message with instructions for summary generation
        let systemPrompt = """
        You are an AI terminal assistant that summarizes task execution results.
        Analyze the provided task context and generate a concise but informative summary.
        
        Your summary should include:
        1. What the original task intended to accomplish
        2. Key operations that were performed
        3. Any warnings, errors, or recovery actions that occurred
        4. The end result and success status
        5. Relevant metrics such as execution time or affected resources
        
        Use a clear and concise format with terminal-friendly formatting:
        - Use emoji or symbols to highlight important points
        - Keep the summary under 6 lines for readability
        - Include the most important metrics only
        - Format commands or filenames in `monospace` when mentioned
        
        The summary should be direct and informative without unnecessary explanations.
        """
        
        // Prepare context for AI
        var contextHistory = taskContext.joined(separator: "\n")
        if contextHistory.count > 4000 {
            // If context is too large, keep the beginning and end for context
            let start = String(contextHistory.prefix(1500))
            let end = String(contextHistory.suffix(2500))
            contextHistory = start + "\n[...abbreviated history...]\n" + end
        }
        
        // Calculate approximate execution time from context if possible
        var executionTimeNote = ""
        if let firstCommandIndex = taskContext.firstIndex(where: { $0.contains("Step 1 result:") }),
           firstCommandIndex < taskContext.count - 1 {
            let stepsExecuted = currentStep
            executionTimeNote = "Steps completed: \(stepsExecuted)/\(totalSteps)"
            
            if hasRecoveryActions {
                executionTimeNote += " (with recovery steps)"
            }
        }
        
        // Create user message with full context
        let userMessage = """
        Task Execution Summary Request
        
        Task History:
        \(contextHistory)
        
        Metrics:
        - Total planned steps: \(totalSteps)
        - Steps executed: \(executedSteps)
        - Recovery operations: \(hasRecoveryActions ? "Yes" : "No")
        \(executionTimeNote)
        """
        
        // Create message array for the AI model
        let messages: [ChatMessage] = [
            ChatMessage(role: .system, content: systemPrompt),
            ChatMessage(role: .user, content: userMessage)
        ]
        
        do {
            guard let aiModel = aiModel else {
                throw NSError(domain: "AIIntegration", code: 1, userInfo: [NSLocalizedDescriptionKey: "No AI model available"])
            }
            
            // Use a moderate temperature for creative but not wild summaries
            let temperature = 0.5
            
            // Use ChatCompletionService to generate the completion summary
            var summaryText = ""
            let completionStream = try await completionService.generateChatCompletion(
                model: aiModel,
                messages: messages,
                temperature: temperature,
                stream: true
            )
            
            // Collect the entire response
            for await chunk in completionStream {
                summaryText += chunk.content
            }
            
            // Process the summary for better display
            summaryText = formatSummaryForDisplay(summaryText)
            
            // Return the generated summary or fallback to a simple one if empty
            return summaryText.isEmpty 
                ? "✅ Task completed successfully (\(taskPlan.count) steps executed)"
                : summaryText
            
        } catch {
            // Handle AI service errors gracefully with a fallback summary
            return "✅ Task completed: \(executedSteps)/\(totalSteps) steps executed" + 
                   (hasRecoveryActions ? " (with recovery operations)" : "")
        }
    }
    
    /// Formats the AI-generated summary for better terminal display
    /// - Parameter summary: The raw summary from the AI
    /// - Returns: Formatted summary with enhancements
    private func formatSummaryForDisplay(_ summary: String) -> String {
        var formattedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Add emoji indicators if missing
        if !formattedSummary.contains("✅") && !formattedSummary.contains("❌") && 
           !formattedSummary.contains("⚠️") && !formattedSummary.contains("🔍") {
            formattedSummary = "✅ " + formattedSummary
        }
        
        // Replace markdown code blocks with terminal-friendly format if needed
        formattedSummary = formattedSummary.replacingOccurrences(
            of: "```[a-z]*\n([\\s\\S]*?)\n```",
            with: "`$1`",
            options: .regularExpression
        )
        
        // Ensure reasonable length (splitting into multiple lines if needed)
        let maxLineLength = 80
        let lines = formattedSummary.split(separator: "\n")
        var wrappedLines: [String] = []
        
        for line in lines {
            if line.count <= maxLineLength {
                wrappedLines.append(String(line))
            } else {
                // Simple word wrap for long lines
                var currentLine = ""
                for word in line.split(separator: " ") {
                    if currentLine.count + word.count + 1 <= maxLineLength {
                        if !currentLine.isEmpty {
                            currentLine += " "
                        }
                        currentLine += word
                    } else {
                        wrappedLines.append(currentLine)
                        currentLine = String(word)
                    }
                }
                if !currentLine.isEmpty {
                    wrappedLines.append(currentLine)
                }
            }
        }
        
        // Join with newlines and return
        return wrappedLines.joined(separator: "\n")
    }
}
