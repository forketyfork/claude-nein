import OSLog
import Foundation

/// Centralized logging configuration for ClaudeNein
/// Uses Apple's unified logging system with structured categories
extension Logger {
    
    // MARK: - Subsystem
    
    /// The subsystem identifier for all ClaudeNein logging
    private static var subsystem: String {
        Bundle.main.bundleIdentifier ?? "com.forketyfork.ClaudeNein"
    }
    
    // MARK: - Category Loggers
    
    /// General application lifecycle and main flow
    static let app = Logger(subsystem: subsystem, category: "app")
    
    /// Menu bar operations and UI updates
    static let menuBar = Logger(subsystem: subsystem, category: "menubar")
    
    /// File system monitoring and changes
    static let fileMonitor = Logger(subsystem: subsystem, category: "filemonitor")
    
    /// JSONL parsing operations
    static let parser = Logger(subsystem: subsystem, category: "parser")
    
    /// Spending calculations and data processing
    static let calculator = Logger(subsystem: subsystem, category: "calculator")
    
    /// Performance monitoring and timing
    static let performance = Logger(subsystem: subsystem, category: "performance")
    
    /// Security and privacy related operations
    static let security = Logger(subsystem: subsystem, category: "security")
    
    /// Network operations (if any)
    static let network = Logger(subsystem: subsystem, category: "network")
}

/// Logging utility functions for common patterns
enum LogLevel {
    case debug, info, notice, error, fault
}

/// Helper extension for common logging patterns
extension Logger {
    
    /// Log with timing information
    func logTiming<T>(_ message: String, operation: () throws -> T) rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
            self.info("⏱️ \(message) completed in \(String(format: "%.3f", timeElapsed))s")
        }
        self.debug("🚀 Starting: \(message)")
        return try operation()
    }
    
    /// Log file operations with privacy
    func logFileOperation(_ operation: String, path: String, success: Bool = true) {
        if success {
            self.info("📁 \(operation): \(path, privacy: .private)")
        } else {
            self.error("❌ Failed \(operation): \(path, privacy: .private)")
        }
    }
    
    /// Log errors with context
    func logError(_ error: Error, context: String) {
        if let localizedError = error as? LocalizedError {
            self.error("💥 \(context): \(localizedError.errorDescription ?? error.localizedDescription)")
        } else {
            self.error("💥 \(context): \(error.localizedDescription)")
        }
    }
    
    /// Log data processing with counts
    func logDataProcessing(_ operation: String, count: Int) {
        self.info("📊 \(operation): processed \(count) items")
    }
    
    /// Log memory usage warnings
    func logMemoryWarning(_ context: String) {
        self.notice("⚠️ Memory warning in \(context)")
    }
    
    /// Log privacy-sensitive operations
    func logPrivacyOperation(_ operation: String, details: String? = nil) {
        if let details = details {
            self.info("🔒 Privacy: \(operation) - \(details, privacy: .private)")
        } else {
            self.info("🔒 Privacy: \(operation)")
        }
    }
}