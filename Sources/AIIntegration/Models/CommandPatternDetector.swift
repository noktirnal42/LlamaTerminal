import Foundation

/// Represents different types of terminal command patterns
public enum CommandPatternType: String, Codable, Sendable {
    /// File system navigation and manipulation commands
    case fileSystem
    
    /// Search-related commands (grep, find, etc.)
    case searchPattern
    
    /// Network-related commands (curl, wget, ping, etc.)
    case network
    
    /// Process management commands (ps, kill, etc.)
    case processManagement
    
    /// Package management commands (apt, brew, npm, etc.)
    case packageManagement
    
    /// Git and version control commands
    case versionControl
    
    /// Text processing commands (awk, sed, etc.)
    case textProcessing
    
    /// System configuration commands
    case systemConfig
    
    /// Archive handling commands (tar, zip, etc.)
    case archiveManagement
    
    /// Shell scripting commands
    case shellScripting
    
    /// Docker and container-related commands
    case containerization
    
    /// Database-related commands
    case database
    
    /// Miscellaneous/unclassified commands
    case other
}

/// Represents the priority level for command suggestions
public enum SuggestionPriority: String, Codable, Sendable {
    /// High priority suggestions that should be shown immediately
    case immediate
    
    /// Lower priority suggestions that can be processed in the background
    case background
    
    /// Critical suggestions that require user attention
    case critical
    
    /// Default priority level
    case normal
}

/// A class that analyzes terminal commands to detect patterns and categorize them
public class CommandPatternDetector: Sendable {
    // Pattern matchers for different command types
    private let fileSystemPatterns = [
        "ls", "cd", "pwd", "mkdir", "rmdir", "rm", "cp", "mv", "touch",
        "chmod", "chown", "find .*-type [fd]", "df", "du"
    ]
    
    private let searchPatterns = [
        "grep", "find", "locate", "which", "whereis", "ack", "ag"
    ]
    
    private let networkPatterns = [
        "curl", "wget", "ping", "traceroute", "netstat", "ifconfig",
        "ip ", "ssh", "scp", "rsync", "nc", "telnet", "nslookup", "dig"
    ]
    
    private let processPatterns = [
        "ps", "kill", "pkill", "top", "htop", "pgrep", "jobs", "bg", "fg", "nice"
    ]
    
    private let packagePatterns = [
        "apt", "apt-get", "yum", "dnf", "brew", "npm", "pip", "gem",
        "cargo", "pacman", "snap", "flatpak"
    ]
    
    private let versionControlPatterns = [
        "git", "svn", "hg"
    ]
    
    private let textProcessingPatterns = [
        "awk", "sed", "cut", "sort", "uniq", "tr", "wc", "head", "tail"
    ]
    
    private let systemConfigPatterns = [
        "uname", "hostname", "sysctl", "systemctl", "service", "dmesg", "journalctl"
    ]
    
    private let archivePatterns = [
        "tar", "zip", "unzip", "gzip", "gunzip", "bzip2", "xz", "7z", "rar"
    ]
    
    private let shellScriptingPatterns = [
        "if ", "for ", "while ", "until ", "case ", "function ", "source ",
        "export ", "alias ", "echo", "printf", "eval", "exec", "./"
    ]
    
    private let containerPatterns = [
        "docker", "podman", "kubectl", "k8s", "helm", "minikube"
    ]
    
    private let databasePatterns = [
        "mysql", "psql", "sqlite", "mongo", "redis-cli"
    ]
    
    /// Initialize a new command pattern detector
    public init() {}
    
    /// Detects the pattern type of a command
    /// - Parameter command: The command string to analyze
    /// - Returns: The detected pattern type or nil if no pattern was detected
    public func detectPattern(in command: String) -> CommandPatternType? {
        let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Check for empty commands
        guard !normalizedCommand.isEmpty else { return nil }
        
        // Check against each pattern category
        if matchesAnyPattern(normalizedCommand, patterns: fileSystemPatterns) {
            return .fileSystem
        }
        
        if matchesAnyPattern(normalizedCommand, patterns: searchPatterns) {
            return .searchPattern
        }
        
        if matchesAnyPattern(normalizedCommand, patterns: networkPatterns) {
            return .network
        }
        
        if matchesAnyPattern(normalizedCommand, patterns: processPatterns) {
            return .processManagement
        }
        
        if matchesAnyPattern(normalizedCommand, patterns: packagePatterns) {
            return .packageManagement
        }
        
        if matchesAnyPattern(normalizedCommand, patterns: versionControlPatterns) {
            return .versionControl
        }
        
        if matchesAnyPattern(normalizedCommand, patterns: textProcessingPatterns) {
            return .textProcessing
        }
        
        if matchesAnyPattern(normalizedCommand, patterns: systemConfigPatterns) {
            return .systemConfig
        }
        
        if matchesAnyPattern(normalizedCommand, patterns: archivePatterns) {
            return .archiveManagement
        }
        
        if matchesAnyPattern(normalizedCommand, patterns: shellScriptingPatterns) {
            return .shellScripting
        }
        
        if matchesAnyPattern(normalizedCommand, patterns: containerPatterns) {
            return .containerization
        }
        
        if matchesAnyPattern(normalizedCommand, patterns: databasePatterns) {
            return .database
        }
        
        // Default case
        return .other
    }
    
    /// Determines if a command contains any of the specified patterns
    /// - Parameters:
    ///   - command: The command to check
    ///   - patterns: The list of patterns to match against
    /// - Returns: True if the command matches any pattern
    private func matchesAnyPattern(_ command: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            // For patterns with spaces, check if the command contains the whole pattern
            if pattern.contains(" ") {
                if command.contains(pattern) {
                    return true
                }
            } 
            // For single-word commands, match at the beginning of the command or after pipe/semicolon
            else {
                let commandComponents = command.components(separatedBy: CharacterSet(charactersIn: "|;"))
                
                for component in commandComponents {
                    let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix(pattern) ||
                       trimmed.hasPrefix("sudo \(pattern)") ||
                       trimmed.matches(of: try! Regex("\\b\(pattern)\\b")).count > 0 {
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    /// Analyzes a command and returns its complexity level
    /// - Parameter command: The command string to analyze
    /// - Returns: A value between 0.0 (simple) and 1.0 (complex)
    public func analyzeComplexity(of command: String) -> Double {
        let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Simple heuristics for command complexity
        var complexity = 0.0
        
        // Length-based complexity (longer commands tend to be more complex)
        complexity += min(Double(normalizedCommand.count) / 100.0, 0.3)
        
        // Operator-based complexity (more operators indicate more complex commands)
        let operators = ["|", ";", "&&", "||", ">", ">>", "<", "2>", "&"]
        for op in operators {
            complexity += Double(normalizedCommand.components(separatedBy: op).count - 1) * 0.05
        }
        
        // Special character complexity
        let specialChars = CharacterSet(charactersIn: "{}[]()$*?^!`\"'\\")
        let specialCharCount = normalizedCommand.filter { specialChars.contains($0.unicodeScalars.first!) }.count
        complexity += Double(specialCharCount) * 0.02
        
        // Command count complexity
        let commandCount = normalizedCommand.components(separatedBy: CharacterSet(charactersIn: "|;")).count
        complexity += Double(commandCount - 1) * 0.1
        
        // Flag complexity
        let flagCount = normalizedCommand.matches(of: try! Regex("\\s-[a-zA-Z]+")).count
        complexity += Double(flagCount) * 0.03
        
        // Long option complexity
        let longOptionCount = normalizedCommand.matches(of: try! Regex("\\s--[a-zA-Z0-9-]+")).count
        complexity += Double(longOptionCount) * 0.05
        
        // Cap the complexity between 0.0 and 1.0
        return min(max(complexity, 0.0), 1.0)
    }
    
    /// Determines the suggestion priority based on command pattern and complexity
    /// - Parameters:
    ///   - command: The command to analyze
    ///   - patternType: Optional pre-detected pattern type
    /// - Returns: The appropriate suggestion priority
    public func determineSuggestionPriority(for command: String, patternType: CommandPatternType? = nil) -> SuggestionPriority {
        let pattern = patternType ?? detectPattern(in: command)
        let complexity = analyzeComplexity(of: command)
        
        // Determine priority based on pattern type and complexity
        switch pattern {
        case .processManagement, .systemConfig:
            // System-critical commands get immediate attention
            return .immediate
            
        case .fileSystem where command.contains("rm "):
            // Destructive file operations get immediate attention
            return .critical
            
        case .versionControl where command.contains("git reset") || command.contains("git push -f"):
            // Potentially destructive git operations get critical attention
            return .critical
            
        case nil:
            // Unknown patterns get normal priority
            return .normal
            
        default:
            // For other patterns, base on complexity
            if complexity > 0.7 {
                return .immediate
            } else if complexity > 0.3 {
                return .normal
            } else {
                return .background
            }
        }
    }
}

