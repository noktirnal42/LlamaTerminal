import SwiftUI
import TerminalCore
import AIIntegration
import UIComponents
import SharedModels

@main
struct LlamaTerminalApp: App {
    // Global app state
    @StateObject private var appState = AppState()
    
    // State for Ollama detection and welcome screen
    @State private var hasCheckedOllama = false
    @State private var showWelcomeScreen = false
    @State private var isOllamaInstalled = false
    
    // State for app lifecycle
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    // Check if this is the first run
                    if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") || 
                       !UserDefaults.standard.bool(forKey: "hideWelcomeScreen") {
                        showWelcomeScreen = true
                        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                    }
                    
                    // Check if Ollama is installed
                    checkOllamaInstallation()
                }
                .sheet(isPresented: $showWelcomeScreen) {
                    WelcomeView(isOllamaInstalled: isOllamaInstalled)
                        .frame(width: 600, height: 500)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhaseChange(newPhase)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // Terminal commands
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    appState.addNewTab()
                }
                .keyboardShortcut("t", modifiers: .command)
                
                Divider()
                
                Button("Split Horizontally") {
                    // To be implemented in future versions
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(true) // Disabled until implemented
                
                Button("Split Vertically") {
                    // To be implemented in future versions
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(true) // Disabled until implemented
                
                Divider()
                
                Button("Close Tab") {
                    if appState.terminalTabs.indices.contains(appState.selectedTabIndex) {
                        appState.closeTab(at: appState.selectedTabIndex)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
            }
            
            // AI Assistant commands
            CommandMenu("AI Assistant") {
                ForEach(AIMode.allCases) { mode in
                    if mode != .disabled {
                        Button(mode.displayName) {
                            appState.setAIMode(mode)
                        }
                        .keyboardShortcut(KeyEquivalent(Character(String(mode.systemImage.prefix(1)))), modifiers: [.command, .shift])
                    }
                }
                
                Divider()
                
                Button("Disable AI Assistant") {
                    appState.setAIMode(.disabled)
                }
                .keyboardShortcut("0", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Select AI Model...") {
                    appState.showModelSelectionSheet = true
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Show Command History") {
                    appState.showCommandHistorySheet = true
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            }
            
            // View commands
            CommandMenu("View") {
                Button("Toggle Terminal Theme") {
                    appState.toggleDarkMode()
                }
                
                Divider()
                
                Button("Increase Font Size") {
                    appState.increaseFontSize()
                }
                .keyboardShortcut("+", modifiers: .command)
                
                Button("Decrease Font Size") {
                    appState.decreaseFontSize()
                }
                .keyboardShortcut("-", modifiers: .command)
                
                Button("Reset Font Size") {
                    appState.resetFontSize()
                }
                .keyboardShortcut("0", modifiers: .command)
                
                Divider()
                
                Button("Toggle AI Panel") {
                    withAnimation {
                        appState.showAIPanel.toggle()
                    }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
            
            // Help commands
            CommandGroup(replacing: .help) {
                Button("LlamaTerminal Help") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/yourusername/llama_terminal/wiki")!)
                }
                
                Button("Show Welcome Screen") {
                    showWelcomeScreen = true
                }
            }
        }
    }
    
    /// Checks if Ollama is installed and available
    private func checkOllamaInstallation() {
        guard !hasCheckedOllama else { return }
        
        hasCheckedOllama = true
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["ollama"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let status = task.terminationStatus
            isOllamaInstalled = (status == 0)
            
            if isOllamaInstalled {
                // If Ollama is installed, load models
                Task {
                    try? await appState.refreshAvailableModels()
                }
            }
        } catch {
            print("Error checking Ollama installation: \(error)")
            isOllamaInstalled = false
        }
    }
    
    /// Handles scene phase changes
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            // Refresh models on becoming active if Ollama is installed
            if isOllamaInstalled {
                Task {
                    try? await appState.refreshAvailableModels()
                }
            }
            
        case .inactive, .background:
            // Save any state if needed
            appState.savePreferences()
            
        @unknown default:
            break
        }
    }
}
