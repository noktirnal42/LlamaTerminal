# LlamaTerminal Architecture

This document provides a high-level overview of the modules within the LlamaTerminal project.

## Modules

*   **App:**
    *   The main executable target.
    *   Sets up the SwiftUI application lifecycle (`LlamaTerminalApp`).
    *   Contains the root view (`ContentView`) that orchestrates the UI.
    *   Initializes and manages the shared `AppState`.
    *   Depends on all other local library targets.

*   **TerminalCore:**
    *   Responsible for managing the underlying terminal session.
    *   Integrates with the `SwiftTerm` library for terminal emulation and PTY handling (`TerminalSession`).
    *   Handles process launching (`/bin/zsh`), data input/output, and terminal resizing.
    *   Provides services for command execution (`CommandExecutionService`) and syntax highlighting.

*   **AIIntegration:**
    *   Handles all communication with the AI backend (currently Ollama).
    *   Defines AI modes (`AIMode`) and handlers (`AIModeHandler`).
    *   Contains services for interacting with the Ollama API (`OllamaModelService`, `ChatCompletionService`, etc.).
    *   Responsible for processing user input through the AI (`AITerminalCoordinator`), generating suggestions, and handling model management.
    *   Uses `Alamofire` for network requests and `swift-markdown` for parsing.

*   **SharedModels:**
    *   Contains data models and state used across multiple modules.
    *   Includes `AppState` (the central source of truth for UI state), `CommandHistoryItem`, and potentially other shared structures.
    *   Depends on `TerminalCore` and `AIIntegration` for some model definitions.

*   **UIComponents:**
    *   Provides reusable SwiftUI views for the application.
    *   Includes the main `TerminalTabView`, `AIAssistantPanel`, `AIModeBadge`, `ModelSelectionView`, etc.
    *   Depends on `TerminalCore`, `AIIntegration`, and `SharedModels` to display data and interact with the backend.

## Dependencies

*   **SwiftTerm:** Used by `TerminalCore` and `UIComponents` for terminal view rendering and PTY management.
*   **Alamofire:** Used by `AIIntegration` for making HTTP requests to the Ollama API.
*   **swift-markdown:** Used by `AIIntegration` for parsing markdown potentially returned by the AI. 