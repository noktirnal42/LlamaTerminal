import SwiftUI
import TerminalCore
import AIIntegration

// NOTE: This file was moved from Sources/App/AppState.swift

@MainActor // Isolate the entire class to the main actor
public class AppState: ObservableObject { // Made public for cross-module access
    // Terminal tabs
    @Published public var terminalTabs: [TerminalTab] = [] // Made public
    @Published public var selectedTabIndex: Int = 0 // Made public

    // AI Assistant state
    @Published public var showAIPanel: Bool = false // Made public
    @Published public var currentAIMode: AIMode = .disabled // Made public
    @Published public var showModelSelectionSheet: Bool = false // Made public
    @Published public var showCommandHistorySheet: Bool = false // Made public
    @Published public var selectedModel: AIModel? // Made public
    @Published public var availableModels: [AIModel] = [] // Made public

    // Terminal customization
    @Published public var isDarkMode: Bool = true // Made public
    @Published public var fontSize: CGFloat = 12.0 // Made public

    // History and context
    @Published public var commandHistory: [CommandHistoryItem] = [] // Made public

    // Model Management State (for ModelSelectionView)
    @Published public var isPullingModel: Bool = false // Made public
    @Published public var pullProgress: Double = 0.0 // Made public
    @Published public var pullStatusMessage: String = "" // Made public
    @Published public var loadingError: Error? = nil // Explicit error state, made public

    // User preferences
    private let userDefaults = UserDefaults.standard
    private let ollamaService = OllamaModelService() // Changed to let
    public init() { // Made public
        // Load user preferences
        loadUserPreferences()

        // Initialize with a single terminal tab (must be done on main actor)
        Task { [weak self] in
            self?.addNewTab() // Already on MainActor due to class annotation
        }
        // If there's a last used model, try to load it and show panel
        if let lastModelName = userDefaults.string(forKey: "lastUsedModel"), !lastModelName.isEmpty {
             // Trigger model loading/selection logic after init completes
             Task { [weak self] in // Use weak self capture
                  // refreshAvailableModels is already @MainActor
                  try? await self?.refreshAvailableModels()
             }
             // Optionally show AI panel based on whether a model exists
             // showAIPanel = true // Consider if this should always happen
         } else {
             // No last used model, default to disabled or another state
             currentAIMode = .disabled
         }

        // Load AI Mode preference
         if let modeRawValue = userDefaults.string(forKey: "aiMode"),
            let mode = AIMode(rawValue: modeRawValue) {
             currentAIMode = mode
         }
        
        // Save initial preferences or maybe rely on explicit saves?
        // savePreferences() // Moved save calls to specific actions
    }

    /// Toggle dark mode for the terminal
    public func toggleDarkMode() { // Made public
        isDarkMode.toggle()
        savePreferences()
    }

    /// Increase font size
    public func increaseFontSize() { // Made public
        fontSize = min(fontSize + 1, 20.0)
        savePreferences()
    }

    /// Decrease font size
    public func decreaseFontSize() { // Made public
        fontSize = max(fontSize - 1, 9.0)
        savePreferences()
    }

    /// Reset font size to default
    public func resetFontSize() { // Made public
        fontSize = 12.0
        savePreferences()
    }

    /// Set the current AI mode
    public func setAIMode(_ mode: AIMode) { // Made public
        currentAIMode = mode
        savePreferences()
    }

    /// Load user preferences from UserDefaults
    private func loadUserPreferences() {
        // Terminal appearance
        isDarkMode = userDefaults.bool(forKey: "isDarkMode")
        fontSize = userDefaults.object(forKey: "fontSize") as? CGFloat ?? 12.0

        // AI panel state
        showAIPanel = userDefaults.bool(forKey: "showAIPanel")

        // AI mode (loaded in init)
        // selectedModel name is loaded in init/refreshAvailableModels
    }

    /// Save current preferences to UserDefaults
    public func savePreferences() { // Made public
        userDefaults.set(isDarkMode, forKey: "isDarkMode")
        userDefaults.set(fontSize, forKey: "fontSize")
        userDefaults.set(showAIPanel, forKey: "showAIPanel")
        userDefaults.set(currentAIMode.rawValue, forKey: "aiMode")

        if let model = selectedModel {
            userDefaults.set(model.name, forKey: "lastUsedModel")
        } else {
             userDefaults.removeObject(forKey: "lastUsedModel") // Clear if no model selected
        }
    }

    /// Fetches the list of available Ollama models and updates the state.
    /// Throws an error if the fetch fails.
    // @MainActor removed - implied by class annotation
    public func refreshAvailableModels() async throws { // Made public
        print("Attempting to refresh available models...")
        do {
            // Call the actor method directly. Swift concurrency handles the actor hop.
            let models = try await ollamaService.listModels()

            // Updates below run on MainActor implicitly because AppState is @MainActor
            self.availableModels = models
            print("Successfully refreshed available models: \(models.count) found.")

            // Restore last selected model if it's still available
            let lastModelName = self.userDefaults.string(forKey: "lastUsedModel")
            if let lastModelName = lastModelName, !lastModelName.isEmpty,
               let lastModel = models.first(where: { $0.name == lastModelName }) {
                if self.selectedModel?.name != lastModel.name {
                     self.selectedModel = lastModel
                     print("Restored last used model: \(lastModelName)")
                }
            } else if self.selectedModel == nil {
                // Select the first model if none was selected or the last one is gone
                self.selectedModel = models.first
                if let firstModel = models.first {
                   self.userDefaults.set(firstModel.name, forKey: "lastUsedModel")
                   print("Selected first available model: \(firstModel.name)")
                } else {
                    // No models available, clear last used
                    self.userDefaults.removeObject(forKey: "lastUsedModel")
                }
            } else if let currentSelectedModel = self.selectedModel, !models.contains(where: { $0.name == currentSelectedModel.name }) {
                 // Current selection is no longer valid, select first available or nil
                 self.selectedModel = models.first
                 if let firstModel = models.first {
                    self.userDefaults.set(firstModel.name, forKey: "lastUsedModel")
                    print("Previously selected model gone. Selected first available: \(firstModel.name)")
                 } else {
                    self.userDefaults.removeObject(forKey: "lastUsedModel")
                    print("Previously selected model gone. No models available.")
                 }
            }

        } catch {
            print("Error fetching available models: \(error)")
            // Consider clearing models or keeping stale list based on UX
            // self.availableModels = []
            throw error // Re-throw for the view to handle
        }
    }

    /// Add a new terminal tab
    // @MainActor removed - implied by class annotation
    public func addNewTab() { // Made public
        let newSession = TerminalSession()
        let newTab = TerminalTab(title: "Terminal \(terminalTabs.count + 1)", session: newSession)
        terminalTabs.append(newTab)
        selectedTabIndex = terminalTabs.count - 1
    }

    /// Close a terminal tab at the specified index
    // @MainActor removed - implied by class annotation
    public func closeTab(at index: Int) { // Made public
        guard index < terminalTabs.count else { return }

        // Terminate the session
        terminalTabs[index].session.terminateSession()

        // Remove the tab
        terminalTabs.remove(at: index)

        // Adjust selected tab index if needed
        if selectedTabIndex >= terminalTabs.count {
            selectedTabIndex = max(0, terminalTabs.count - 1)
        }

        // If no tabs remain, add a new one
        if terminalTabs.isEmpty {
            addNewTab()
        }
    }

    /// Initiates pulling a new model from Ollama. Updates published properties for progress.
    // @MainActor removed - implied by class annotation
    public func pullModel(name: String) { // Made public
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("Model name cannot be empty.")
            // Optionally set an error message
            // self.loadingError = NSError(domain: "AppState", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model name cannot be empty."])
            return
        }

        // Update state immediately (already on MainActor)
        self.isPullingModel = true
        self.pullProgress = 0.0
        self.pullStatusMessage = "Starting download for '\(name)'..."
        self.loadingError = nil

        Task {
            do {
                let stream = try await ollamaService.pullModel(modelName: name)
                for try await progressUpdate in stream {
                    // Update progress on main actor
                    await MainActor.run {
                        self.pullProgress = progressUpdate.progress
                        self.pullStatusMessage = progressUpdate.status
                    }
                }
                // Finished successfully
                await MainActor.run {
                    self.pullStatusMessage = "Successfully pulled model '\(name)'!"
                    self.isPullingModel = false // Mark as done here before refresh
                }
                // Refresh the model list
                try await refreshAvailableModels() // Already ensures it runs on main actor if needed

            } catch {
                // Handle errors
                print("Error pulling model '\(name)': \(error)")
                await MainActor.run {
                    self.loadingError = error
                    self.pullStatusMessage = "Error: \(error.localizedDescription)"
                    self.isPullingModel = false
                }
            }
        }
    }

    /// Deletes the specified model from Ollama.
    // @MainActor removed - implied by class annotation
    public func deleteModel(_ model: AIModel) { // Made public
        print("Attempting to delete model: \(model.name)")
        self.loadingError = nil // Clear previous errors

        Task {
            do {
                try await ollamaService.deleteModel(modelName: model.name)
                print("Successfully deleted model '\(model.name)'")

                // Refresh the list after deletion
                try await refreshAvailableModels() // Already ensures it runs on main actor if needed

            } catch {
                print("Error deleting model '\(model.name)': \(error)")
                await MainActor.run {
                    self.loadingError = error
                }
            }
        }
    }
}

// Terminal tab structure
public struct TerminalTab: Identifiable { // Made public
	public var id = UUID()
    public var title: String
    public var session: TerminalSession

    // Public initializer if needed outside the module
    public init(id: UUID = UUID(), title: String, session: TerminalSession) {
        self.id = id
        self.title = title
        self.session = session
    }
}

// AI modes
public enum AIMode: String, CaseIterable, Identifiable { // Made public
    case disabled
    case auto
    case dispatch
    case code
    case command

    public var id: String { self.rawValue }

    public var displayName: String { // Made public
        switch self {
        case .disabled: return "AI Disabled"
        case .auto: return "Auto Mode"
        case .dispatch: return "Dispatch Mode"
        case .code: return "Code Assistant"
        case .command: return "Command Assistant"
        }
    }

    public var systemImage: String { // Made public
        switch self {
        case .disabled: return "brain.slash"
        case .auto: return "brain"
        case .dispatch: return "list.bullet.rectangle"
        case .code: return "curlybraces"
        case .command: return "terminal"
        }
    }
}

// Command history item
public struct CommandHistoryItem: Identifiable { // Made public
    public let id: UUID // Made public
    public let command: String // Made public
    public let output: String // Made public
    public let timestamp: Date // Made public
    public let isAIGenerated: Bool // Made public

    // Public initializer
     public init(id: UUID = UUID(), command: String, output: String, timestamp: Date, isAIGenerated: Bool) {
         self.id = id
         self.command = command
         self.output = output
         self.timestamp = timestamp
         self.isAIGenerated = isAIGenerated
     }
}

