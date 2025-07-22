import Foundation
import OSLog

/// Handles reading and parsing Claude Code JSONL files
class JSONLParser {
    private let decoder = JSONDecoder()
    
    init() {
        // Configure date decoding strategy
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                if let date = ISO8601DateFormatter().date(from: string) {
                    return date
                }
            }
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: timestamp)
            }
            return Date()
        }
    }
    
    /// Parse a JSONL file and return valid usage entries
    func parseJSONLFile(at url: URL) throws -> [UsageEntry] {
        Logger.parser.debug("📖 Reading JSONL file: \(url.lastPathComponent)")
        let content = try String(contentsOf: url, encoding: .utf8)
        let entries = parseJSONLContent(content)
        Logger.parser.logDataProcessing("JSONL parsing", count: entries.count)
        return entries
    }
    
    /// Parse JSONL content string and return valid usage entries
    func parseJSONLContent(_ content: String) -> [UsageEntry] {
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var entries: [UsageEntry] = []
        
        for (lineNumber, line) in lines.enumerated() {
            if let entry = parseJSONLine(line, lineNumber: lineNumber + 1) {
                entries.append(entry)
            }
        }
        
        return entries
    }
    
    /// Parse a single JSON line, handling malformed data gracefully
    private func parseJSONLine(_ line: String, lineNumber: Int) -> UsageEntry? {
        guard let data = line.data(using: .utf8) else {
            logParsingError("Invalid UTF-8 encoding", lineNumber: lineNumber, line: line)
            return nil
        }
        
        do {
            let entry = try decoder.decode(UsageEntry.self, from: data)
            return entry
        } catch let DecodingError.keyNotFound(key, context) {
            logParsingError("Missing required key '\(key.stringValue)': \(context.debugDescription)", 
                          lineNumber: lineNumber, line: line)
            return nil
        } catch let DecodingError.typeMismatch(type, context) {
            logParsingError("Type mismatch for \(type): \(context.debugDescription)", 
                          lineNumber: lineNumber, line: line)
            return nil
        } catch let DecodingError.valueNotFound(type, context) {
            logParsingError("Value not found for \(type): \(context.debugDescription)", 
                          lineNumber: lineNumber, line: line)
            return nil
        } catch let DecodingError.dataCorrupted(context) {
            logParsingError("Data corrupted: \(context.debugDescription)", 
                          lineNumber: lineNumber, line: line)
            return nil
        } catch {
            logParsingError("Unknown parsing error: \(error.localizedDescription)", 
                          lineNumber: lineNumber, line: line)
            return nil
        }
    }
    
    /// Log parsing errors for debugging
    private func logParsingError(_ message: String, lineNumber: Int, line: String) {
        let truncatedLine = line.count > 100 ? String(line.prefix(100)) + "..." : line
        Logger.parser.error("⚠️ JSONL Parse Error (line \(lineNumber)): \(message)")
        Logger.parser.debug("   Line content: \(truncatedLine, privacy: .private)")
    }
    
    /// Discover Claude config directories on the system
    /// - Parameter accessManager: Optional access manager for secured directory access
    /// - Returns: Array of accessible Claude config directory URLs
    static func findClaudeConfigDirectories(accessManager: HomeDirectoryAccessManager? = nil) -> [URL] {
        Logger.parser.debug("🔍 Searching for Claude config directories")
        var directories: [URL] = []
        let fileManager = FileManager.default
        
        // Get the base directory for searching
        let baseDirectory: URL
        if let accessManager = accessManager, let securedURL = accessManager.getSecuredHomeDirectoryURL() {
            baseDirectory = securedURL
            Logger.parser.debug("🔒 Using secured access to search from: \(securedURL.path, privacy: .private)")
        } else {
            baseDirectory = fileManager.homeDirectoryForCurrentUser
            Logger.parser.debug("🏠 Using standard home directory access")
        }
        
        // Standard locations relative to the base directory
        let claudeDir = baseDirectory.appendingPathComponent(".claude/projects")
        let configClaudeDir = baseDirectory.appendingPathComponent(".config/claude/projects")
        
        // Check if directories exist and are accessible
        if isDirectoryAccessible(claudeDir, accessManager: accessManager) {
            Logger.parser.debug("📁 Found standard Claude directory: \(claudeDir.path, privacy: .private)")
            directories.append(claudeDir)
        }
        
        if isDirectoryAccessible(configClaudeDir, accessManager: accessManager) {
            Logger.parser.debug("📁 Found config Claude directory: \(configClaudeDir.path, privacy: .private)")
            directories.append(configClaudeDir)
        }
        
        // Custom directory from environment variable
        if let customPath = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            let customURL = URL(fileURLWithPath: customPath)
            if isDirectoryAccessible(customURL, accessManager: accessManager) {
                Logger.parser.debug("📁 Found custom Claude directory from env: \(customURL.path, privacy: .private)")
                directories.append(customURL)
            }
        }
        
        Logger.parser.info("📁 Found \(directories.count) Claude config directories")
        return directories
    }
    
    /// Check if a directory is accessible, handling both secured and standard access
    private static func isDirectoryAccessible(_ directory: URL, accessManager: HomeDirectoryAccessManager?) -> Bool {
        let fileManager = FileManager.default
        
        // Check basic existence first
        guard fileManager.fileExists(atPath: directory.path) else {
            return false
        }
        
        // If we have an access manager, verify we can access this path
        if let accessManager = accessManager {
            return accessManager.canAccess(path: directory.path)
        }
        
        // For non-secured access, just check if it exists and is readable
        return fileManager.isReadableFile(atPath: directory.path)
    }
    
    /// Recursively discover all JSONL files in given directories
    static func discoverJSONLFiles(in directories: [URL]) -> [URL] {
        Logger.parser.debug("🔍 Discovering JSONL files in \(directories.count) directories")
        let fileManager = FileManager.default
        var jsonlFiles: [URL] = []
        
        for directory in directories {
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles],
                errorHandler: { (url, error) in
                    Logger.parser.error("⚠️ Error accessing \(url.path, privacy: .private): \(error.localizedDescription)")
                    return true
                }
            ) else {
                Logger.parser.error("❌ Could not create enumerator for directory: \(directory.path, privacy: .private)")
                continue
            }
            
            for case let fileURL as URL in enumerator {
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                    if resourceValues.isRegularFile == true && fileURL.pathExtension == "jsonl" {
                        jsonlFiles.append(fileURL)
                        Logger.parser.debug("📄 Found JSONL file: \(fileURL.lastPathComponent)")
                    }
                } catch {
                    Logger.parser.error("⚠️ Error checking file \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        
        Logger.parser.info("📄 Discovered \(jsonlFiles.count) JSONL files")
        return jsonlFiles.sorted { $0.path < $1.path }
    }
}