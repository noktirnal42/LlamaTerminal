// Import models
import Combine
import Foundation

/// Central coordinator for AI features in the terminal
public actor AITerminalCoordinator {
    // MARK: - Properties

    /// Currently selected AI model
    @Published public private(set) var currentModel: AIModel?

    /// Current AI mode
    @Published public private(set) var currentMode: AIMode = .disabled

    /// Whether AI features are initialized and ready
    @Published public private(set) var isReady: Bool = false

    /// Current state of the active mode handler
    @Published public private(set) var currentState: AIModeState = AIModeState()

    /// Service for accessing and managing Ollama models
    private let modelService: OllamaModelService

    /// Available AI models
    private var availableModels: [AIModel] = []

    /// Active mode handler (Auto or Dispatch)
    private var activeModeHandler: AIModeHandler?

    /// Command history for context
    private var commandHistory: [CommandHistoryEntry] = []

    /// Maximum command history entries to keep
    private let maxHistoryEntries: Int = 20

    /// Safety confirmation handler - Must be @Sendable
    private var safetyConfirmationHandler: (@Sendable (AIAction, @escaping @Sendable (Bool) -> Void) -> Void)?

    // MARK: - Initialization

    /// Initializes a new AITerminalCoordinator
    /// - Parameter modelService: Service for accessing Ollama models
    public init(modelService: OllamaModelService = OllamaModelService()) {
        self.modelService = modelService
    }

    // MARK: - Public Methods

    /// Initializes the AI system by fetching available models
    /// - Returns: True if initialization was successful
    public func initialize() async -> Bool {
        do {
            // Fetch available models from Ollama
            availableModels = try await modelService.listModels()

            // Find suitable default models
            if let defaultModel = selectDefaultModel() {
                await setModel(defaultModel)
            }

            isReady = !availableModels.isEmpty
            return isReady
        } catch {
            print("Failed to initialize AI system: \(error.localizedDescription)")
            isReady = false
            return false
        }
    }

    /// Sets the active AI model
    /// - Parameter model: Model to use
    public func setModel(_ model: AIModel) async {
        self.currentModel = model

        // Reconfigure active handler with new model if needed
        if currentMode != .disabled {
            await initializeHandler(for: currentMode, with: model)
        }
    }

    /// Sets the AI mode
    /// - Parameter mode: Mode to use
    public func setMode(_ mode: AIMode) async {
        // Skip if already in the requested mode
        if mode == currentMode {
            return
        }

        // Reset current handler if changing modes
        if let handler = activeModeHandler {
            await handler.reset()
        }

        self.currentMode = mode

        // Initialize the appropriate handler for the new mode
        if mode != .disabled, let model = currentModel {
            await initializeHandler(for: mode, with: model)
        } else {
            activeModeHandler = nil
            currentState = AIModeState(isActive: false)
        }
    }

    /// Processes terminal input through the active AI mode
    /// - Parameter input: User input to process
    /// - Returns: AI response for the input
    public func processInput(_ input: String) async throws -> AIModeResponse {
        guard currentMode != .disabled, let handler = activeModeHandler else {
            return AIModeResponse()  // Empty response if AI is disabled
        }

        // Add to command history for context
        addToCommandHistory(
            CommandHistoryEntry(
                command: input,
                timestamp: Date(),
                workingDirectory: nil,
                isAIAssisted: false,
                source: .user
            ))

        // Process through active handler
        let response = try await handler.processInput(input)

        // Store the state
        currentState = await handler.getState()

        // Return the processed response
        return response
    }

    /// Handles command execution results
    /// - Parameter result: Result of command execution
    /// - Returns: AI feedback on command result
    public func handleCommandResult(_ result: CommandResult) async throws -> AIModeResponse {
        guard currentMode != .disabled, let handler = activeModeHandler else {
            return AIModeResponse()  // Empty response if AI is disabled
        }

        // Add to command history for context
        addToCommandHistory(
            CommandHistoryEntry(
                command: result.command,
                output: result.output,
                exitCode: result.exitCode,
                timestamp: Date(),
                workingDirectory: nil,
                isAIAssisted: false,
                source: .system
            ))

        // Process through active handler
        let response = try await handler.handleCommandResult(result)

        // Store the state
        currentState = await handler.getState()

        // Return the processed response
        return response
    }

    /// Sets a handler for safety confirmations
    /// - Parameter handler: @Sendable function that will handle user confirmations
    public func setSafetyConfirmationHandler(
        _ handler: (@Sendable (AIAction, @escaping @Sendable (Bool) -> Void) -> Void)?
    ) {
        self.safetyConfirmationHandler = handler
    }

    /// Executes an AI action with safety checks
    /// - Parameter action: Action to execute
    /// - Returns: True if action will be executed (might be pending confirmation)
    public func executeAction(_ action: AIAction) async -> Bool {
        // Always require confirmation for destructive actions
        if action.requiresConfirmation {
            // If we have a confirmation handler, request confirmation
            if let confirmationHandler = safetyConfirmationHandler {
                // This is a bit tricky in actors, using a continuation
                return await withCheckedContinuation { continuation in
                    confirmationHandler(action) { confirmed in
                        continuation.resume(returning: confirmed)
                    }
                }
            } else {
                // No confirmation handler, fail safe by not executing
                return false
            }
        }

        // No confirmation needed, can execute directly
        return true
    }

    /// Gets a list of all available AI models
    /// - Returns: Array of available models
    public func getAvailableModels() -> [AIModel] {
        return availableModels
    }

    /// Gets models filtered by capability
    /// - Parameter capability: Capability filter (nil for all)
    /// - Returns: Array of models matching the capability
    public func getModels(withCapability capability: ModelCapabilityFilter? = nil) -> [AIModel] {
        guard let capability = capability else {
            return availableModels
        }

        return availableModels.filter { model in
            switch capability {
            case .code:
                return model.capabilities.isCodeCapable
            case .command:
                return model.capabilities.isCommandOptimized
            case .all:
                return true
            }
        }
    }

    /// Refreshes the available models list
    /// - Returns: True if refresh was successful
    public func refreshModels() async -> Bool {
        do {
            availableModels = try await modelService.listModels()

            // If current model was removed, select a new default
            if let currentModel = currentModel,
                !availableModels.contains(where: { $0.id == currentModel.id })
            {
                if let defaultModel = selectDefaultModel() {
                    await setModel(defaultModel)
                } else {
                    self.currentModel = nil
                    await setMode(.disabled)
                }
            }

            return true
        } catch {
            print("Failed to refresh models: \(error.localizedDescription)")
            return false
        }
    }

    /// Pulls a new model from Ollama
    /// - Parameter modelName: Name of the model to pull
    /// - Returns: Progress updates stream
    public func pullModel(_ modelName: String) async -> AsyncThrowingStream<PullProgress, Error> {
        do {
            return try await modelService.pullModel(modelName: modelName)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    /// Deletes a model from Ollama
    /// - Parameter model: Model to delete
    public func deleteModel(_ model: AIModel) async throws {
        try await modelService.deleteModel(modelName: model.name)

        // Refresh models after deletion
        _ = await refreshModels()
    }

    // MARK: - Private Methods

    /// Initializes the appropriate handler for the given mode
    /// - Parameters:
    ///   - mode: Mode to initialize
    ///   - model: Model to use
    private func initializeHandler(for mode: AIMode, with model: AIModel) async {
        switch mode {
        case .auto:
            activeModeHandler = AutoModeHandler(model: model.name)
        case .dispatch:
            activeModeHandler = DispatchModeHandler(model: model.name)
        case .command, .code:
            // These modes are not yet implemented
            activeModeHandler = nil
        case .disabled:
            activeModeHandler = nil
        }

        // Get initial state
        if let handler = activeModeHandler {
            currentState = await handler.getState()
        } else {
            currentState = AIModeState(isActive: false)
        }
    }

    /// Selects a default model based on available models
    /// - Returns: A suitable default model, or nil if none found
    private func selectDefaultModel() -> AIModel? {
        // First try to find a command-optimized model
        if let commandModel = availableModels.first(where: { $0.capabilities.isCommandOptimized }) {
            return commandModel
        }

        // Then try to find a general-purpose model like Llama
        if let generalModel = availableModels.first(where: {
            $0.name.lowercased().contains("llama")
        }) {
            return generalModel
        }

        // Finally, just use the first model if available
        return availableModels.first
    }

    /// Adds a command to the history, maintaining maximum size
    /// - Parameter entry: History entry to add
    private func addToCommandHistory(_ entry: CommandHistoryEntry) {
        commandHistory.append(entry)

        // Trim history if needed
        if commandHistory.count > maxHistoryEntries {
            commandHistory.removeFirst(commandHistory.count - maxHistoryEntries)
        }
    }
}
