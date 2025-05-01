import SwiftUI
import Foundation
import TerminalCore

// NOTE: This file was moved from Sources/App/AppState+Extensions.swift

extension AppState {
    /// Whether Ollama appears to be detected (based on having models listed).
    /// This is a proxy and doesn't guarantee Ollama is *currently* running.
    public var isOllamaDetected: Bool { // Made public
        return !availableModels.isEmpty
    }
    
    /// Returns the current terminal session based on the selected tab
    public var currentTerminalSession: TerminalSession? {
        guard !terminalTabs.isEmpty, selectedTabIndex < terminalTabs.count else {
            return nil
        }
        return terminalTabs[selectedTabIndex].session
    }
    
    // MARK: - Session Persistence
    
    /// Load session state from persistent storage
    public func loadSessionState() {
        guard let sessionsData = UserDefaults.standard.data(forKey: "savedSessions") else {
            print("No saved sessions found")
            return
        }
        
        do {
            let sessionsDict = try JSONSerialization.jsonObject(with: sessionsData) as? [String: [String: Any]]
            
            guard let sessionsDict = sessionsDict else {
                print("Invalid sessions data format")
                return
            }
            
            // Temporary array to collect sessions we'll restore
            var restoredTabs: [TerminalTab] = []
            
            for (sessionId, sessionData) in sessionsDict {
                do {
                    // Create a new session with the saved state
                    let newSession = TerminalSession()
                    
                    // Get session title or use default
                    let title = (sessionData["title"] as? String) ?? "Restored Terminal"
                    
                    // Create a new tab
                    let tab = TerminalTab(id: UUID(uuidString: sessionId) ?? UUID(), 
                                         title: title, 
                                         session: newSession)
                    
                    // Restore the session directory and other session-specific state
                    if let workingDir = sessionData["workingDirectory"] as? String, !workingDir.isEmpty {
                        // Set working directory in the next terminal startup
                        // This will be applied when the view starts the session
                        // The actual directory change happens when the terminal session starts
                        UserDefaults.standard.set(workingDir, forKey: "lastWorkingDirectory-\(sessionId)")
                    }
                    
                    restoredTabs.append(tab)
                    
                    print("Restored session with ID: \(sessionId)")
                } catch {
                    print("Failed to restore session \(sessionId): \(error.localizedDescription)")
                }
            }
            
            // Only update if we restored some tabs
            if !restoredTabs.isEmpty {
                // Replace the current tabs with the restored ones
                terminalTabs = restoredTabs
                selectedTabIndex = 0
                print("Successfully restored \(restoredTabs.count) terminal sessions")
            }
            
        } catch {
            print("Error deserializing sessions: \(error.localizedDescription)")
        }
    }
    
    /// Save current session state to persistent storage
    public func saveSessionState() {
        var sessionsDict: [String: [String: Any]] = [:]
        
        for tab in terminalTabs {
            // Skip sessions that aren't running
            if !tab.session.isRunning {
                continue
            }
            
            var sessionData: [String: Any] = [:]
            
            // Save basic info
            sessionData["title"] = tab.title
            
            // Save working directory if available
            if let workingDir = tab.session.currentWorkingDirectory {
                sessionData["workingDirectory"] = workingDir
            }
            
            // Add custom session data
            if let dimensions = getSessionDimensions(tab.session) {
                sessionData["dimensions"] = dimensions
            }
            
            // Add this session to our dictionary
            sessionsDict[tab.id.uuidString] = sessionData
        }
        
        // Save to UserDefaults
        do {
            let sessionsData = try JSONSerialization.data(withJSONObject: sessionsDict)
            UserDefaults.standard.set(sessionsData, forKey: "savedSessions")
            print("Saved \(sessionsDict.count) terminal sessions")
        } catch {
            print("Error serializing sessions: \(error.localizedDescription)")
        }
    }
    
    /// Save all terminal sessions
    public func saveAllSessions() {
        saveSessionState()
        savePreferences()
    }
    
    /// Helper to get terminal dimensions
    private func getSessionDimensions(_ session: TerminalSession) -> [String: Int]? {
        return [
            "cols": session.currentCols,
            "rows": session.currentRows
        ]
    }
    
    // MARK: - Task Management
    
    /// Show task detail for the given task ID
    public func showTaskDetail(taskId: UUID) {
        // Find the task in the current terminal session
        guard let session = currentTerminalSession else {
            print("No active terminal session")
            return
        }
        
        // Set the task detail view mode
        // In a real implementation, this would update UI state to show a detail view
        // for the specified task
        print("Showing task detail for: \(taskId.uuidString)")
        
        // Fetch task data and update UI accordingly
        Task {
            if let task = await session.taskPersistenceManager.getTaskState(taskId) {
                await MainActor.run {
                    // In a real implementation, this would update a @Published property
                    // that drives the task detail view
                    print("Task status: \(task.status.rawValue), Type: \(task.type.rawValue)")
                }
            } else {
                print("Task not found: \(taskId.uuidString)")
            }
        }
    }
    
    /// Check if Ollama is installed and running
    public func checkOllamaStatus() async -> Bool {
        do {
            // First check if we have any models, which is a quick way to determine
            // if Ollama is likely installed and has been used
            try await refreshAvailableModels()
            if !availableModels.isEmpty {
                return true
            }
            
            // If no models are available, we can do a deeper check
            // by attempting to call the Ollama API directly
            return await ollamaService.isOllamaRunning()
        } catch {
            print("Ollama check failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Restore application state on launch
    public func restoreApplicationState() {
        // Load saved preferences
        loadUserPreferences()
        
        // Check if we should restore sessions or start fresh
        let shouldRestoreSessions = UserDefaults.standard.bool(forKey: "restoreSessionsOnLaunch")
        
        if shouldRestoreSessions {
            // Load previously saved sessions
            loadSessionState()
        }
        
        // If no sessions were loaded or restoration is disabled, create a new tab
        if terminalTabs.isEmpty {
            addNewTab()
        }
        
        // Check Ollama status
        Task {
            let isOllamaRunning = await checkOllamaStatus()
            if isOllamaRunning {
                print("Ollama detected and running")
            } else {
                print("Ollama not detected or not running")
            }
        }
    }
}
