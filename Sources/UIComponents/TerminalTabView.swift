import AIIntegration
import SharedModels
import SwiftTerm
import SwiftUI
import TerminalCore

/// The main terminal tab view that displays a terminal session
public struct TerminalTabView: View {
    // MARK: - Properties

    /// The terminal session to display
    private let terminalSession: TerminalSession

    /// Environment object for accessing app state
    @EnvironmentObject private var appState: AppState

    /// State properties
    @State private var terminalSize: CGSize = CGSize(width: 80, height: 25)
    @State private var showCommandConfirmation = false
    @State private var commandToConfirm = ""
    @State private var isDestructiveCommand = false
    @State private var commandInput: String = ""

    // MARK: - Initialization

    public init(terminalSession: TerminalSession) {
        self.terminalSession = terminalSession
    }

    // MARK: - View Body

    public var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                // Main terminal area
                SwiftTermViewRepresentable(
                    session: terminalSession,
                    terminalSize: $terminalSize,
                    onCommandDetected: handleCommandDetected
                )
                .focusable()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(terminalBackgroundColor)

                // Command input
                if appState.currentAIMode != .disabled {
                    commandInputView
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            // Status bar
            if !terminalSession.isRunning {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("Terminal session ended")
                        .foregroundColor(.secondary)

                    Spacer()

                    // Temporarily disable restart button
                    /*
                    Button("Restart") {
                        Task {
                            await restartTerminalSession()
                        }
                    }
                    */
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color(.windowBackgroundColor))
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: geometry.size)
                    .onPreferenceChange(SizePreferenceKey.self) { newSize in
                        updateTerminalSize(newSize)
                    }
            }
        )
        .toolbar {
            ToolbarItem(placement: .status) {
                statusBar
            }
        }
        .alert("Execute Command", isPresented: $showCommandConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button(
                isDestructiveCommand ? "Execute Anyway" : "Execute",
                role: isDestructiveCommand ? .destructive : .none
            ) {
                executeCommand(commandToConfirm)
            }
        } message: {
            Text(
                isDestructiveCommand
                    ? "This command may modify or delete files. Are you sure?\n\n\(commandToConfirm)"
                    : "Execute this command?\n\n\(commandToConfirm)")
        }
    }

    // No duplicate declarations - these are already defined above

    /// Status bar displaying terminal info and controls
    private var statusBar: some View {
        HStack(spacing: 12) {
            // Current directory
            Label(terminalSession.currentWorkingDirectory ?? "Terminal", systemImage: "folder")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            // AI mode indicator
            if appState.currentAIMode != .disabled {
                AIModeBadge(mode: appState.currentAIMode)
                    .scaleEffect(0.8)
            }

            // Command count
            Text("\(appState.commandHistory.count) commands")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    /// Command input view for entering commands with AI suggestions
    private var commandInputView: some View {
        HStack {
            Image(systemName: "terminal")
                .foregroundColor(.secondary)

            TextField(
                "Enter command...", text: $commandInput,
                onCommit: {
                    submitCommand()
                }
            )
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))

            Button {
                submitCommand()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(!commandInput.isEmpty ? .blue : .gray)
            }
            .disabled(commandInput.isEmpty)
            .buttonStyle(.plain)

            Button {
                // Clear the input
                commandInput = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(commandInput.isEmpty ? 0 : 1)
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .background(.regularMaterial)
        .cornerRadius(8)
    }

    /// Updates the terminal size based on the view size
    /// - Parameter size: The new size
    // MARK: - Private Methods

    private var terminalBackgroundColor: SwiftUI.Color {
        appState.isDarkMode ? SwiftUI.Color.black : SwiftUI.Color(nsColor: .textBackgroundColor)
    }

    private func updateTerminalSize(_ size: CGSize) {
        // Calculate terminal dimensions based on font metrics
        let fontWidth: CGFloat = 7.0  // Approximate width of a monospaced character
        let fontHeight: CGFloat = 14.0  // Approximate height of a line

        let cols = max(Int(size.width / fontWidth), 40)
        let rows = max(Int(size.height / fontHeight), 10)

        let newSize = CGSize(width: cols, height: rows)
        if newSize != terminalSize {
            terminalSize = newSize
        }
    }

    private func submitCommand() {
        guard !commandInput.isEmpty else { return }

        // Check if the command is potentially destructive
        if isDestructiveCommand(commandInput) {
            commandToConfirm = commandInput
            isDestructiveCommand = true
            showCommandConfirmation = true
        } else {
            executeCommand(commandInput)
        }
    }

    private func handleCommandDetected(_ command: String) {
        if isDestructiveCommand(command) {
            commandToConfirm = command
            isDestructiveCommand = true
            showCommandConfirmation = true
        } else {
            executeCommand(command)
        }
    }

    private func executeCommand(_ command: String) {
        // Use the new helper method in TerminalSession
        terminalSession.sendCommandToProcess(command)
        commandInput = ""

        // Add to command history
        let historyItem = CommandHistoryItem(
            id: UUID(),
            command: command,
            output: "",
            timestamp: Date(),
            isAIGenerated: false
        )
        appState.commandHistory.append(historyItem)
    }

    private func restartTerminalSession() async {
        // TODO: Refactor restart logic.
        // This now requires getting the TerminalView instance associated with the session.
        // Temporarily commenting out to allow build.
        /*
        guard let view = terminalSession.terminalView else {
            print("Cannot restart session: TerminalView reference missing.")
            return
        }
        await terminalSession.startSession(terminalView: view)
        */
        print("Restart functionality needs refactoring after SwiftTerm.LocalProcess change.")
    }

    private func isDestructiveCommand(_ command: String) -> Bool {
        let destructivePatterns = [
            "^\\s*rm\\s",
            "^\\s*sudo\\s+rm\\s",
            "^\\s*mv\\s",
            "^\\s*dd\\s",
            "^\\s*rmdir\\s",
            "^\\s*truncate\\s",
            "^\\s*shred\\s",
            "^\\s*sudo\\s+mkfs",
        ]

        return destructivePatterns.contains { pattern in
            command.range(of: pattern, options: .regularExpression) != nil
        }
    }
    // MARK: - Size Preference Key

    private struct SizePreferenceKey: PreferenceKey {
        static let defaultValue: CGSize = .zero

        static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
            value = nextValue()
        }
    }
}

// MARK: - Preview Provider

struct TerminalTabView_Previews: PreviewProvider {
    static var previews: some View {
        TerminalTabView(terminalSession: TerminalSession())
            .environmentObject(AppState())
    }
}

// MARK: - SwiftTermViewRepresentable

/// SwiftUI wrapper for SwiftTerm's terminal view
struct SwiftTermViewRepresentable: NSViewRepresentable {
    typealias NSViewType = TerminalView  // Use TerminalView directly

    var session: TerminalSession
    @Binding var terminalSize: CGSize  // Represents target Cols/Rows now
    var onCommandDetected: (String) -> Void

    func makeNSView(context: Context) -> TerminalView {
        print("[Representable] makeNSView called.")  // DEBUG
        // Create the terminal view
        let terminalView = TerminalView(frame: .zero)

        // Configure the terminal view
        terminalView.terminalDelegate = context.coordinator

        // Link the session to this view and start the process
        // Must be done *after* terminalView is initialized
        Task { @MainActor in
            print("[Representable] Calling session.startSession")  // DEBUG
            await session.startSession(terminalView: terminalView)

            // Attempt to make the terminal view the first responder *after* session starts
            // Needs a slight delay to ensure the view is fully in the hierarchy
            DispatchQueue.main.async {
                print("[Representable] Attempting makeFirstResponder on terminalView")  // DEBUG
                if let window = terminalView.window, window.firstResponder != terminalView {
                    let success = window.makeFirstResponder(terminalView)
                    print("[Representable] makeFirstResponder success: \(success)")  // DEBUG
                } else if terminalView.window == nil {
                    print("[Representable] makeFirstResponder failed: window is nil")  // DEBUG
                } else {
                    print("[Representable] makeFirstResponder skipped: already first responder")  // DEBUG
                }
            }
        }

        // Set up initial emulator size (process size set in startSession)
        let initialCols = Int(terminalSize.width)
        let initialRows = Int(terminalSize.height)
        print("[Representable] Initial resize of emulator to \(initialCols)x\(initialRows)")  // DEBUG
        terminalView.terminal?.resize(cols: initialCols, rows: initialRows)

        return terminalView
    }

    @MainActor
    func updateNSView(_ nsView: TerminalView, context: Context) {
        // TerminalView is already the correct type
        // Calculate target dimensions for the *emulator*
        let targetCols = Int(terminalSize.width)
        let targetRows = Int(terminalSize.height)

        // Get the terminal emulator and resize if needed
        guard let terminal = nsView.terminal else {
            print("[Representable] Warning: Terminal emulator not available during updateNSView")  // DEBUG
            return
        }

        if terminal.cols != targetCols || terminal.rows != targetRows {
            print("[Representable] Resizing emulator to \(targetCols)x\(targetRows)")  // DEBUG
            terminal.resize(cols: targetCols, rows: targetRows)
            // The PTY/process size is updated via the session's updateSize method,
            // which should be called by the Coordinator's sizeChanged delegate.
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    @MainActor
    class Coordinator: NSObject, TerminalViewDelegate {
        // Properties stored from init
        let parentView: SwiftTermViewRepresentable
        let terminalSession: TerminalSession
        let commandCallback: (String) -> Void

        init(_ parent: SwiftTermViewRepresentable) {
            self.parentView = parent
            self.terminalSession = parent.session  // Store session
            self.commandCallback = parent.onCommandDetected  // Store callback
            super.init()
        }

        // MARK: - TerminalViewDelegate Implementations

        // REMOVED @MainActor properties for command tracking here,
        // as TerminalSession should manage command state if needed.

        // MODIFIED: Send data to the TerminalSession
        nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let session = self.terminalSession
            let str = String(bytes: data, encoding: .utf8) ?? "Non-UTF8"
            print(
                "[Coordinator] send delegate called, forwarding to session.sendToProcess: \(str.replacingOccurrences(of: "\n", with: "\\\\n").replacingOccurrences(of: "\r", with: "\\\\r"))"
            )

            // Dispatch the call to the MainActor isolated session method
            Task { @MainActor in
                session.sendToProcess(data: data)
            }
        }

        // clipboardCopy remains the same
        nonisolated func clipboardCopy(source: TerminalView, content: Data) {
            if let string = String(data: content, encoding: .utf8) {
                Task { @MainActor in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(string, forType: .string)
                }
            }
        }

        // rangeChanged remains empty
        nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

        // MODIFIED: sizeChanged calls session.updateSize
        nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            let session = self.terminalSession
            print("[Coordinator] sizeChanged delegate: \(newCols)x\(newRows)")  // DEBUG
            // Update the session (which updates PTY)
            Task { @MainActor in
                session.updateSize(cols: newCols, rows: newRows)
            }
            // The parent @State terminalSize binding might need separate update if UI depends on it?
            // Currently, updateNSView uses the binding, so this delegate *might* not need to update parentView state.
        }

        // setTerminalTitle should update the session's CWD
        nonisolated func setTerminalTitle(source: TerminalView, title: String) {
            let session = self.terminalSession
            Task { @MainActor in
                print("[Coordinator] setTerminalTitle delegate: \(title)")  // DEBUG
                let displayTitle =
                    title  // ... processing ...
                    .replacingOccurrences(of: NSString("~").expandingTildeInPath, with: "~")
                    .replacingOccurrences(of: "file://", with: "")
                if displayTitle.contains("/") || displayTitle.hasPrefix("~") {
                    session.currentWorkingDirectory = displayTitle
                }
                // Potentially update parentView tab title here if needed
                // parentView.session.tabTitle = displayTitle // Example if tab title state exists
            }
        }

        // hostCurrentDirectoryUpdate should update the session's CWD
        nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            let session = self.terminalSession
            Task { @MainActor in
                print("[Coordinator] hostCurrentDirectoryUpdate delegate: \(directory ?? "nil")")  // DEBUG
                if let directory = directory {
                    let processedDir =
                        directory  // ... processing ...
                        .replacingOccurrences(of: NSString("~").expandingTildeInPath, with: "~")
                        .replacingOccurrences(of: "file://", with: "")
                    session.currentWorkingDirectory = processedDir
                }
            }
        }

        // bell, scrolled, requestOpenLink, setTerminalIconTitle remain mostly the same
        nonisolated func bell(source: TerminalView) { Task { @MainActor in NSSound.beep() } }
        nonisolated func scrolled(source: TerminalView, position: Double) {}
        nonisolated func requestOpenLink(
            source: TerminalView, link: String, params: [String: String]
        ) { Task { @MainActor in if let url = URL(string: link) { NSWorkspace.shared.open(url) } } }
        nonisolated func setTerminalIconTitle(source: TerminalView, title: String) {
            Task { @MainActor in if let window = source.window { window.title = title } }
        }

    }  // End of Coordinator class
}  // End of struct SwiftTermViewRepresentable
