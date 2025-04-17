import SharedModels
import SwiftUI
import UIComponents

public struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var windowSize: CGSize = .zero

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Main content area with tabs
            Group {
                if appState.terminalTabs.isEmpty {
                    // Empty state message
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
                } else {
                    // Tab view with terminals
                    TabView(selection: $appState.selectedTabIndex) {
                        ForEach(appState.terminalTabs.indices, id: \.self) { index in
                            TerminalTabView(terminalSession: appState.terminalTabs[index].session)
                                .tabItem {
                                    Label(
                                        appState.terminalTabs[index].title, systemImage: "terminal")
                                }
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.automatic)
                }
            }

            // Separator before AI panel (optional)
            if appState.showAIPanel {
                Divider()
            }

            // AI assistant panel overlay
            if appState.showAIPanel {
                AIAssistantPanel()
                    .frame(height: min(max(windowSize.height * 0.3, 200), 400))
                    .transition(.move(edge: .bottom))
            }
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
            // Assuming CommandHistoryView has been updated with a public initializer
            CommandHistoryView()
                .frame(width: 600, height: 500)
                .environmentObject(appState)
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
                // AI assistant toggle
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

    // MARK: - Computed Properties

    /// Color for the current AI mode
    private var modeColor: Color {
        switch appState.currentAIMode {
        case .disabled:
            return .secondary
        case .auto:
            return .blue
        case .dispatch:
            return .orange
        case .code:
            return .green
        case .command:
            return .purple
        }
    }

    /// Terminal background based on theme
    private var terminalBackground: Color {
        appState.isDarkMode ? Color.black : Color(NSColor.textBackgroundColor)
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
