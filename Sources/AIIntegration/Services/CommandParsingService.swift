import Foundation

/// Service responsible for parsing and validating AI responses into structured commands
public actor CommandParsingService: CommandParsingServiceProtocol {
    /// Regular expressions for command pattern matching
    private struct CommandPatterns {
        static let commandBlock = #"```(?:bash|shell|zsh|command)?\s*([^`]+)```"#
        static let commandWithExplanation = #"(?:Command|Run|Execute):\s*`([^`]+)`(?:\s*-\s*(.+))?"#
        static let suggestedCommand =
            #"(?:You can use|Try|Suggestion):\s*`([^`]+)`(?:\s*-\s*(.+))?"#
    }

    /// Set of potentially unsafe commands that require extra validation
    private let unsafeCommands: Set<String> = [
        "rm", "sudo", "mv", "cp", "chmod", "chown",
        ">", ">>", "|", "truncate", "dd",
    ]

    /// Set of commands that are always forbidden
    private let forbiddenCommands: Set<String> = [
        ":(){ :|:& };:",  // Fork bomb
        "rm -rf /",
        "rm -rf /*",
        "mkfs",
        ":()|:& ;:",
        "dd if=/dev/random",
        "dd if=/dev/zero",
        "> /dev/sda",
        "shutdown",
        "reboot",
        "halt",
        "poweroff",
    ]

    public init() {}

    /// Preprocesses AI response to clean up formatting
    /// - Parameter response: Raw AI response
    /// - Returns: Cleaned response
    public func preprocessResponse(_ response: String) async -> String {
        // Clean up common formatting issues
        return
            response
            .replacingOccurrences(of: "\n\n", with: "\n")  // Remove double line breaks
            .trimmingCharacters(in: .whitespacesAndNewlines)  // Trim whitespace
    }

    /// Parses command suggestions from AI response
    /// - Parameter response: AI-generated response
    /// - Returns: Array of structured command suggestions
    public func parseSuggestions(from response: String) async throws -> [CommandSuggestion] {
        var suggestions: [CommandSuggestion] = []

        // Try to match code blocks first, which are likely to contain commands
        let codeBlockPattern = try NSRegularExpression(pattern: CommandPatterns.commandBlock)
        let codeBlockMatches = codeBlockPattern.matches(
            in: response, range: NSRange(response.startIndex..., in: response))

        for match in codeBlockMatches {
            if let range = Range(match.range(at: 1), in: response) {
                let codeBlock = String(response[range])

                // Extract commands line by line
                let commands = codeBlock.split(separator: "\n")

                for command in commands {
                    let commandString = String(command).trimmingCharacters(
                        in: .whitespacesAndNewlines)
                    if !commandString.isEmpty && !commandString.hasPrefix("#") {
                        // Assume it's a valid command if not empty or a comment
                        suggestions.append(
                            CommandSuggestion(
                                command: commandString,
                                explanation: "Suggested command from code block",
                                safetyLevel: detectSafetyLevel(for: commandString),
                                requiresConfirmation: isDestructive(commandString)
                            ))
                    }
                }
            }
        }

        // Then try to match explicit command suggestions with explanations
        let commandPattern = try NSRegularExpression(
            pattern: CommandPatterns.commandWithExplanation)
        let commandMatches = commandPattern.matches(
            in: response, range: NSRange(response.startIndex..., in: response))

        for match in commandMatches {
            if let commandRange = Range(match.range(at: 1), in: response) {
                let command = String(response[commandRange]).trimmingCharacters(
                    in: .whitespacesAndNewlines)

                var explanation = "Execute this command"
                if match.numberOfRanges > 2,
                    let explanationRange = Range(match.range(at: 2), in: response)
                {
                    explanation = String(response[explanationRange])
                }

                suggestions.append(
                    CommandSuggestion(
                        command: command,
                        explanation: explanation,
                        safetyLevel: detectSafetyLevel(for: command),
                        requiresConfirmation: isDestructive(command)
                    ))
            }
        }

        // Finally, look for more general suggestions
        let suggestionPattern = try NSRegularExpression(pattern: CommandPatterns.suggestedCommand)
        let suggestionMatches = suggestionPattern.matches(
            in: response, range: NSRange(response.startIndex..., in: response))

        for match in suggestionMatches {
            if let commandRange = Range(match.range(at: 1), in: response) {
                let command = String(response[commandRange]).trimmingCharacters(
                    in: .whitespacesAndNewlines)

                var explanation = "Try this command"
                if match.numberOfRanges > 2,
                    let explanationRange = Range(match.range(at: 2), in: response)
                {
                    explanation = String(response[explanationRange])
                }

                suggestions.append(
                    CommandSuggestion(
                        command: command,
                        explanation: explanation,
                        safetyLevel: detectSafetyLevel(for: command),
                        requiresConfirmation: isDestructive(command)
                    ))
            }
        }

        // Remove duplicates
        var uniqueSuggestions: [CommandSuggestion] = []
        var seenCommands = Set<String>()

        for suggestion in suggestions {
            if !seenCommands.contains(suggestion.command) {
                seenCommands.insert(suggestion.command)
                uniqueSuggestions.append(suggestion)
            }
        }

        return uniqueSuggestions
    }

    /// Parses AI actions from AI response
    /// - Parameter response: AI-generated response
    /// - Returns: Array of structured AI actions
    public func parseActions(from response: String) async throws -> [AIAction] {
        // Simplified implementation for now - extract command execution actions
        let suggestions = try await parseSuggestions(from: response)

        return suggestions.map { suggestion in
            AIAction(
                type: .executeCommand,
                content: suggestion.command,
                requiresConfirmation: suggestion.requiresConfirmation,
                metadata: ["explanation": suggestion.explanation]
            )
        }
    }

    /// Checks if a command requires confirmation before execution
    /// - Parameter command: The command to check
    /// - Returns: Whether confirmation is required
    public func requiresConfirmation(_ command: String) -> Bool {
        return isDestructive(command)
    }

    // MARK: - Private helper methods

    /// Detects safety level for a command
    /// - Parameter command: The command to check
    /// - Returns: Safety level
    private func detectSafetyLevel(for command: String) -> CommandSafetyLevel {
        let lowercasedCommand = command.lowercased()

        // Check for destructive commands
        let destructivePatterns = [
            "rm -rf", "rm -r", "rmdir", "deltree",
            "dd", "mkfs", "format",
            "shutdown", "reboot", "halt",
            "> /dev", "> /etc", "> /usr", "> /System",
        ]

        for pattern in destructivePatterns {
            if lowercasedCommand.contains(pattern) {
                return .destructive
            }
        }

        // Check for moderate risk commands
        let moderatePatterns = [
            "sudo", "chown", "chmod",
            "kill", "passwd", "mv", "cp -f",
        ]

        for pattern in moderatePatterns {
            if lowercasedCommand.contains(pattern) {
                return .moderate
            }
        }

        // Default to safe
        return .safe
    }

    /// Determines if a command requires confirmation
    /// - Parameter command: The command to check
    /// - Returns: Whether confirmation is required
    private func isDestructive(_ command: String) -> Bool {
        return detectSafetyLevel(for: command) != .safe
    }
}

/// Extension to compare safety levels
extension CommandSafetyLevel {
    /// Checks if this safety level represents a higher risk than another
    func isHigherRisk(than other: CommandSafetyLevel) -> Bool {
        let riskOrder: [CommandSafetyLevel] = [.safe, .moderate, .destructive]
        guard let thisIndex = riskOrder.firstIndex(of: self),
            let otherIndex = riskOrder.firstIndex(of: other)
        else {
            return false
        }
        return thisIndex > otherIndex
    }
}

/// Errors that can occur during command validation
public enum CommandValidationError: Error, LocalizedError {
    case forbiddenCommand(String)
    case invalidCommand(String)
    case unsafeOperation(String)

    public var errorDescription: String? {
        switch self {
        case .forbiddenCommand(let command):
            return "Command is forbidden: \(command)"
        case .invalidCommand(let command):
            return "Invalid command format: \(command)"
        case .unsafeOperation(let operation):
            return "Unsafe operation detected: \(operation)"
        }
    }
}
