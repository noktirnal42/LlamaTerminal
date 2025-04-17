import SwiftUI
import AIIntegration
import SharedModels // Changed import from App to SharedModels
import SharedModels // Ensure SharedModels is imported

/// View for selecting and managing Ollama models
public struct ModelSelectionView: View {
    // Ensure properties are inside the struct
    @EnvironmentObject private var appState: AppState
    // Add other @State/@Environment properties if they were previously outside
    @State private var newModelName: String = ""
    @State private var showDeleteConfirmation: Bool = false
    @State private var modelToDelete: AIModel? = nil
    @State private var isRefreshing: Bool = false
    @State private var isPullingModel: Bool = false
    @State private var pullProgress: Double = 0.0
    @State private var pullStatusMessage: String = ""
    @State private var loadingError: Error? = nil
    @Environment(\.dismiss) private var dismiss
    
    public init() {}

    // Hardcoded list of popular models for easy pulling
    private let popularModels = ["llama3", "codellama", "mistral", "gemma"] // Example popular models

    /// View for a single model row
    private func modelRow(_ model: AIModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .fontWeight(appState.selectedModel?.id == model.id ? .bold : .regular)

                HStack(spacing: 12) {
                    // Size
                    HStack(spacing: 4) {
                        Image(systemName: "archivebox")
                            .font(.caption)
                        Text(model.formattedSize)
                            .font(.caption)
                    }

                    // Last modified
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption)
                        Text(model.formattedDate)
                            .font(.caption)
                    }
                }
                .foregroundColor(.secondary)
            }

            Spacer()

            // Model capabilities
            HStack(spacing: 8) {
                if model.capabilities.isCodeCapable {
                    Image(systemName: "curlybraces")
                        .foregroundColor(.blue)
                        .help("Optimized for code generation")
                }

                if model.capabilities.isMultimodal {
                    Image(systemName: "photo")
                        .foregroundColor(.green)
                        .help("Supports image input")
                }

                if model.capabilities.isCommandOptimized {
                    Image(systemName: "terminal")
                        .foregroundColor(.purple)
                        .help("Optimized for command generation")
                }
            }

            // Selection button
            Button(action: {
                appState.selectedModel = model
            }) {
                Text(appState.selectedModel?.id == model.id ? "Selected" : "Select")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(appState.selectedModel?.id == model.id ? Color.green.opacity(0.2) : Color.blue.opacity(0.1))
                    .foregroundColor(appState.selectedModel?.id == model.id ? .green : .blue)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain) // Use plain button style

            // Delete button
            Button(action: {
                modelToDelete = model
                showDeleteConfirmation = true
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(appState.selectedModel?.id == model.id ? Color.blue.opacity(0.05) : Color.clear)
        .cornerRadius(8)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Manage Models")
                    .font(.title2)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)

            // Pull New Model Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Pull New Model").font(.headline)
                HStack {
                    TextField("Enter model name (e.g., llama3:latest)", text: $newModelName)
                        .textFieldStyle(.roundedBorder)

                    Button("Pull") {
                        pullModel()
                    }
                    .disabled(isPullingModel || newModelName.isEmpty)
                    .buttonStyle(.borderedProminent)
                }

                if isPullingModel {
                    VStack(alignment: .leading) {
                        ProgressView(value: pullProgress)
                            .progressViewStyle(.linear)
                        Text(pullStatusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }

            // Popular Models Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Popular Models").font(.headline)
                HStack {
                    ForEach(popularModels, id: \.self) { modelName in
                        Button(modelName) {
                            newModelName = modelName
                            pullModel()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isPullingModel)
                    }
                }
            }

            Divider()

            // Installed Models Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Installed Models").font(.headline)
                    Spacer()
                    Button {
                        refreshModels()
                    } label: {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)
                    .help("Refresh model list")
                }

                if let error = loadingError {
                    Text("Error: \(error.localizedDescription)")
                        .foregroundColor(.red)
                        .font(.callout)
                }

                if appState.availableModels.isEmpty && !isRefreshing && loadingError == nil {
                    Text("No models installed locally. Pull a model above or run 'ollama list' in your terminal.")
                        .foregroundColor(.secondary)
                        .font(.callout)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    List {
                        ForEach(appState.availableModels) { model in
                            modelRow(model)
                        }
                    }
                    .listStyle(.plain) // Use plain list style for better integration
                    .frame(maxHeight: 300) // Limit height to prevent excessive growth
                }
            }

            Spacer() // Pushes content to the top
        }
        .padding()
        .frame(width: 600)
        .background(Color(NSColor.windowBackgroundColor)) // Use system background
        .onAppear {
            refreshModels() // Initial load
        }
        .alert("Delete Model?", isPresented: $showDeleteConfirmation, presenting: modelToDelete) { model in
            Button("Delete", role: .destructive) {
                deleteModel(model)
            }
            Button("Cancel", role: .cancel) {
                modelToDelete = nil // Ensure we clear the state on cancel
            }
        } message: { model in
             Text("Are you sure you want to delete the model '\(model.name)'? This action cannot be undone.")
        }
    }


    // MARK: - Helper Functions (Moved inside struct)
    // Removed misplaced code block from original lines 118-202

    // Placeholder body is now active (line 106) -> THIS COMMENT IS NO LONGER TRUE
    /* // Original Body - Commented out
     public var body: some View {
         VStack(spacing: 0) {
            // ... original content ...
         }
         .frame(width: 600)
         .background(Color(NSColor.controlBackgroundColor))
         .onAppear { ... }
         .alert(...) { ... }
     }
     */

    // MARK: - Helper Functions (Ensure they are inside the struct)
    // MARK: - Helper Functions (Moved inside struct)

    /// Refreshes the list of available models from Ollama
    /// Refreshes the list of available models from Ollama
    private func refreshModels() {
        self.isRefreshing = true
        self.loadingError = nil // Clear previous errors
        Task {
            do {
                // Assuming AppState has a method to refresh models which uses OllamaModelService
                try await self.appState.refreshAvailableModels()
            } catch {
                self.loadingError = error
                print("Error refreshing models: \(error)") // Log the error
            }
            self.isRefreshing = false
        }
    }
    /// Initiates pulling a new model
    private func pullModel() {
        // Implementation likely exists in AppState or needs to be added,
        // potentially using OllamaModelService.pullModel
        // Example structure:
        // isPullingModel = true
        // pullProgress = 0
        // pullStatusMessage = "Starting download..."
        // Task {
        //     do {
        //         for try await progressUpdate in try await appState.pullModel(name: newModelName) {
        //             pullProgress = progressUpdate.progress
        //             pullStatusMessage = progressUpdate.status
        //         }
        //         pullStatusMessage = "Model pulled successfully!"
        //         refreshModels() // Refresh list after pulling
        //     } catch {
        //         pullStatusMessage = "Error pulling model: \(error.localizedDescription)"
        //     }
        //     isPullingModel = false
        // }
        print("Pull model '\(self.newModelName)' requested. Implementation needed in AppState.")
    }
    /// Deletes the specified model
    private func deleteModel(_ model: AIModel) {
        // Implementation likely exists in AppState or needs to be added,
        // potentially using OllamaModelService.deleteModel
        // Example structure:
        // Task {
        //     do {
        //         try await appState.deleteModel(model)
        //         refreshModels() // Refresh list after deleting
        //     } catch {
        //         // Handle error (e.g., show alert)
        //         print("Error deleting model: \(error)")
        //     }
        // }
         print("Delete model '\(model.name)' requested. Implementation needed in AppState.")
         self.modelToDelete = nil // Clear selection after attempting delete
    }
} // End of struct ModelSelectionView
