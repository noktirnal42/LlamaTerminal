import SwiftUI

public struct WelcomeView: View {
    private var isOllamaInstalled: Bool
    @State private var hideWelcomeOnStartup: Bool = UserDefaults.standard.bool(
        forKey: "hideWelcomeScreen")
    @Environment(\.dismiss) private var dismiss

    public init(isOllamaInstalled: Bool) {
        self.isOllamaInstalled = isOllamaInstalled
    }

    public var body: some View {
        VStack(spacing: 30) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)

                Text("Welcome to LlamaTerminal")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("A modern terminal with integrated AI assistance")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)

            // Feature highlights
            VStack(alignment: .leading, spacing: 20) {
                featureRow(
                    icon: "wand.and.stars", title: "AI Assistant",
                    description: "Get help with commands, code, and more")
                featureRow(
                    icon: "command", title: "Command Suggestions",
                    description: "Intelligent command recommendations")
                featureRow(
                    icon: "key", title: "Keyboard Friendly",
                    description: "Optimized keyboard shortcuts for efficient workflow")
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.windowBackgroundColor)))

            // Ollama integration
            if !isOllamaInstalled {
                VStack(spacing: 10) {
                    Text("For the best experience, install Ollama")
                        .font(.headline)

                    Button("Get Ollama") {
                        NSWorkspace.shared.open(URL(string: "https://ollama.ai")!)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.yellow.opacity(0.2)))
            }

            // Settings
            Toggle("Don't show this screen at startup", isOn: $hideWelcomeOnStartup)
                .padding()
                .onChange(of: hideWelcomeOnStartup) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "hideWelcomeScreen")
                }

            // Start button
            Button("Start Using LlamaTerminal") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 20)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .frame(width: 36, height: 36)
                .foregroundStyle(.blue)

            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
