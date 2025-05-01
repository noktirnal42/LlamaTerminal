import SwiftUI
import UIComponents
import SharedModels
import TerminalCore
import AIIntegration

/// Main content view for the app
public struct ContentView: View {
    /// App state
    @EnvironmentObject private var appState: AppState
    
    /// Whether the task recovery dialog is visible
    @State private var showRecoveryDialog = false
    
    /// Tasks to recover
    @State private var recoveryTasks: [TaskState] = []
    
    /// Whether the error notification is visible
    @State private var showErrorNotification = false
    
    /// Error message
    @State private var errorMessage = ""
    
    /// Error details
    @State private var errorDetails: String? = nil
    
    /// Window size
    @State private var windowSize: CGSize = .zero
    
    /// Is initializing terminal sessions
    @State private var isInitializing = true
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            HSplitView {
                // Main terminal area
                VStack(spacing: 0) {
                    if isInitializing {
                        loadingView
                    } else if appState.terminalTabs.isEmpty {
                        welcomeView
                    } else {
                        TabView(selection: $appState.selectedTabIndex) {
                            ForEach(appState.terminalTabs.indices, id: \.self) { index in
                                terminalTab(for: index)
                                    .tabItem {
                                        Label(
                                            appState.terminalTabs[index].title,
                                            systemImage: "terminal"
                                        )
                                    }
                                    .tag(index)
                            }
                        }
                        .tabViewStyle(.automatic)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(terminalBackground)
                
                // AI Assistant panel (if enabled)
                if appState.showAIPanel {
                    AIAssistantPanel()
                        .frame(width: min(windowSize.width * 0.3, 350), maxWidth: 500)
                        .transition(.move(edge: .trailing))
                }
            }
            .toolbar {
                // Left side toolbar items
                ToolbarItemGroup(placement: .automatic) {
                    // Model status indicator
                    if let model = appState.selectedModel {
                        HStack(spacing: 4) {
                            Image(systemName: "cube.box.fill")
                                .foregroundColor(.blue)
                            
                            Text(model.name)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                        .onTapGesture {
                            appState.showModelSelectionSheet = true
                        }
                    } else if appState.availableModels.isEmpty && !appState.isOllamaDetected {
                        Button {
                            NSWorkspace.shared.open(URL(string: "https://ollama.ai")!)
                        } label: {
                            Label("Install Ollama", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Right side toolbar items
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: {
                        withAnimation {
                            appState.showAIPanel.toggle()
                        }
                    }) {
                    Label(
                        "AI Assistant",
                        systemImage: appState.showAIPanel ? "wand.and.stars.fill" : "wand.and.stars"
                    )
                    .foregroundColor(appState.showAIPanel ? .blue : .primary)
                }
                .help("Toggle AI Assistant Panel")

                // AI mode selection
                Menu {
                    ForEach(AIMode.allCases) { mode in
                        Button(action: {
                            appState.setAIMode(mode)
                        }) {
                            Label(mode.displayName, systemImage: mode.systemImage)
                        }
                    }
                } label: {
                    Label(
                        appState.currentAIMode.displayName,
                        systemImage: appState.currentAIMode.systemImage
                    )
                    .foregroundColor(modeColor)
                }
                .help("Select AI Assistant Mode")

                // Terminal customization
                Menu {
                    Button(action: {
                        appState.toggleDarkMode()
                    }) {
                        Label(
                            appState.isDarkMode ? "Switch to Light Mode" : "Switch to Dark Mode",
                            systemImage: appState.isDarkMode ? "sun.max" : "moon")
                    }

                    Divider()

                    Button(action: {
                        appState.increaseFontSize()
                    }) {
                        Label("Increase Font Size", systemImage: "plus.circle")
                    }

                    Button(action: {
                        appState.decreaseFontSize()
                    }) {
                        Label("Decrease Font Size", systemImage: "minus.circle")
                    }

                    Button(action: {
                        appState.resetFontSize()
                    }) {
                        Label("Reset Font Size", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Label("Customize", systemImage: "slider.horizontal.3")
                }
                .help("Customize Terminal")

                // Add new tab button
                Button(action: {
                    appState.addNewTab()
                }) {
                    Label("New Tab", systemImage: "plus")
                }
                .help("Open New Terminal Tab")
            }
        }
        .navigationTitle(
            appState.terminalTabs.isEmpty
                ? "LlamaTerminal"
                : appState.terminalTabs[safe: appState.selectedTabIndex]?.title ?? "Terminal"
        )
        .preferredColorScheme(appState.isDarkMode ? .dark : .light)
    }
    .background(
        GeometryReader { geometry in
            Color.clear
                .preference(key: WindowSizePreferenceKey.self, value: geometry.size)
                .onPreferenceChange(WindowSizePreferenceKey.self) { size in
                    windowSize = size
                }
        }
    )
    .sheet(isPresented: $appState.showModelSelectionSheet) {
        ModelSelectionView()
            .frame(width: 600, height: 500)
            .environmentObject(appState)
    }
    .sheet(isPresented: $appState.showCommandHistorySheet) {
        CommandHistoryView()
            .frame(width: 600, height: 500)
            .environmentObject(appState)
    }
    .sheet(isPresented: $showRecoveryDialog) {
        TaskRecoveryDialog(
            isPresented: $showRecoveryDialog,
            tasks: recoveryTasks,
            onRecover: { tasks in
                Task {
                    if let session = appState.currentTerminalSession {
                        await session.recoverTasks(tasks)
                        await MainActor.run {
                            recoveryTasks = []
                        }
                    }
                }
            },
            onSkip: {
                Task {
                    if let session = appState.currentTerminalSession {
                        await session.clearRecoveryTasks()
                        await MainActor.run {
                            recoveryTasks = []
                        }
                    }
                }
            }
        )
    }
    .overlay(
        Group {
            if !recoveryTasks.isEmpty && !showRecoveryDialog {
                RecoveryPromptView(
                    tasks: recoveryTasks,
                    onAccept: {
                        showRecoveryDialog = true
                    },
                    onDecline: {
                        Task {
                            if let session = appState.currentTerminalSession {
                                await session.clearRecoveryTasks()
                                await MainActor.run {
                                    recoveryTasks = []
                                }
                            }
                        }
                    }
                )
                .transition(.opacity)
                .animation(.easeInOut, value: !recoveryTasks.isEmpty)
                .zIndex(100)
            }
        }
    )
    .errorNotification(
        isVisible: $showErrorNotification,
        message: errorMessage,
        details: errorDetails
    )
    .onAppear {
        initializeTerminalSessions()
    }
    .onChange(of: appState.currentTerminalSession?.recoveryTasks) { newValue in
        if let tasks = newValue, !tasks.isEmpty {
            recoveryTasks = tasks
            // Only show dialog automatically for critical tasks
            let hasCriticalTasks = tasks.contains { $0.recoveryPriority == .critical }
            if hasCriticalTasks {
                showRecoveryDialog = true
            }
        }
    }
    .onChange(of: appState.currentTerminalSession?.error) { newError in
        if let error = newError {
            errorMessage = error.localizedDescription
            errorDetails = error.recoveryOptions?.first
            showErrorNotification = true
            
            // Clear error after showing notification
            appState.currentTerminalSession?.clearError()
        }
    }
    .onReceive(NotificationCenter.default.publisher(for: .terminalSessionError)) { notification in
        if let error = notification.object as? TerminalError,
           let sessionId = notification.userInfo?["sessionId"] as? UUID {
            // Handle errors from any terminal session, not just the current one
            errorMessage = error.localizedDescription
            errorDetails = "\(error.recoveryOptions?.first ?? "") (Session ID: \(sessionId.uuidString.prefix(8)))"
            showErrorNotification = true
        }
    }
}

// MARK: - View Components
extension ContentView {
    /// Welcome view when no terminals are open
    private var welcomeView: some View {
        VStack(spacing: 20) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 52))
                .foregroundColor(.secondary)
            
            Text("No Active Terminals")
                .font(.title2)
            
            Text("Press ⌘T to open a new terminal tab.")
                .font(.callout)
                .foregroundColor(.secondary)
            
            Button("New Terminal") {
                appState.addNewTab()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("t", modifiers: .command)
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
    
    /// Loading view during initialization
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .padding()
            
            Text("Initializing Terminal...")
                .font(.headline)
            
            Text("Loading session state and preparing environment")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
    
    /// Terminal tab view for a specific index
    private func terminalTab(for index: Int) -> some View {
        ZStack(alignment: .bottomTrailing) {
            // Terminal view
            if let session = appState.terminalTabs[index].session,
               let terminalView = session.terminalView {
                SwiftUITerminalView(terminalView: terminalView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Placeholder when terminal view is not yet initialized
                Rectangle()
                    .fill(Color.black)
                    .overlay(
                        ProgressView("Initializing terminal...")
                            .foregroundColor(.white)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Task progress view (only show when there are active tasks)
            if let session = appState.terminalTabs[index].session,
               !session.activeTasks.isEmpty {
                TaskProgressView(
                    tasks: session.activeTasks.values.map { $0 },
                    onTaskCancel: { taskId in
                        Task {
                            await session.cancelTask(withId: taskId)
                        }
                    },
                    onTaskViewDetails: { task in
                        if let commandTask = task as? CommandTaskState {
                            appState.showTaskDetails(commandTask)
                        }
                    }
                )
                .frame(maxWidth: 300)
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Terminal Session Management
extension ContentView {
    /// Initialize terminal sessions and restore state
    private func initializeTerminalSessions() {
        Task {
            // Check for persisted sessions
            let persistedSessions = await SessionStorage.shared.loadSavedSessions()
            
            await MainActor.run {
                if persistedSessions.isEmpty {
                    // Create a default session if none exist
                    appState.addNewTab()
                } else {
                    // Restore persisted sessions
                    for sessionData in persistedSessions {
                        appState.restoreSession(from: sessionData)
                    }
                }
                
                // Mark initialization as complete
                isInitializing = false
            }
            
            // Set up observers for session events
            setupSessionObservers()
            
            // Check for recovery tasks after initialization
            await checkForRecoveryTasks()
        }
    }
    
    /// Set up observers for terminal session events
    private func setupSessionObservers() {
        // Set up periodic state saving
        Task {
            while !Task.isCancelled {
                await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                await appState.saveAllSessionStates()
            }
        }
        
        // Set up command history tracking
        Task {
            for await notification in NotificationCenter.default.notifications(named: .terminalCommandExecuted) {
                if let command = notification.object as? String,
                   let sessionId = notification.userInfo?["sessionId"] as? UUID {
                    await CommandHistoryManager.shared.addCommand(
                        command,
                        sessionId: sessionId,
                        directory: notification.userInfo?["workingDirectory"] as? String ?? ""
                    )
                }
            }
        }
    }
    
    /// Check for recovery tasks in all sessions
    private func checkForRecoveryTasks() async {
        var allRecoveryTasks: [TaskState] = []
        
        // Gather recovery tasks from all sessions
        for tab in appState.terminalTabs {
            if let session = tab.session {
                let tasks = await session.checkForRecoveryTasks()
                allRecoveryTasks.append(contentsOf: tasks)
            }
        }
        
        // Update UI if we have recovery tasks
        if !allRecoveryTasks.isEmpty {
            await MainActor.run {
                recoveryTasks = allRecoveryTasks
                
                // Only automatically show dialog for critical tasks
                let hasCriticalTasks = allRecoveryTasks.contains { $0.recoveryPriority == .critical }
                if hasCriticalTasks {
                    showRecoveryDialog = true
                }
            }
        }
    }
}

// MARK: - SwiftUI Terminal View
struct SwiftUITerminalView: NSViewRepresentable {
    /// The wrapped SwiftTerm view
    let terminalView: NSViewType
    
    /// Creates the NSView
    func makeNSView(context: Context) -> NSViewType {
        return terminalView
    }
    
    /// Updates the NSView
    func updateNSView(_ nsView: NSViewType, context: Context) {
        // No updates needed as we're using the same view instance
    }
    
    /// Type for NSView
    typealias NSViewType = SwiftTerm.TerminalView
}

// MARK: - Computed Properties

extension ContentView {
    /// Color for the current AI mode
    private var modeColor: Color {
        switch appState.currentAIMode {
        case .disabled:
            return .gray
        case .auto:
            return .blue
        case .command:
            return .green
        case .dispatch:
            return .orange
        case .code:
            return .purple
        }
    }
    
    /// Terminal background based on theme
    private var terminalBackground: some View {
        Color(nsColor: appState.isDarkMode ? NSColor.black : NSColor.textBackgroundColor)
            .ignoresSafeArea()
    }
}

// MARK: - Helper Extensions

/// Safe array access
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

/// Window size preference key
struct WindowSizePreferenceKey: @preconcurrency PreferenceKey {
    @MainActor static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// Preview for ContentView
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppState())
    }
}
// Removed duplicate ContentView definition
