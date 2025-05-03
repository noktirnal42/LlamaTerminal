import Foundation
import OSLog

/// Logs security-related events for auditing purposes
public actor AuditLogger {
    /// Logger for system integration
    private let logger = Logger(subsystem: "com.llamaterminal", category: "AuditLogger")
    
    /// Singleton instance
    public static let shared = AuditLogger()
    
    /// Current log file
    private var currentLogFile: URL
    
    /// Configuration for logging
    private let config: LoggingConfig
    
    /// Maps severity levels to OSLog types
    private let severityToLogType: [Severity: OSLogType] = [
        .debug: .debug,
        .info: .info,
        .warning: .default,
        .error: .error,
        .critical: .fault
    ]
    
    /// Log severity levels
    public enum Severity: String, Codable {
        case debug
        case info
        case warning
        case error
        case critical
    }
    
    /// Event categories
    public enum Category: String, Codable {
        case command         // Command execution events
        case ai              // AI-related events
        case security        // Security-related events
        case system          // System events
        case error           // Error events
        case file            // File operation events
        case permission      // Permission-related events
        
        public init(rawValue: String) {
            switch rawValue {
            case "command": self = .command
            case "ai": self = .ai
            case "security": self = .security
            case "system": self = .system
            case "error": self = .error
            case "file": self = .file
            case "permission": self = .permission
            default: self = .system
            }
        }
    }
    
    /// Configuration for logging
    public struct LoggingConfig {
        /// Whether to include detailed information in logs
        public var includeDetailedInfo: Bool = true
        
        /// Directory to store log files
        public var logDirectory: URL
        
        /// Maximum size of a log file before rotation
        public var maxLogFileSize: UInt64 = 10 * 1024 * 1024  // 10 MB default
        
        /// Maximum number of log files to keep
        public var maxLogFiles: Int = 10
        
        /// Initializes a new logging configuration
        public init(logDirectory: URL? = nil) {
            if let directory = logDirectory {
                self.logDirectory = directory
            } else {
                // Default to a logs directory in Application Support
                let fileManager = FileManager.default
                let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                self.logDirectory = appSupportURL.appendingPathComponent("LlamaTerminal/Logs", isDirectory: true)
            }
            
            // Ensure log directory exists
            try? fileManager.createDirectory(at: self.logDirectory, withIntermediateDirectories: true)
        }
    }
    
    /// Log entry model
    public struct LogEntry: Codable {
        /// Timestamp of the entry
        public let timestamp: Date
        
        /// Event category
        public let category: String
        
        /// Event type
        public let event: String
        
        /// Human-readable message
        public let message: String
        
        /// Event severity
        public let severity: Severity
        
        /// Additional details
        public let details: [String: String]?
        
        /// Converts the entry to JSON
        public var asJSON: String? {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(self) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }
    
    /// Initializes the audit logger
    public init(config: LoggingConfig? = nil) {
        // Set up configuration
        self.config = config ?? LoggingConfig()
        
        // Set up initial log file
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        self.currentLogFile = self.config.logDirectory.appendingPathComponent("security-\(dateString).log")
        
        // Ensure log directory exists
        try? FileManager.default.createDirectory(at: self.config.logDirectory, withIntermediateDirectories: true)
    }
    
    /// Logs an event
    /// - Parameters:
    ///   - category: Event category
    ///   - event: Event type
    ///   - message: Human-readable message
    ///   - severity: Event severity
    ///   - details: Additional details
    public func logEvent(
        category: Category,
        event: String,
        message: String,
        severity: Severity = .info,
        details: [String: String]? = nil
    ) async {
        let entry = LogEntry(
            timestamp: Date(),
            category: category.rawValue,
            event: event,
            message: message,
            severity: severity,
            details: details
        )
        
        // Write to log file
        await writeEntryToFile(entry)
        
        // Also log to system
        logToSystem(entry)
    }
    
    /// Logs a command execution
    /// - Parameters:
    ///   - command: Command that was executed
    ///   - exitCode: Exit code (nil if not available)
    ///   - output: Command output (nil if not available)
    ///   - workingDirectory: Working directory when command was executed
    ///   - isAIGenerated: Whether the command was generated by AI
    public func logCommandExecution(
        command: String,
        exitCode: Int? = nil,
        output: String? = nil,
        workingDirectory: String? = nil,
        isAIGenerated: Bool = false
    ) async {
        var details: [String: String] = [
            "command": command,
            "isAIGenerated": String(isAIGenerated)
        ]
        
        if let exitCode = exitCode {
            details["exitCode"] = String(exitCode)
            details["success"] = exitCode == 0 ? "true" : "false"
        
        if let output = output, config.includeDetailedInfo {
            // Truncate long outputs
            let maxOutputLength = 1000
            if output.count > maxOutputLength {
                details["output"] = output.prefix(maxOutputLength) + "... [truncated]"
            } else {
                details["output"] = output
            }
        }
        
        if let workingDirectory = workingDirectory {
            details["workingDirectory"] = workingDirectory
        }
        
        // Determine severity based on exit code and whether the command is high-risk
        let severity: Severity
        if let exitCode = exitCode, exitCode != 0 {
            severity = .warning
        } else if isHighRiskCommand(command) {
            severity = .warning
        } else {
            severity = .info
        }
        
        // Log the event
        await logEvent(
            category: .command,
            event: isAIGenerated ? "ai_command_executed" : "user_command_executed",
            message: "Command executed: \(command)",
            severity: severity,
            details: details
        )
    }
    
    /// Logs an AI-related event
    /// - Parameters:
    ///   - event: Event type
    ///   - message: Human-readable message
    ///   - model: AI model used
    ///   - mode: AI mode
    ///   - input: User input
    ///   - response: AI response
    ///   - severity: Event severity
    public func logAIEvent(
        event: String,
        message: String,
        model: String? = nil,
        mode: String? = nil,
        input: String? = nil,
        response: String? = nil,
        severity: Severity = .info
    ) async {
        var details: [String: String] = [:]
        
        if let model = model {
            details["model"] = model
        }
        
        if let mode = mode {
            details["mode"] = mode
        }
        
        if let input = input, config.includeDetailedInfo {
            // Truncate long inputs
            let maxInputLength = 500
            if input.count > maxInputLength {
                details["input"] = input.prefix(maxInputLength) + "... [truncated]"
            } else {
                details["input"] = input
            }
        }
        
        if let response = response, config.includeDetailedInfo {
            // Truncate long responses
            let maxResponseLength = 1000
            if response.count > maxResponseLength {
                details["response"] = response.prefix(maxResponseLength) + "... [truncated]"
            } else {
                details["response"] = response
            }
        }
        
        // Log the event
        await logEvent(
            category: .ai,
            event: event,
            message: message,
            severity: severity,
            details: details
        )
    }
    
    /// Logs a security event
    /// - Parameters:
    ///   - event: Event type
    ///   - message: Human-readable message
    ///   - severity: Event severity
    ///   - details: Additional details
    public func logSecurityEvent(
        event: String,
        message: String,
        severity: Severity = .warning,
        details: [String: String]? = nil
    ) async {
        await logEvent(
            category: .security,
            event: event,
            message: message,
            severity: severity,
            details: details
        )
    }
    
    /// Logs an error
    /// - Parameters:
    ///   - error: The error
    ///   - context: Context in which the error occurred
    ///   - details: Additional details
    public func logError(
        _ error: Error,
        context: String,
        details: [String: String]? = nil
    ) async {
        var errorDetails = details ?? [:]
        errorDetails["errorDescription"] = error.localizedDescription
        errorDetails["context"] = context
        
        if let nsError = error as NSError {
            errorDetails["domain"] = nsError.domain
            errorDetails["code"] = String(nsError.code)
        }
        
        await logEvent(
            category: .system,
            event: "error",
            message: "Error in \(context): \(error.localizedDescription)",
            severity: .error,
            details: errorDetails
        )
    }
    
    /// Writes a log entry to the current log file
    /// - Parameter entry: Log entry to write
    private func writeEntryToFile(_ entry: LogEntry) async {
        guard let json = entry.asJSON, let jsonData = json.data(using: .utf8) else {
            logger.error("Failed to serialize log entry to JSON")
            return
        }
        
        do {
            // Check log rotation before writing
            await checkLogRotation()
            
            // Append to current log file
            let fileHandle: FileHandle
            
            if FileManager.default.fileExists(atPath: currentLogFile.path) {
                // File exists, open for appending
                fileHandle = try FileHandle(forWritingTo: currentLogFile)
                fileHandle.seekToEndOfFile()
            } else {
                // File doesn't exist, create it
                try jsonData.write(to: currentLogFile, options: .atomic)
                return
            }
            
            // Write JSON data and newline
            fileHandle.write(jsonData)
            fileHandle.write("\n".data(using: .utf8)!)
            fileHandle.closeFile()
        } catch {
            logger.error("Failed to write log entry: \(error.localizedDescription)")
        }
    }
    
    /// Checks if a command is high-risk
    /// - Parameter command: Command to check
    /// - Returns: Whether the command is high-risk
    private func isHighRiskCommand(_ command: String) -> Bool {
        let highRiskPatterns = [
            "rm -", "rmdir", "mv", "dd", "sudo",
            "format", "mkfs", "> /", "chmod", "chown"
        ]
        
        for pattern in highRiskPatterns {
            if command.contains(pattern) {
                return true
            }
        }
        
        return false
    }
    
    /// Checks if log rotation is needed and performs rotation
    private func checkLogRotation() async {
        do {
            let fileManager = FileManager.default
            
            // Check if current log file exists and its size
            if fileManager.fileExists(atPath: currentLogFile.path) {
                let attributes = try fileManager.attributesOfItem(atPath: currentLogFile.path)
                if let fileSize = attributes[.size] as? UInt64, fileSize > config.maxLogFileSize {
                    // Rotate log file
                    await rotateLogFile()
                }
            }
            
            // Check total number of log files
            let logFiles = try fileManager.contentsOfDirectory(at: config.logDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "log" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            
            // If we have too many log files, delete the oldest ones
            if logFiles.count > config.maxLogFiles {
                for file in logFiles.suffix(from: config.maxLogFiles) {
                    try fileManager.removeItem(at: file)
                    logger.info("Removed old log file: \(file.lastPathComponent)")
                }
            }
        } catch {
            logger.error("Error during log rotation: \(error.localizedDescription)")
        }
    }
    
    /// Rotates the current log file
    private func rotateLogFile() async {
        // Create a new log file with timestamp
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "T", with: "_")
        
        let rotatedFile = config.logDirectory.appendingPathComponent("security-\(timestamp).log")
        
        do {
            // Rename current log file
            if FileManager.default.fileExists(atPath: currentLogFile.path) {
                try FileManager.default.moveItem(at: currentLogFile, to: rotatedFile)
                logger.info("Rotated log file to: \(rotatedFile.lastPathComponent)")
            }
            
            // Create new log file
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: Date())
            currentLogFile = config.logDirectory.appendingPathComponent("security-\(dateString).log")
            
            // Log rotation event
            await logEvent(
                category: .system,
                event: "log_rotation",
                message: "Log file rotated",
                severity: .info,
                details: ["rotatedFile": rotatedFile.lastPathComponent]
            )
        } catch {
            logger.error("Failed to rotate log file: \(error.localizedDescription)")
        }
    }
    
    /// Analyzes security logs for patterns and anomalies
    /// - Parameters:
    ///   - timeWindow: Time window to analyze (in hours)
    ///   - categories: Categories to include in analysis
    /// - Returns: Analysis results
    public func analyzeSecurityLogs(
        timeWindow: Int = 24,
        categories: [Category]? = nil
    ) async -> [String: Any] {
        var results: [String: Any] = [:]
        
        // Calculate the start time for our analysis window
        let startTime = Calendar.current.date(
            byAdding: .hour,
            value: -timeWindow,
            to: Date()
        ) ?? Date().addingTimeInterval(-Double(timeWindow) * 3600)
        
        do {
            // Load log entries
            let entries = try await loadLogEntries(since: startTime, categories: categories)
            
            // Basic statistics
            results["totalEvents"] = entries.count
            
            // Events by category
            let eventsByCategory = Dictionary(grouping: entries) { $0.category }
                .mapValues { $0.count }
            results["eventsByCategory"] = eventsByCategory
            
            // Events by severity
            let eventsBySeverity = Dictionary(grouping: entries) { $0.severity.rawValue }
                .mapValues { $0.count }
            results["eventsBySeverity"] = eventsBySeverity
            
            // Command statistics (if command category present)
            if let commandEntries = eventsByCategory["command"], commandEntries > 0 {
                // Filter command entries
                let commandLogs = entries.filter { $0.category == "command" }
                
                // Count AI-generated vs user commands
                let aiGeneratedCommands = commandLogs.filter { entry in
                    guard let details = entry.details,
                          let isAIGenerated = details["isAIGenerated"],
                          isAIGenerated == "true" else {
                        return false
                    }
                    return true
                }
                
                results["aiGeneratedCommands"] = aiGeneratedCommands.count
                results["userCommands"] = commandLogs.count - aiGeneratedCommands.count
                
                // Command success rate
                let successfulCommands = commandLogs.filter { entry in
                    guard let details = entry.details,
                          let success = details["success"],
                          success == "true" else {
                        return false
                    }
                    return true
                }
                
                if !commandLogs.isEmpty {
                    results["commandSuccessRate"] = Double(successfulCommands.count) / Double(commandLogs.count)
                }
            }
            
            // AI statistics (if AI category present)
            if let aiEntries = eventsByCategory["ai"], aiEntries > 0 {
                // Filter AI entries
                let aiLogs = entries.filter { $0.category == "ai" }
                
                // Group by AI mode
                let aiModeUsage = aiLogs.compactMap { entry in
                    entry.details?["aiMode"]
                }.reduce(into: [:]) { counts, mode in
                    counts[mode, default: 0] += 1
                }
                
                results["aiModeUsage"] = aiModeUsage
                
                // Group by model
                let modelUsage = aiLogs.compactMap { entry in
                    entry.details?["model"]
                }.reduce(into: [:]) { counts, model in
                    counts[model, default: 0] += 1
                }
                
                results["modelUsage"] = modelUsage
            }
            
            // Security anomalies
            var anomalies: [[String: Any]] = []
            
            // Check for high error rates
            let errorEntries = entries.filter { $0.severity == .error || $0.severity == .critical }
            if Double(errorEntries.count) / Double(max(1, entries.count)) > 0.1 {
                // More than 10% errors is suspicious
                anomalies.append([
                    "type": "high_error_rate",
                    "count": errorEntries.count,
                    "percentage": Double(errorEntries.count) / Double(max(1, entries.count))
                ])
            }
            
            // Check for unusual command patterns
            if let commandEntries = eventsByCategory["command"], commandEntries > 0 {
                let commandLogs = entries.filter { $0.category == "command" }
                
                // Check for high frequency of high-risk commands
                let highRiskCommands = commandLogs.filter { entry in
                    guard let details = entry.details,
                          let command = details["command"] else {
                        return false
                    }
                    return isHighRiskCommand(command)
                }
                
                if Double(highRiskCommands.count) / Double(max(1, commandLogs.count)) > 0.2 {
                    // More than 20% high-risk commands is suspicious
                    anomalies.append([
                        "type": "high_risk_command_frequency",
                        "count": highRiskCommands.count,
                        "percentage": Double(highRiskCommands.count) / Double(max(1, commandLogs.count))
                    ])
                }
                
                // Check for commands with unusual execution times
                let failedCommands = commandLogs.filter { entry in
                    guard let details = entry.details,
                          let success = details["success"],
                          success == "false" else {
                        return false
                    }
                    return true
                }
                
                if Double(failedCommands.count) / Double(max(1, commandLogs.count)) > 0.3 {
                    // More than 30% failed commands is unusual
                    anomalies.append([
                        "type": "high_command_failure_rate",
                        "count": failedCommands.count,
                        "percentage": Double(failedCommands.count) / Double(max(1, commandLogs.count))
                    ])
                }
            }
            
            // Check for unusual AI usage patterns
            if let aiEntries = eventsByCategory["ai"], aiEntries > 0 {
                let aiLogs = entries.filter { $0.category == "ai" }
                
                // Check for high frequency of AI-generated commands
                if let aiGeneratedCount = results["aiGeneratedCommands"] as? Int,
                   let commandCount = eventsByCategory["command"],
                   commandCount > 0,
                   Double(aiGeneratedCount) / Double(commandCount) > 0.8 {
                    // More than 80% AI-generated commands could indicate automation misuse
                    anomalies.append([
                        "type": "high_ai_command_generation",
                        "count": aiGeneratedCount,
                        "percentage": Double(aiGeneratedCount) / Double(commandCount)
                    ])
                }
            }
            
            // Add anomalies to results
            results["anomalies"] = anomalies
            results["anomalyCount"] = anomalies.count
            results["hasAnomalies"] = !anomalies.isEmpty
            
            // Add time window information
            results["analysisTimeWindow"] = [
                "hours": timeWindow,
                "startTime": ISO8601DateFormatter().string(from: startTime),
                "endTime": ISO8601DateFormatter().string(from: Date())
            ]
            
        } catch {
            logger.error("Failed to analyze security logs: \(error.localizedDescription)")
            results["error"] = error.localizedDescription
        }
        
        return results
    }
    
    /// Loads log entries from the log files
    /// - Parameters:
    ///   - since: Starting time for entries
    ///   - categories: Categories to include
    /// - Returns: Array of log entries
    private func loadLogEntries(
        since: Date,
        categories: [Category]?
    ) async throws -> [LogEntry] {
        let fileManager = FileManager.default
        var entries: [LogEntry] = []
        
        // Get all log files
        let logFiles = try fileManager.contentsOfDirectory(at: config.logDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        
        // Process each log file
        for logFile in logFiles {
            guard let data = try? Data(contentsOf: logFile) else { continue }
            guard let contents = String(data: data, encoding: .utf8) else { continue }
            
            // Process each line of the log file
            let lines = contents.components(separatedBy: .newlines)
            for line in lines where !line.isEmpty {
                guard let data = line.data(using: .utf8),
                      let entry = try? JSONDecoder().decode(LogEntry.self, from: data),
                      entry.timestamp >= since else {
                    continue
                }
                
                // Filter by category if specified
                if let categories = categories, !categories.isEmpty {
                    let categoryStrings = categories.map { $0.rawValue }
                    guard categoryStrings.contains(entry.category) else { continue }
                }
                
                entries.append(entry)
                if Double(highRiskCommands.count) / Double(max(1, commandLogs.count)) > 0.2 {
                    anomalies.append([
                        "type": "high_risk_command_frequency",
                        "count": highRiskCommands.count,
                        "percentage": Double(highRiskCommands.count) / Double(max(1, commandLogs.count))
                    ])
                }
    }
    
    /// Logs an entry to the system log
    /// - Parameter entry: Log entry
    private func logToSystem(_ entry: LogEntry) {
        let logType = severityToLogType[entry.severity] ?? .default
        logger.log(level: logType, "\(entry.message)")
    }
}
