import SwiftUI

/// Displays error notifications in a toast-like UI
public struct ErrorNotificationView: View {
    /// Error message to display
    let message: String
    
    /// Error details
    let details: String?
    
    /// Whether the notification is visible
    @Binding var isVisible: Bool
    
    /// Initializes with error message
    /// - Parameters:
    ///   - message: Error message
    ///   - details: Optional error details
    ///   - isVisible: Binding to control visibility
    public init(message: String, details: String? = nil, isVisible: Binding<Bool>) {
        self.message = message
        self.details = details
        self._isVisible = isVisible
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                
                Text("Error")
                    .font(.headline)
                    .foregroundColor(.red)
                
                Spacer()
                
                Button {
                    withAnimation {
                        isVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Error message
            Text(message)
                .font(.body)
            
            // Error details
            if let details = details, !details.isEmpty {
                Text(details)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.95))
                .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
        )
        .padding()
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(100)
    }
}

/// View modifier for adding error notifications
public struct ErrorNotificationModifier: ViewModifier {
    /// Whether the notification is visible
    @Binding var isVisible: Bool
    
    /// Error message
    let message: String
    
    /// Error details
    let details: String?
    
    /// Initializes the modifier
    /// - Parameters:
    ///   - isVisible: Binding to control visibility
    ///   - message: Error message
    ///   - details: Optional error details
    public init(isVisible: Binding<Bool>, message: String, details: String? = nil) {
        self._isVisible = isVisible
        self.message = message
        self.details = details
    }
    
    public func body(content: Content) -> some View {
        ZStack {
            content
            
            if isVisible {
                VStack {
                    ErrorNotificationView(
                        message: message,
                        details: details,
                        isVisible: $isVisible
                    )
                    .padding(.top, 50)
                    
                    Spacer()
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: isVisible)
            }
        }
    }
}

/// Extension to add error notification convenience method
extension View {
    /// Adds an error notification to the view
    /// - Parameters:
    ///   - isVisible: Binding to control visibility
    ///   - message: Error message
    ///   - details: Optional error details
    /// - Returns: Modified view
    public func errorNotification(
        isVisible: Binding<Bool>,
        message: String,
        details: String? = nil
    ) -> some View {
        modifier(ErrorNotificationModifier(
            isVisible: isVisible,
            message: message,
            details: details
        ))
    }

