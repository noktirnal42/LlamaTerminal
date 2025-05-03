import SwiftUI
import AIIntegration
import SharedModels
import AppKit

/// Panel that displays AI suggestions and interactions
public struct AIAssistantPanel: View {
    // MARK: - Environment & State
    
    /// Access to the global app state
    @EnvironmentObject private var appState: AppState
    
    /// Text input by the user
    @State private var inputText: String = ""
    
    /// Whether AI processing is happening
    @State private var isProcessing: Bool = false
    
    /// Current response from the AI
    @State private var assistantResponse: String = ""
    
    /// Suggested commands from the AI
    @State private var suggestedCommands: [CommandSuggestion] = []
    
    /// Flag to show command execution confirmation dialog
    @State private var showConfirmationDialog = false
    
    /// Command to be executed after confirmation
    @State private var commandToExecute: String = ""
    
    /// Whether the command is potentially destructive
    @State private var commandIsDestructive: Bool = false
    
    /// Recent commands from history
    @State private var recentCommands: [CommandHistoryEntry] = []
    
    /// Command history search query
    @State private var historySearchQuery: String = ""
    
    /// Whether to show command history
    @State private var showCommandHistory: Bool = false
    
    /// Loading state for model operations
    @State private var isLoadingModels: Bool = false
    
    /// Command service for history and execution
    private let commandService: CommandService?
    
    /// AI terminal coordinator for AI processing
    private let aiCoordinator: AITerminalCoordinator?
    
    // MARK: - Initialization
    
    /// Initialize with optional services for testing
    /// - Parameters:
    ///   - commandService: Optional command service for testing
    ///   - aiCoordinator: Optional AI coordinator for testing
    public init(commandService: CommandService? = nil, aiCoordinator: AITerminalCoordinator? = nil) {
        self.commandService = commandService
        self.aiCoordinator = aiCoordinator
    }
    
    // MARK: - Main View
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Content area based on AI mode
            ZStack {
                // Main content view
                ScrollView {
                    contentView
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Command history overlay (shown conditionally)
                if showCommandHistory {
                    commandHistoryView
                        .transition(.move(edge: .bottom))
                        .zIndex(1) // Ensure it's on top
                }
            }

            Divider()

            // Input area
            inputArea
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $showConfirmationDialog) {
            CommandExecutionConfirmationDialog(
                isPresented: $showConfirmationDialog,
                command: commandToExecute,
                isDestructive: commandIsDestructive,
                onExecute: {
                    executeCommand(commandToExecute)
                }
            )
        }
        .task {
            // Load recent commands when view appears
            await loadRecentCommands()
        }
    }

    /* // Original Body - Commented out due to errors
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Content area based on AI mode
            ScrollView {
                contentView
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Input area
            inputArea
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $showConfirmationDialog) {
            CommandExecutionConfirmationDialog(
                isPresented: $showConfirmationDialog,
                command: commandToExecute,
                isDestructive: commandIsDestructive,
                onExecute: {
                    executeCommand(commandToExecute)
                }
            )
        }
    }

    // MARK: - Subviews

    /// Header view displaying the current AI mode and actions
    private var headerView: some View {
        HStack {
            Label(appState.currentAIMode.displayName, systemImage: appState.currentAIMode.systemImage)
                .font(.headline)

            Spacer()

            // Add mode-specific actions or general controls here if needed
            if isProcessing {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
    }

    /// Main content view based on the current AI mode
    @ViewBuilder
    private var contentView: some View {
        switch appState.currentAIMode {
        case .disabled:
            disabledView
        case .auto:
            autoModeView
        case .dispatch:
            dispatchModeView
        case .code:
            codeModeView
        case .command:
            commandModeView
        }
    }

    /// View when AI is disabled
    private var disabledView: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("AI Assistant is Disabled")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Select an AI mode from the toolbar to enable assistance.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if appState.selectedModel == nil {
                 Text("No AI model selected. Please select one via the AI Assistant menu.")
                     .font(.caption)
                     .foregroundColor(.orange)
                     .padding(.top, 4)
            }

            Button("Select AI Mode...") {
                 // This should ideally open the mode selection menu in the toolbar,
                 // but direct control isn't straightforward. Guide the user.
                 print("User should select AI mode from toolbar menu.")
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    /// View for auto mode
    private var autoModeView: some View {
        genericResponseView // Auto mode might just show a generic response/chat interface
    }

    /// View for command mode
    private var commandModeView: some View {
        VStack(alignment: .leading) {
            if !assistantResponse.isEmpty {
                 responseHeader("Suggested Command")
                 ScrollView {
                     // Display the single suggested command
                     HStack {
                          Text(assistantResponse)
                              .font(.system(.body, design: .monospaced))
                              .textSelection(.enabled)
                          Spacer()
                          // Execute button
                          Button {
                              confirmCommand(assistantResponse) // Use confirmation helper
                          } label: {
                              Image(systemName: "terminal")
                          }
                          .buttonStyle(.plain)
                          .help("Execute Command")
                          // Copy button
                          Button {
                              copyToClipboard(assistantResponse)
                          } label: {
                              Image(systemName: "doc.on.doc")
                          }
                          .buttonStyle(.plain)
                          .help("Copy Command")
                     }
                     .padding(10)
                     .background(Color.black.opacity(0.1))
                     .cornerRadius(8)
                }
            } else if isProcessing {
                 ProgressView("Generating command suggestion...")
            } else {
                 Text("Enter a task to get a command suggestion.")
                     .foregroundColor(.secondary)
            }
        }
    }

    /// View for dispatch mode
    private var dispatchModeView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !assistantResponse.isEmpty {
                 // Assume response is a list of commands, parse it (basic split for now)
                 let suggestedCommands = assistantResponse.split(separator: "\n").map(String.init)

                 if !suggestedCommands.isEmpty {
                     responseHeader("Suggested Plan")
                     ScrollView {
                         VStack(alignment: .leading, spacing: 8) {
                             ForEach(suggestedCommands, id: \.self) { command in
                                 HStack {
                                     Text(command)
                                         .font(.system(.body, design: .monospaced))
                                         .textSelection(.enabled)
                                     Spacer()
                                     // Execute button
                                     Button {
                                         confirmCommand(command)
                                     } label: {
                                         Image(systemName: "terminal")
                                     }
                                     .buttonStyle(.plain)
                                     .help("Execute Command")
                                     // Copy button
                                     Button {
                                         copyToClipboard(command)
                                     } label: {
                                         Image(systemName: "doc.on.doc")
                                     }
                                     .buttonStyle(.plain)
                                     .help("Copy Command")
                                 }
                                 .padding(10)
                                 .background(Color.black.opacity(0.1))
                                 .cornerRadius(8)
                             }
                         }
                     }

                     // Button to execute the plan sequentially (needs careful implementation)
                     Button("Execute Plan") {
                         // TODO: Implement sequential execution with confirmation
                         // This would sequentially execute commands with confirmations
                         if let firstCommand = suggestedCommands.first {
                             confirmCommand(firstCommand)
                         }
                     }
                     .padding(.top, 8)
                 } else {
                      Text("Could not parse a plan from the response.")
                         .foregroundColor(.secondary)
                 }
            } else if isProcessing {
                 ProgressView("Generating execution plan...")
            } else {
                 Text("Describe a multi-step task to get an execution plan.")
                     .foregroundColor(.secondary)
            }
        }
    }

    /// View for code mode
    private var codeModeView: some View {
        VStack(alignment: .leading) {
            if !assistantResponse.isEmpty {
                 responseHeader("Generated Code")
                 ScrollView {
                    Text(assistantResponse) // Display raw code response for now
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(8)
                 }
                 // Add copy button for code
                 Button {
                     copyToClipboard(assistantResponse)
                 } label: {
                     Label("Copy Code", systemImage: "doc.on.doc")
                 }
                 .padding(.top, 8)
            } else if isProcessing {
                 ProgressView("Generating code...")
            } else {
                 Text("Ask for code generation or explanation.")
                     .foregroundColor(.secondary)
            }
        }
    }

    /// Generic view for displaying AI responses (used by Auto mode)
    private var genericResponseView: some View {
        VStack(alignment: .leading) {
            if !assistantResponse.isEmpty {
                 responseHeader("AI Response")
                 ScrollView {
                    Text(assistantResponse) // Display raw response
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.black.opacity(0.05)) // Slightly different background
                        .cornerRadius(8)
                 }
                 // Add copy button
                 Button {
                     copyToClipboard(assistantResponse)
                 } label: {
                     Label("Copy Response", systemImage: "doc.on.doc")
                 }
                 .padding(.top, 8)
            } else if isProcessing {
                 ProgressView("Waiting for response...")
            } else {
                 Text("Ask the AI assistant anything...")
                     .foregroundColor(.secondary)
            }
        }
    }

    /// Reusable header for response sections
    private func responseHeader(_ title: String) -> some View {
         HStack {
             Text(title)
                 .font(.headline)
                 // .foregroundColor(modeColor) // Needs modeColor definition
             Spacer()
         }
         .padding(.bottom, 4)
    }

    /// View for input area
    private var inputArea: some View {
        HStack {
            if appState.currentAIMode != .disabled {
                TextField("Ask the assistant...", text: $inputText, onCommit: {
                    sendMessage()
                })
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        // .foregroundColor(!inputText.isEmpty && !isProcessing ? modeColor : .gray) // Needs modeColor
                        .foregroundColor(!inputText.isEmpty && !isProcessing ? .blue : .gray) // Placeholder color
                }
                .disabled(inputText.isEmpty || isProcessing)
                .buttonStyle(.plain)

            } else {
                Text("AI Assistant is disabled")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center) // Added closing parenthesis
            }
        }
    }

    // MARK: - Helper Functions (Need implementation or moving)

    // These functions are called by the UI but not defined within this struct.
    // They likely need to be implemented here, moved from elsewhere, or interactions
    // should be handled via the AppState environment object.

    private func sendMessage() {
        print("sendMessage called. Input: \(inputText). Needs implementation.")
        // Guard !inputText.isEmpty, let model = appState.selectedModel else { return }
        // ... rest of the implementation using OllamaChatService ...
        // inputText = "" // Clear input after sending
    }

    private func confirmCommand(_ command: String) {
        print("confirmCommand called: \(command). Needs implementation.")
        // commandToExecute = command
        // commandIsDestructive = isDestructiveCommand(command) // isDestructiveCommand needs definition
        // showConfirmationDialog = true
    }

    private func executeCommand(_ command: String) {
        print("executeCommand called: \(command). Needs implementation.")
        // appState.executeCommandInTerminal(command) // Needs method on AppState
    }

    private func copyToClipboard(_ text: String) {
        print("copyToClipboard called. Needs implementation.")
        // NSPasteboard.general.clearContents()
        // NSPasteboard.general.setString(text, forType: .string)
    }

    // Needs definition or removal
    // private var modeColor: Color { ... }
    // private func isDestructiveCommand(_ command: String) -> Bool { ... }
 }
 */

    // MARK: - Subviews
    
    /// Header view displaying the current AI mode and actions
    private var headerView: some View {
        HStack {
            Label(appState.aiMode.displayName, systemImage: appState.aiMode.systemImage)
                .font(.headline)
                .foregroundColor(modeColor)

            Spacer()

            // Model selection indicator
            if let model = appState.currentAIModel {
                Text(model.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
            
            // Progress indicator
            if isProcessing || isLoadingModels {
                ProgressView()
                    .scaleEffect(0.7)
                    .padding(.horizontal, 4)
            }
            
            // Command history toggle
            Button {
                withAnimation {
                    showCommandHistory.toggle()
                    if showCommandHistory {
                        Task {
                            await loadRecentCommands()
                        }
                    }
                }
            } label: {
                Image(systemName: showCommandHistory ? "clock.fill" : "clock")
                    .foregroundColor(showCommandHistory ? modeColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Command History")
        }
    }

    /// Main content view based on the current AI mode
    @ViewBuilder
    private var contentView: some View {
        switch appState.aiMode {
        case .disabled:
            disabledView
        case .auto:
            autoModeView
        case .dispatch:
            dispatchModeView
        case .code:
            codeModeView
        case .command:
            commandModeView
        }
    }

    /// View when AI is disabled
    private var disabledView: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary)
                
            Text("AI Assistant is Disabled")
                .font(.title2)
                .foregroundColor(.secondary)
                
            Text("Select an AI mode from the toolbar to enable assistance.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if appState.currentAIModel == nil {
                Text("No AI model selected. Please select one via the AI Assistant menu.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.top, 4)
            }

            Button("Select AI Mode...") {
                // We can't directly control the toolbar menu, so we'll update app state instead
                if let model = appState.currentAIModel {
                    Task {
                        await appState.setAIMode(.auto)
                    }
                }
            }
            .padding(.top, 8)
            .disabled(appState.currentAIModel == nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    /// View for auto mode
    private var autoModeView: some View {
        suggestionsResponseView
    }

    /// View for command mode
    private var commandModeView: some View {
        VStack(alignment: .leading) {
            if !suggestedCommands.isEmpty {
                responseHeader("Suggested Commands")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(suggestedCommands, id: \.command) { suggestion in
                            commandSuggestionView(suggestion)
                        }
                    }
                }
            } else if !assistantResponse.isEmpty {
                responseHeader("Suggested Command")
                ScrollView {
                    // Display the single suggested command
                    HStack {
                        Text(assistantResponse)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        // Command actions
                        commandActionButtons(assistantResponse)
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(8)
                }
            } else if isProcessing {
                ProgressView("Generating command suggestion...")
            } else {
                Text("Enter a task to get a command suggestion.")
                    .foregroundColor(.secondary)
            }
        }
    }

    /// View for dispatch mode
    private var dispatchModeView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !suggestedCommands.isEmpty {
                responseHeader("Task Execution Plan")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(suggestedCommands, id: \.command) { suggestion in
                            VStack(alignment: .leading, spacing: 4) {
                                commandSuggestionView(suggestion)
                                
                                if !suggestion.explanation.isEmpty {
                                    Text(suggestion.explanation)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 4)
                                }
                            }
                        }
                    }
                }
                
                // Button to execute the plan sequentially
                if suggestedCommands.count > 1 {
                    Button("Execute Entire Plan") {
                        executeCommandPlan(suggestedCommands.map(\.command))
                    }
                    .padding(.top, 8)
                    .disabled(isProcessing)
                }
            } else if !assistantResponse.isEmpty {
                responseHeader("Task Analysis")
                ScrollView {
                    Text(assistantResponse)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(8)
                }
            } else if isProcessing {
                ProgressView("Analyzing task...")
            } else {
                Text("Describe a task for AI execution.")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    /// View for code mode
    private var codeModeView: some View {
        VStack(alignment: .leading) {
            if !assistantResponse.isEmpty {
                responseHeader("Generated Code")
                ScrollView {
                    // Display code with syntax highlighting (basic monospaced for now)
                    Text(assistantResponse)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(NSColor.textBackgroundColor).opacity(0.8))
                        .cornerRadius(8)
                }
                
                // Actions for code
                HStack {
                    Button {
                        copyToClipboard(assistantResponse)
                    } label: {
                        Label("Copy Code", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // Execute code button (might only be for script code)
                    if canExecuteAsScript(assistantResponse) {
                        Button {
                            confirmCommand("# Execute generated code\n" + assistantResponse)
                        } label: {
                            Label("Run as Script", systemImage: "play.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
            } else if isProcessing {
                ProgressView("Generating code...")
            } else {
                Text("Ask for code generation or explanation.")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    /// View that displays suggestions with explanation
    private var suggestionsResponseView: some View {
        VStack(alignment: .leading) {
            if !suggestedCommands.isEmpty {
                responseHeader("AI Suggestions")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(suggestedCommands, id: \.command) { suggestion in
                            VStack(alignment: .leading, spacing: 4) {
                                commandSuggestionView(suggestion)
                                
                                if !suggestion.explanation.isEmpty {
                                    Text(suggestion.explanation)
                                        .font(.callout)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 4)
                                }
                            }
                        }
                    }
                }
            } else if !assistantResponse.isEmpty {
                responseHeader("AI Response")
                ScrollView {
                    Text(assistantResponse)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                }
            } else if isProcessing {
                ProgressView("Thinking...")
            } else {
                Text("Ask the AI assistant anything...")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    /// Command suggestion view with actions
    private func commandSuggestionView(_ suggestion: CommandSuggestion) -> some View {
        HStack {
            // Safety indicator
            safetyIndicator(for: suggestion.safetyLevel)
                .padding(.trailing, 4)
            
            // Command text
            Text(suggestion.command)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            
            Spacer()
            
            // Action buttons
            commandActionButtons(suggestion.command, requiresConfirmation: suggestion.requiresConfirmation)
        }
        .padding(10)
        .background(Color.black.opacity(0.1))
        .cornerRadius(8)
    }
    
    /// Safety indicator icon based on safety level
    private func safetyIndicator(for safetyLevel: CommandSafetyLevel) -> some View {
        switch safetyLevel {
        case .safe:
            return Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .moderate:
            return Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
        case .destructive:
            return Image(systemName: "exclamationmark.octagon.fill")
                .foregroundColor(.red)
        }
    }
    
    /// Command action buttons (execute and copy)
    private func commandActionButtons(_ command: String, requiresConfirmation: Bool = true) -> some View {
        HStack(spacing: 12) {
            // Execute button
            Button {
                if requiresConfirmation || isDestructiveCommand(command) {
                    confirmCommand(command)
                } else {
                    executeCommand(command)
                }
            } label: {
                Image(systemName: "terminal")
            }
            .buttonStyle(.plain)
            .help("Execute Command")
            
            // Copy button
            Button {
                copyToClipboard(command)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .help("Copy Command")
        }
    }
    
    /// Command history view
    private var commandHistoryView: some View {
        VStack(spacing: 0) {
            // Search and header
            HStack {
                Text("Command History")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    withAnimation {
                        showCommandHistory = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search commands", text: $historySearchQuery, onCommit: {
                    Task {
                        await searchCommandHistory()
                    }
                })
                .textFieldStyle(.plain)
                
                if !historySearchQuery.isEmpty {
                    Button {
                        historySearchQuery = ""
                        Task {
                            await loadRecentCommands()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .padding(.bottom, 8)
            
            // Command list
            if recentCommands.isEmpty {
                Text("No command history found")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                List {
                    ForEach(recentCommands) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                // Success/failure indicator
                                if let exitCode = entry.exitCode {
                                    Image(systemName: exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(exitCode == 0 ? .green : .red)
                                }
                                
                                // Command text
                                Text(entry.command)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                // Command actions
                                HStack(spacing: 12) {
                                    Button {
                                        executeCommand(entry.command)
                                    } label: {
                                        Image(systemName: "terminal")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Button {
                                        copyToClipboard(entry.command)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            
                            // Timestamp
                            Text(dateFormatter.string(from: entry.timestamp))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
                .frame(maxHeight: 300)
            }
        }
        .padding()
        .background(
            Color(NSColor.windowBackgroundColor)
                .shadow(radius: 10)
        )
        .cornerRadius(8)
        .padding()
    }
    
    /// Reusable header for response sections
    private func responseHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundColor(modeColor)
            Spacer()
        }
        .padding(.bottom, 4)
    }
    
    /// Input area for user to type queries
    private var inputArea: some View {
        HStack {
            if appState.aiMode != .disabled {
                TextField("Ask the assistant...", text: $inputText, onCommit: {
                    sendMessage()
                })
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .disabled(isProcessing)

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(!inputText.isEmpty && !isProcessing ? modeColor : .gray)
                }
                .disabled(inputText.isEmpty || isProcessing)
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Send Message (⌘+Return)")

            } else {
                Text("AI Assistant is disabled")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    /// Color associated with the current AI mode
    private var modeColor: Color {
        switch appState.aiMode {
        case .auto:
            return .blue
        case .command:
            return .green
        case .dispatch:
            return .orange
        case .code:
            return .purple
        case .disabled:
            return .gray
        }
    }
    
    /// Date formatter for timestamps
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
    
    /// Send a message to the AI
    private func sendMessage() {
        guard !inputText.isEmpty, !isProcessing else { return }
        
        // Save the query for potential clearing
        let query = inputText
        
        // Clear input immediately for better UX
        inputText = ""
        
        // Show processing state
        isProcessing = true
        
        // Reset results
        assistantResponse = ""
        suggestedCommands = []
        
        // Process with AI coordinator
        Task {
            do {
                // Get AI coordinator from app state if not provided in init
                let coordinator = aiCoordinator ?? await appState.aiCoordinator
                
                // Process input based on the current mode
                let response = try await coordinator.processInput(query)
                
                // Update UI with response
                await MainActor.run {
                    if let context = response.context {
                        assistantResponse = context
                    }
                    
                    suggestedCommands = response.suggestions
                    isProcessing = false
                    
                    // Add to command history if this is related to command generation
                    if appState.aiMode == .command || appState.aiMode == .dispatch {
                        Task {
                            await addToCommandHistory(query, isAIAssisted: true)
                        }
                    }
                    
                    // If in dispatch mode and there are actions, potentially execute them
                    if appState.aiMode == .dispatch, let firstAction = response.actions.first {
                        Task {
                            let shouldExecute = await coordinator.executeAction(firstAction)
                            if shouldExecute {
                                await executeAIAction(firstAction)
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    assistantResponse = "Error: \(error.localizedDescription)"
                    isProcessing = false
                }
            }
        }
    }
    
    /// Execute an AI action
    private func executeAIAction(_ action: AIAction) async {
        switch action.type {
        case .executeCommand:
            executeCommand(action.content)
            
        case .generateCode:
            // Just display the code
            await MainActor.run {
                assistantResponse = action.content
            }
            
        case .modifyFile:
            guard let filePath = action.metadata["path"] else { return }
            
            // Create a command to modify the file
            let command = "cat > \(filePath) << 'LLAMA_EOF'\n\(action.content)\nLLAMA_EOF"
            executeCommand(command)
            
        case .installPackage:
            executeCommand(action.content)
            
        case .planTask:
            // Just display the plan
            await MainActor.run {
                assistantResponse = action.content
            }
        }
    }
    
    /// Confirm a command before execution
    private func confirmCommand(_ command: String) {
        commandToExecute = command
        commandIsDestructive = isDestructiveCommand(command)
        showConfirmationDialog = true
    }
    
    /// Check if a command is potentially destructive
    private func isDestructiveCommand(_ command: String) -> Bool {
        let destructivePatterns = [
            "rm", "rmdir", "mv", "sudo", "dd", "mkfs", 
            "format", "reboot", "shutdown", "halt",
            "> /", "| sudo", "chmod", "chown", "kill",
            "pkill", ":(){ :|:& };:", "> /dev/sd",
            "find .* -delete"
        ]
        
        let lowerCommand = command.lowercased()
        return destructivePatterns.contains { lowerCommand.contains($0) }
    }
    
    /// Execute a command in the terminal
    private func executeCommand(_ command: String) {
        guard !command.isEmpty else { return }
        
        // Add to command history
        Task {
            await addToCommandHistory(command)
        }
        
        // Execute using app state
        appState.executeCommandInTerminal(command)
    }
    
    /// Execute a series of commands sequentially
    private func executeCommandPlan(_ commands: [String]) {
        guard !commands.isEmpty else
