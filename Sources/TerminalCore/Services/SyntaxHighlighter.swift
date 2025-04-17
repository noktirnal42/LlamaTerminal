import Foundation
import SwiftTerm
import SwiftUI

/// Protocol defining the core functionality of a syntax highlighter
public protocol SyntaxHighlighter {
    /// Highlights the given text according to syntax rules
    /// - Parameters:
    ///   - text: Text to highlight
    ///   - theme: Color theme to use
    /// - Returns: AttributedString with appropriate highlighting
    func highlight(text: String, theme: HighlightTheme) -> AttributedString

    /// Processes output text in real-time for terminal display
    /// - Parameters:
    ///   - text: Text to process
    ///   - theme: Color theme to use
    /// - Returns: String with ANSI escape sequences for terminal colors
    func highlightForTerminal(text: String, theme: HighlightTheme) -> String
}

/// Represents a color theme for syntax highlighting
public struct HighlightTheme: Equatable, Hashable, Sendable {
    /// The name of the theme
    public let name: String

    /// Background color
    public let background: TerminalColor

    /// Default foreground color for text
    public let foreground: TerminalColor

    /// Color for command names
    public let command: TerminalColor

    /// Color for options and flags
    public let option: TerminalColor

    /// Color for parameter values
    public let parameter: TerminalColor

    /// Color for quoted strings
    public let string: TerminalColor

    /// Color for numeric values
    public let number: TerminalColor

    /// Color for comments
    public let comment: TerminalColor

    /// Color for keywords
    public let keyword: TerminalColor

    /// Color for variables
    public let variable: TerminalColor

    /// Color for function names
    public let function: TerminalColor

    /// Color for paths and file names
    public let path: TerminalColor

    /// Color for errors and warnings
    public let error: TerminalColor

    /// Creates a new HighlightTheme
    public init(
        name: String,
        background: TerminalColor,
        foreground: TerminalColor,
        command: TerminalColor,
        option: TerminalColor,
        parameter: TerminalColor,
        string: TerminalColor,
        number: TerminalColor,
        comment: TerminalColor,
        keyword: TerminalColor,
        variable: TerminalColor,
        function: TerminalColor,
        path: TerminalColor,
        error: TerminalColor
    ) {
        self.name = name
        self.background = background
        self.foreground = foreground
        self.command = command
        self.option = option
        self.parameter = parameter
        self.string = string
        self.number = number
        self.comment = comment
        self.keyword = keyword
        self.variable = variable
        self.function = function
        self.path = path
        self.error = error
    }
}

/// Predefined terminal color themes
extension HighlightTheme {
    /// Dark theme with vibrant colors
    public static let dark = HighlightTheme(
        name: "Dark",
        background: .black,
        foreground: .white,
        command: .brightGreen,
        option: .brightBlue,
        parameter: .brightCyan,
        string: .brightYellow,
        number: .magenta,
        comment: .brightBlack,
        keyword: .brightRed,
        variable: .brightMagenta,
        function: .green,
        path: .cyan,
        error: .red
    )

    /// Light theme with subdued colors
    public static let light = HighlightTheme(
        name: "Light",
        background: .white,
        foreground: .black,
        command: .green,
        option: .blue,
        parameter: .cyan,
        string: .yellow,
        number: .magenta,
        comment: .brightBlack,
        keyword: .red,
        variable: .magenta,
        function: .brightGreen,
        path: .brightCyan,
        error: .brightRed
    )

    /// High contrast theme
    public static let highContrast = HighlightTheme(
        name: "High Contrast",
        background: .black,
        foreground: .white,
        command: .brightYellow,
        option: .brightGreen,
        parameter: .brightCyan,
        string: .brightWhite,
        number: .brightMagenta,
        comment: .brightBlack,
        keyword: .brightRed,
        variable: .brightBlue,
        function: .brightYellow,
        path: .brightWhite,
        error: .brightRed
    )
}

/// Terminal colors for syntax highlighting
public enum TerminalColor: String, Equatable, Hashable, Sendable {
    case black = "0"
    case red = "1"
    case green = "2"
    case yellow = "3"
    case blue = "4"
    case magenta = "5"
    case cyan = "6"
    case white = "7"
    case brightBlack = "90"
    case brightRed = "91"
    case brightGreen = "92"
    case brightYellow = "93"
    case brightBlue = "94"
    case brightMagenta = "95"
    case brightCyan = "96"
    case brightWhite = "97"

    /// Converts the color to an ANSI escape sequence for foreground color
    public var ansiCode: String {
        return "\u{001B}[3\(rawValue)m"
    }

    /// Converts the color to an ANSI escape sequence for foreground color
    public var ansiBrightCode: String {
        return "\u{001B}[9\(rawValue)m"
    }

    /// Converts the color to an ANSI escape sequence for background color
    public var ansiBackgroundCode: String {
        return "\u{001B}[4\(rawValue)m"
    }

    /// ANSI reset code
    public static let reset = "\u{001B}[0m"
}

/// Converts a TerminalColor to a SwiftUI Color
private func colorFromTerminalColor(_ terminalColor: TerminalColor) -> SwiftUI.Color {
    switch terminalColor {
    case .black: return SwiftUI.Color.black
    case .red: return SwiftUI.Color.red
    case .green: return SwiftUI.Color.green
    case .yellow: return SwiftUI.Color.yellow
    case .blue: return SwiftUI.Color.blue
    case .magenta: return SwiftUI.Color.purple
    case .cyan: return SwiftUI.Color.cyan
    case .white: return SwiftUI.Color.white
    case .brightBlack: return SwiftUI.Color.gray
    case .brightRed: return SwiftUI.Color.red.opacity(0.8)
    case .brightGreen: return SwiftUI.Color.green.opacity(0.8)
    case .brightYellow: return SwiftUI.Color.yellow.opacity(0.8)
    case .brightBlue: return SwiftUI.Color.blue.opacity(0.8)
    case .brightMagenta: return SwiftUI.Color.purple.opacity(0.8)
    case .brightCyan: return SwiftUI.Color.cyan.opacity(0.8)
    case .brightWhite: return SwiftUI.Color.white.opacity(0.8)
    }
}

/// Concrete implementation of SyntaxHighlighter for shell commands
public class ShellCommandHighlighter: SyntaxHighlighter {
    /// Regular expressions for shell command syntax
    private struct Patterns {
        // Command (the first word on a line or after a pipe/semicolon)
        static let command = try! NSRegularExpression(pattern: "(?:^|;|\\|)\\s*(\\S+)")

        // Options (words starting with - or --)
        static let option = try! NSRegularExpression(pattern: "\\s(-{1,2}\\w+(?:-\\w+)*)")

        // Parameters (words after options, not starting with special characters)
        static let parameter = try! NSRegularExpression(pattern: "\\s(-{1,2}\\w+)\\s+(\\S+)")

        // Quoted strings (both single and double quotes)
        static let string = try! NSRegularExpression(pattern: "(['\"])(.*?)\\1")

        // Numbers (integers, decimals, hex)
        static let number = try! NSRegularExpression(
            pattern: "\\b(\\d+(?:\\.\\d+)?|0x[0-9a-fA-F]+)\\b")

        // Variables ($VAR or ${VAR})
        static let variable = try! NSRegularExpression(pattern: "(\\$\\w+|\\$\\{\\w+\\})")

        // File paths
        static let path = try! NSRegularExpression(pattern: "(?:\\s|=)(/(?:[\\w.-]+/)*[\\w.-]+)")

        // Comments (starting with #)
        static let comment = try! NSRegularExpression(pattern: "#.*$")
    }

    /// Common shell commands for optimized pattern matching
    private let commonCommands: Set<String> = [
        "cd", "ls", "grep", "find", "echo", "cat", "cp", "mv", "rm", "mkdir",
        "touch", "chmod", "chown", "curl", "wget", "ssh", "scp", "git", "brew",
        "python", "python3", "pip", "node", "npm", "yarn", "docker", "make",
    ]

    public init() {}

    public func highlight(text: String, theme: HighlightTheme) -> AttributedString {
        var attributedString = AttributedString(text)

        // Apply base foreground color
        attributedString.foregroundColor = colorFromTerminalColor(theme.foreground)

        // Highlight commands
        highlightPattern(Patterns.command, in: text, with: theme.command, on: &attributedString)

        // Highlight options
        highlightPattern(Patterns.option, in: text, with: theme.option, on: &attributedString)

        // Highlight parameters
        highlightPattern(
            Patterns.parameter, in: text, with: theme.parameter, on: &attributedString,
            captureGroup: 2)

        // Highlight strings
        highlightPattern(
            Patterns.string, in: text, with: theme.string, on: &attributedString, captureGroup: 2)

        // Highlight numbers
        highlightPattern(Patterns.number, in: text, with: theme.number, on: &attributedString)

        // Highlight variables
        highlightPattern(Patterns.variable, in: text, with: theme.variable, on: &attributedString)

        // Highlight paths
        highlightPattern(
            Patterns.path, in: text, with: theme.path, on: &attributedString, captureGroup: 1)

        // Highlight comments - must be last to override other highlights
        highlightPattern(Patterns.comment, in: text, with: theme.comment, on: &attributedString)

        return attributedString
    }

    public func highlightForTerminal(text: String, theme: HighlightTheme) -> String {
        var result = text

        // Apply ANSI color codes in reverse order to avoid index shifting issues

        // Comments (starting with #)
        result = applyAnsiColors(to: result, pattern: Patterns.comment, color: theme.comment)

        // Paths
        result = applyAnsiColors(
            to: result, pattern: Patterns.path, color: theme.path, captureGroup: 1)

        // Variables
        result = applyAnsiColors(to: result, pattern: Patterns.variable, color: theme.variable)

        // Numbers
        result = applyAnsiColors(to: result, pattern: Patterns.number, color: theme.number)

        // Strings
        result = applyAnsiColors(
            to: result, pattern: Patterns.string, color: theme.string, captureGroup: 2)

        // Parameters
        result = applyAnsiColors(
            to: result, pattern: Patterns.parameter, color: theme.parameter, captureGroup: 2)

        // Options
        result = applyAnsiColors(to: result, pattern: Patterns.option, color: theme.option)

        // Commands
        result = applyAnsiColors(
            to: result, pattern: Patterns.command, color: theme.command,
            transform: { match in
                // Trim whitespace and check if it's a known command
                let cmd = match.trimmingCharacters(in: .whitespacesAndNewlines)
                return self.commonCommands.contains(cmd) ? match : nil
            })

        return result
    }

    // MARK: - Private Helpers

    private func highlightPattern(
        _ pattern: NSRegularExpression,
        in text: String,
        with color: TerminalColor,
        on attributedString: inout AttributedString,
        captureGroup: Int = 1,
        transform: ((String) -> String?)? = nil
    ) {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)

        pattern.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match = match, match.numberOfRanges > captureGroup else { return }
            guard let range = Range(match.range(at: captureGroup), in: text) else { return }

            let matchText = String(text[range])

            // Apply optional transform
            if let transform = transform, transform(matchText) == nil {
                return
            }

            if let attributedRange = Range(range, in: attributedString) {
                // Convert TerminalColor to SwiftUI Color
                let swiftUIColor = colorFromTerminalColor(color)
                attributedString[attributedRange].foregroundColor = swiftUIColor
            }
        }
    }

    private func applyAnsiColors(
        to text: String,
        pattern: NSRegularExpression,
        color: TerminalColor,
        captureGroup: Int = 1,
        transform: ((String) -> String?)? = nil
    ) -> String {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = text
        var offset = 0

        pattern.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match = match, match.numberOfRanges > captureGroup else { return }
            guard let matchRange = Range(match.range(at: captureGroup), in: text) else { return }

            let matchText = String(text[matchRange])

            // Apply optional transform
            if let transform = transform, transform(matchText) == nil {
                return
            }

            let startOffset = matchRange.lowerBound.utf16Offset(in: text) + offset
            let length = matchText.utf16.count

            let coloredText = color.ansiCode + matchText + TerminalColor.reset
            let oldLength = matchText.utf16.count
            let newLength = coloredText.utf16.count

            let start = result.index(result.startIndex, offsetBy: startOffset)
            let end = result.index(start, offsetBy: length)
            result.replaceSubrange(start..<end, with: coloredText)

            offset += (newLength - oldLength)
        }

        return result
    }
}

/// Concrete implementation of SyntaxHighlighter for code highlighting
public class CodeHighlighter: SyntaxHighlighter {
    /// Supported programming languages
    public enum Language: String, CaseIterable {
        case swift
        case python
        case javascript
        case go
        case rust
        case bash
        case c
        case cpp
        case java
        case ruby
        case php
        case plain  // Fallback for unsupported languages

        /// Maps file extensions to languages
        public static func detect(from filename: String) -> Language {
            let ext = (filename as NSString).pathExtension.lowercased()

            switch ext {
            case "swift": return .swift
            case "py": return .python
            case "js", "ts", "jsx", "tsx": return .javascript
            case "go": return .go
            case "rs": return .rust
            case "sh", "bash", "zsh": return .bash
            case "c", "h": return .c
            case "cpp", "cc", "cxx", "hpp", "hxx": return .cpp
            case "java": return .java
            case "rb": return .ruby
            case "php": return .php
            default: return .plain
            }
        }
    }

    /// Regular expressions for code syntax by language
    private struct Patterns {
        static let commonKeywords = try! NSRegularExpression(
            pattern:
                "\\b(if|else|for|while|do|switch|case|break|continue|return|function|func|class|struct|enum|var|let|const|import|from|package|use)\\b"
        )

        static let swiftKeywords = try! NSRegularExpression(
            pattern:
                "\\b(if|else|for|while|do|switch|case|break|continue|return|func|class|struct|enum|protocol|extension|let|var|self|try|catch|guard|as|is|throw|throws|rethrows|typealias|associatedtype|import)\\b"
        )

        static let pythonKeywords = try! NSRegularExpression(
            pattern:
                "\\b(if|elif|else|for|while|def|class|import|from|as|try|except|finally|with|lambda|return|yield|global|nonlocal|pass|break|continue|and|or|not|is|in|True|False|None)\\b"
        )

        static let numberLiteral = try! NSRegularExpression(
            pattern: "\\b(\\d+(\\.\\d+)?|0x[0-9a-fA-F]+)\\b")

        static let stringLiteral = try! NSRegularExpression(
            pattern: "(\"[^\"\\\\]*(?:\\\\.[^\"\\\\]*)*\"|'[^'\\\\]*(?:\\\\.[^'\\\\]*)*')")

        static let comment = try! NSRegularExpression(pattern: "(//.*$|/\\*[\\s\\S]*?\\*/|#.*$)")

        static let function = try! NSRegularExpression(
            pattern: "\\b([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\(")

        static let className = try! NSRegularExpression(pattern: "\\b([A-Z][a-zA-Z0-9_]*)\\b")
    }

    public init() {}

    /// Highlights the given text according to language-specific syntax rules
    /// - Parameters:
    ///   - text: Text to highlight
    ///   - theme: Color theme to use
    /// - Returns: AttributedString with appropriate syntax highlighting
    public func highlight(text: String, theme: HighlightTheme) -> AttributedString {
        var attributedString = AttributedString(text)

        // Apply base foreground color
        attributedString.foregroundColor = colorFromTerminalColor(theme.foreground)

        // Apply language-specific highlighting
        // Apply highlights in reverse precedence order

        // Comments - highest precedence
        highlightPattern(Patterns.comment, in: text, with: theme.comment, on: &attributedString)

        // String literals
        highlightPattern(
            Patterns.stringLiteral, in: text, with: theme.string, on: &attributedString)

        // Number literals
        highlightPattern(
            Patterns.numberLiteral, in: text, with: theme.number, on: &attributedString)

        // Keywords based on language
        highlightPattern(
            Patterns.commonKeywords, in: text, with: theme.keyword, on: &attributedString)

        // Function calls
        highlightPattern(
            Patterns.function, in: text, with: theme.function, on: &attributedString,
            captureGroup: 1)

        // Class names
        highlightPattern(Patterns.className, in: text, with: theme.variable, on: &attributedString)

        return attributedString
    }

    /// Processes code text for terminal display with ANSI color sequences
    /// - Parameters:
    ///   - text: Text to process
    ///   - theme: Color theme to use
    /// - Returns: String with ANSI escape sequences for terminal colors
    public func highlightForTerminal(text: String, theme: HighlightTheme) -> String {
        var result = text

        // Apply ANSI color codes for code elements

        // Comments - must be first to handle multi-line comments correctly
        result = applyAnsiColors(to: result, pattern: Patterns.comment, color: theme.comment)

        // String literals
        result = applyAnsiColors(to: result, pattern: Patterns.stringLiteral, color: theme.string)

        // Numbers
        result = applyAnsiColors(to: result, pattern: Patterns.numberLiteral, color: theme.number)

        // Keywords
        result = applyAnsiColors(to: result, pattern: Patterns.commonKeywords, color: theme.keyword)

        // Function calls
        result = applyAnsiColors(
            to: result, pattern: Patterns.function, color: theme.function, captureGroup: 1)

        // Class names
        result = applyAnsiColors(to: result, pattern: Patterns.className, color: theme.variable)

        return result
    }

    // MARK: - Private Helpers

    /// Highlights a pattern in the text with the specified color
    /// - Parameters:
    ///   - pattern: Regular expression pattern to match
    ///   - text: Text to search
    ///   - color: Color to apply
    ///   - attributedString: AttributedString to modify
    ///   - captureGroup: Capture group to use (defaults to 0 for entire match)
    private func highlightPattern(
        _ pattern: NSRegularExpression,
        in text: String,
        with color: TerminalColor,
        on attributedString: inout AttributedString,
        captureGroup: Int = 0
    ) {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)

        pattern.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match = match, match.numberOfRanges > captureGroup else { return }
            guard let range = Range(match.range(at: captureGroup), in: text) else { return }

            if let attributedRange = Range(range, in: attributedString) {
                // AttributedString requires helper methods for accessing attributes
                // We're setting the foreground color based on the terminal color
                var attrs = AttributeContainer()
                attrs.foregroundColor = colorFromTerminalColor(color)
                attributedString[attributedRange].mergeAttributes(attrs)
            }
        }
    }

    /// Applies ANSI color codes to matched patterns
    /// - Parameters:
    ///   - text: Text to process
    ///   - pattern: Regular expression pattern to match
    ///   - color: Color to apply
    ///   - captureGroup: Capture group to use (defaults to 0 for entire match)
    /// - Returns: Text with ANSI color codes applied
    private func applyAnsiColors(
        to text: String,
        pattern: NSRegularExpression,
        color: TerminalColor,
        captureGroup: Int = 0
    ) -> String {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = text
        var offset = 0

        pattern.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match = match, match.numberOfRanges > captureGroup else { return }
            guard let matchRange = Range(match.range(at: captureGroup), in: text) else { return }

            let matchText = String(text[matchRange])

            let startOffset = matchRange.lowerBound.utf16Offset(in: text) + offset
            let length = matchText.utf16.count

            let coloredText = color.ansiCode + matchText + TerminalColor.reset
            let oldLength = matchText.utf16.count
            let newLength = coloredText.utf16.count

            let start = result.index(result.startIndex, offsetBy: startOffset)
            let end = result.index(start, offsetBy: length)
            result.replaceSubrange(start..<end, with: coloredText)

            offset += (newLength - oldLength)
        }

        return result
    }
}
