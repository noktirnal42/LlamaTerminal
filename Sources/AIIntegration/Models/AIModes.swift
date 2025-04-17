import Foundation
import SwiftUI

/// Represents the different AI assistance modes available in the terminal
public enum AIMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case auto
    case dispatch
    case command
    case code
    case disabled

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .auto:
            return "Auto Assistant"
        case .dispatch:
            return "Task Dispatcher"
        case .command:
            return "Command Assistant"
        case .code:
            return "Code Assistant"
        case .disabled:
            return "Disabled"
        }
    }

    public var systemImage: String {
        switch self {
        case .auto:
            return "wand.and.stars"
        case .dispatch:
            return "list.bullet.clipboard"
        case .command:
            return "terminal"
        case .code:
            return "chevron.left.forwardslash.chevron.right"
        case .disabled:
            return "nosign"
        }
    }

    public var description: String {
        switch self {
        case .auto:
            return "Automatically detects context and provides relevant assistance"
        case .dispatch:
            return "Breaks complex tasks into steps and guides you through them"
        case .command:
            return "Helps with terminal commands and explains their usage"
        case .code:
            return "Assists with coding tasks and debugging"
        case .disabled:
            return "No AI assistance"
        }
    }
}

/// Protocol for AI mode handlers
public protocol AIModeHandler: Sendable {
    nonisolated var model: String { get }
    /// Initializes the handler with a specific model
    init(model: String)

    /// Gets the current state of the handler
    func getState() async -> AIModeState

    /// Processes new terminal input
    func processInput(_ input: String) async throws -> AIModeResponse

    /// Handles command execution results
    func handleCommandResult(_ result: CommandResult) async throws -> AIModeResponse

    /// Resets the handler state
    func reset() async
}

/// Represents the state of an AI mode handler
public struct AIModeState: Codable, Sendable {
    /// Whether the mode is currently active
    public var isActive: Bool

    /// The current context being tracked
    public var context: [String]

    /// Any pending suggestions or actions
    public var pendingActions: [AIAction]

    public init(isActive: Bool = true, context: [String] = [], pendingActions: [AIAction] = []) {
        self.isActive = isActive
        self.context = context
        self.pendingActions = pendingActions
    }
}

/// Represents a response from an AI mode handler
public struct AIModeResponse: Codable, Sendable {
    /// Any suggestions for the user
    public let suggestions: [CommandSuggestion]

    /// Actions that can be executed automatically
    public let actions: [AIAction]

    /// Additional context or information for the user
    public let context: String?

    public init(
        suggestions: [CommandSuggestion] = [],
        actions: [AIAction] = [],
        context: String? = nil
    ) {
        self.suggestions = suggestions
        self.actions = actions
        self.context = context
    }
}

/// Represents a command suggestion from the AI
public struct CommandSuggestion: Codable, Sendable {
    /// The suggested command
    public let command: String

    /// Explanation of what the command does
    public let explanation: String

    /// Safety level of the command
    public let safetyLevel: CommandSafetyLevel

    /// Whether the command requires confirmation
    public let requiresConfirmation: Bool

    public init(
        command: String,
        explanation: String,
        safetyLevel: CommandSafetyLevel = .safe,
        requiresConfirmation: Bool = false
    ) {
        self.command = command
        self.explanation = explanation
        self.safetyLevel = safetyLevel
        self.requiresConfirmation = requiresConfirmation
    }
}

/// Represents an action that can be taken by the AI
public struct AIAction: Codable, Sendable {
    /// Type of the action
    public let type: AIActionType

    /// The command or code to execute
    public let content: String

    /// Whether the action requires user confirmation
    public let requiresConfirmation: Bool

    /// Additional context or metadata
    public let metadata: [String: String]

    public init(
        type: AIActionType,
        content: String,
        requiresConfirmation: Bool = true,
        metadata: [String: String] = [:]
    ) {
        self.type = type
        self.content = content
        self.requiresConfirmation = requiresConfirmation
        self.metadata = metadata
    }
}

/// Types of actions the AI can take
public enum AIActionType: String, Codable, Sendable {
    case executeCommand
    case generateCode
    case modifyFile
    case installPackage
    case planTask
}

/// Safety levels for commands
public enum CommandSafetyLevel: String, Codable, Sendable {
    case safe
    case moderate
    case destructive
}

/// Result of a command execution
public struct CommandResult: Codable, Sendable {
    /// The command that was executed
    public let command: String

    /// The output of the command
    public let output: String

    /// The exit code of the command
    public let exitCode: Int

    /// Duration of the command execution
    public let duration: TimeInterval

    public init(
        command: String,
        output: String,
        exitCode: Int,
        duration: TimeInterval
    ) {
        self.command = command
        self.output = output
        self.exitCode = exitCode
        self.duration = duration
    }
}
