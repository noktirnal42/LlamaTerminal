# LlamaTerminal

[![Swift Version](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2015.0%2B-lightgrey.svg)](https://developer.apple.com/macOS)

LlamaTerminal is an experimental macOS terminal application enhanced with local AI capabilities, primarily using Ollama.

## Overview

This application provides a standard terminal interface (powered by SwiftTerm) combined with integrated AI assistance. Users can interact with their shell as usual, but also leverage local large language models (LLMs) running via Ollama for tasks like command generation, code explanation, file modification, and more.

## Features

*   **Standard Terminal Emulation:** Based on the robust `SwiftTerm` library.
*   **Ollama Integration:** Connects to a local Ollama instance to run LLMs.
*   **Model Management:** View, pull, and delete Ollama models from within the app.
*   **AI Modes:**
    *   **Auto Mode:** AI observes terminal interaction and provides suggestions.
    *   **Dispatch Mode:** AI can directly execute commands or actions based on user input (with safety checks).
    *   **(Future Modes):** Command Mode, Code Mode, etc.
*   **AI Assistant Panel:** Dedicated UI for interacting with the AI, viewing suggestions, and managing models.
*   **Command Bar:** Separate input field for composing commands with potential AI assistance (depending on mode).
*   **(Planned/Potential):** Syntax highlighting, customizable themes, session tabs.

## Build & Run

### Prerequisites

1.  **macOS:** macOS 15.0 (Sonoma) or later.
2.  **Xcode:** Xcode 16 or later (required for Swift 6.0).
3.  **Ollama:** You need a running Ollama instance. Download and install it from [ollama.com](https://ollama.com/). Ensure Ollama is running before launching LlamaTerminal.
4.  **Ollama Models:** Pull at least one model using the Ollama CLI (e.g., `ollama pull llama3`).

### Building from Source

1.  **Clone the Repository:**
    ```bash
    git clone https://github.com/noktirnal42/LlamaTerminal.git
    cd LlamaTerminal
    ```

2.  **Open in Xcode:**
    *   You can directly open the `LlamaTerminal` directory in Xcode 16.
    *   Alternatively, generate project files (though opening the directory directly is preferred):
        ```bash
        swift package generate-xcodeproj
        open LlamaTerminal.xcodeproj
        ```

3.  **Build and Run:**
    *   Select the `LlamaTerminal` scheme and your Mac as the target device in Xcode.
    *   Press the Run button (▶︎) or `Cmd + R`.

    *   Alternatively, use the Swift Package Manager from the terminal:
        ```bash
        swift run LlamaTerminal
        ```

## Basic Usage

1.  **Launch the App:** Ensure Ollama is running, then launch LlamaTerminal.
2.  **Terminal Interaction:** Use the main terminal pane just like any other terminal.
3.  **AI Mode Selection:** Use the AI Mode selector (often in the status bar or AI Panel) to switch between modes (e.g., Auto, Dispatch, Disabled).
4.  **Command Bar:** When AI is enabled, you can type commands into the bottom command bar for potential AI processing before execution.
5.  **AI Panel:** Interact with the AI panel to manage models, view suggestions, or potentially have direct chats (depending on implementation).

## Architecture

For details on the project's structure and module responsibilities, see [ARCHITECTURE.md](ARCHITECTURE.md).

## API Documentation (DocC)

This project uses Swift-DocC for generating API documentation.

1.  **Build Documentation:** In Xcode, select **Product > Build Documentation** (`Cmd + Shift + Ctrl + D`).
2.  **View Documentation:** The documentation archive will open in Xcode's documentation viewer.

You can also generate documentation from the command line (ensure you have the necessary Xcode command-line tools selected):

```bash
swift package --allow-writing-to-directory ./docs generate-documentation --target TerminalCore --target AIIntegration --target SharedModels --target UIComponents --output-path ./docs
```

*(Note: Hosting this documentation online would typically involve a separate process or CI job.)*

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
