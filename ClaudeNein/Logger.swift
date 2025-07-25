import OSLog
import Foundation

/// Centralized logging configuration for ClaudeNein
extension Logger {
    // MARK: - Subsystem
    private static var subsystem: String {
        Bundle.main.bundleIdentifier ?? "com.forketyfork.ClaudeNein"
    }

    // MARK: - Category Loggers
    static let app = Logger(subsystem: subsystem, category: "app")
    static let menuBar = Logger(subsystem: subsystem, category: "menubar")
    static let fileMonitor = Logger(subsystem: subsystem, category: "filemonitor")
    static let parser = Logger(subsystem: subsystem, category: "parser")
    static let dataStore = Logger(subsystem: subsystem, category: "datastore")
    static let calculator = Logger(subsystem: subsystem, category: "calculator")
    static let performance = Logger(subsystem: subsystem, category: "performance")
    static let security = Logger(subsystem: subsystem, category: "security")
    static let network = Logger(subsystem: subsystem, category: "network")
}

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

    /// Log data processing with counts
    func logDataProcessing(_ operation: String, count: Int) {
        self.info("📊 \(operation): processed \(count) items")
    }
}
