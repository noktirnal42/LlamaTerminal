import SwiftUI

// NOTE: This file was moved from Sources/App/AppState+Extensions.swift

extension AppState {
    /// Whether Ollama appears to be detected (based on having models listed).
    /// This is a proxy and doesn't guarantee Ollama is *currently* running.
    public var isOllamaDetected: Bool { // Made public
        return !availableModels.isEmpty
    }
}

