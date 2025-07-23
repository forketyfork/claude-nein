import Foundation
import OSLog

/// Handles reading and parsing Claude Code JSONL files with deduplication and comprehensive error handling
class JSONLParser {
    private let decoder = JSONDecoder()
    private var seenHashes = Set<String>()
    
    init() {
        // Configure date decoding strategy
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: string) {
                    return date
                } else if let date = ISO8601DateFormatter().date(from: string) {
                    return date
                }
            }
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: timestamp)
            }
            return Date()
        }
    }
    
    /// Asynchronously parse a single JSONL file.
    func parse(fileURL: URL) async throws -> [UsageEntry] {
        let content = try String(contentsOf: fileURL)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        return lines.compactMap { line -> UsageEntry? in
            guard let data = line.data(using: .utf8) else { return nil }
            
            do {
                // Attempt to decode as a UsageEntry
                return try decoder.decode(UsageEntry.self, from: data)
            } catch {
                // Only log errors for entries that should be decodable (assistant entries)
                // User entries, summary entries, etc. are expected to fail decoding
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let entryType = json["type"] as? String,
                   entryType == "assistant" {
                    Logger.parser.error("Failed to decode assistant entry: \(line) - Error: \(error)")
                }
                return nil
            }
        }
    }
    
    /// Parse a JSONL file and return valid usage entries with deduplication
    func parseJSONLFile(at url: URL, enableDeduplication: Bool = true) throws -> [UsageEntry] {
        Logger.parser.debug("📖 Reading JSONL file: \(url.lastPathComponent)")
        let content = try String(contentsOf: url, encoding: .utf8)
        let entries = parseJSONLContent(content, enableDeduplication: enableDeduplication)
        Logger.parser.logDataProcessing("JSONL parsing", count: entries.count)
        return entries
    }
    
    /// Parse JSONL content string and return valid usage entries with optional deduplication
    func parseJSONLContent(_ content: String, enableDeduplication: Bool = true) -> [UsageEntry] {
        // Split by \n for consistent line parsing across platforms
        let lines = content.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var entries: [UsageEntry] = []
        
        for (lineNumber, line) in lines.enumerated() {
            if let entry = parseJSONLine(line, lineNumber: lineNumber + 1) {
                // Apply deduplication if enabled
                if enableDeduplication, let hash = entry.uniqueHash() {
                    if seenHashes.contains(hash) {
                        Logger.parser.debug("🔄 Skipping duplicate entry with hash: \(hash)")
                        continue
                    }
                    seenHashes.insert(hash)
                }
                entries.append(entry)
            }
        }
        
        return entries
    }
    
    /// Parse a single JSON line, handling malformed data gracefully
    func parseJSONLine(_ line: String, lineNumber: Int) -> UsageEntry? {
        guard let data = line.data(using: .utf8) else {
            return nil
        }
        
        // Parse as JSON and check if this is an assistant entry
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            
            // Only process assistant entries - they contain usage data
            guard let entryType = json["type"] as? String, entryType == "assistant" else {
                return nil
            }
            
            // Check for required fields: model, usage, timestamp
            guard let model = json["model"] as? String ?? (json["message"] as? [String: Any])?["model"] as? String,
                  let usage = json["usage"] as? [String: Any] ?? (json["message"] as? [String: Any])?["usage"] as? [String: Any] else {
                return nil
            }
            
            // Parse timestamp - handle both string and numeric formats
            let timestamp: Date
            if let timestampString = json["timestamp"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                guard let date = formatter.date(from: timestampString) ?? ISO8601DateFormatter().date(from: timestampString) else {
                    return nil
                }
                timestamp = date
            } else if let timestampNumber = json["timestamp"] as? Double {
                timestamp = Date(timeIntervalSince1970: timestampNumber)
            } else {
                return nil
            }
            
            // Extract token counts from usage
            guard let inputTokens = usage["input_tokens"] as? Int,
                  let outputTokens = usage["output_tokens"] as? Int else {
                return nil
            }
            
            // Extract separate cache creation and cache read tokens
            let cacheCreationTokens = usage["cache_creation_input_tokens"] as? Int
            let cacheReadTokens = usage["cache_read_input_tokens"] as? Int
            
            let tokenCounts = TokenCounts(
                input: inputTokens,
                output: outputTokens,
                cacheCreation: cacheCreationTokens,
                cacheRead: cacheReadTokens
            )
            
            // Extract optional fields - handle both nested and flat structures
            let messageId = (json["message"] as? [String: Any])?["id"] as? String ?? json["messageId"] as? String ?? json["id"] as? String
            let requestId = json["requestId"] as? String
            let costUSD = json["costUSD"] as? Double
            
            return UsageEntry(
                timestamp: timestamp,
                model: model,
                tokenCounts: tokenCounts,
                cost: costUSD,
                sessionId: json["sessionId"] as? String,
                projectPath: nil,
                requestId: requestId,
                originalMessageId: messageId
            )
            
        } catch {
            return nil
        }
    }
    
    
    /// Clear deduplication cache
    func clearDeduplicationCache() {
        seenHashes.removeAll()
    }
    
    /// Get earliest timestamp from a JSONL file for chronological sorting
    static func getEarliestTimestamp(from url: URL) -> Date? {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            var earliestDate: Date? = nil
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallbackFormatter = ISO8601DateFormatter()
            
            for line in lines {
                guard let data = line.data(using: .utf8) else { continue }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let timestampString = json["timestamp"] as? String {
                        if let date = formatter.date(from: timestampString) ?? fallbackFormatter.date(from: timestampString) {
                            if earliestDate == nil || date < earliestDate! {
                                earliestDate = date
                            }
                        }
                    }
                } catch {
                    // Skip invalid JSON lines
                    continue
                }
            }
            
            return earliestDate
        } catch {
            Logger.parser.error("⚠️ Error reading file for timestamp: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Sort files by their earliest timestamp for chronological processing
    static func sortFilesByTimestamp(_ files: [URL]) -> [URL] {
        return files.sorted { file1, file2 in
            let timestamp1 = getEarliestTimestamp(from: file1)
            let timestamp2 = getEarliestTimestamp(from: file2)
            
            // Files without timestamps go to the end
            switch (timestamp1, timestamp2) {
            case (.none, .none):
                return file1.path < file2.path // Lexicographic fallback
            case (.none, .some):
                return false // file1 goes after file2
            case (.some, .none):
                return true // file1 goes before file2
            case (.some(let date1), .some(let date2)):
                return date1 < date2
            }
        }
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
        
        if directories.isEmpty {
            Logger.parser.error("❌ No valid Claude data directories found. Expected locations:")
            Logger.parser.error("  - \(baseDirectory.path)/.config/claude/projects")
            Logger.parser.error("  - \(baseDirectory.path)/.claude/projects")
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
    
    /// Recursively discover all JSONL files in given directories with chronological sorting
    static func discoverJSONLFiles(in directories: [URL], sortChronologically: Bool = true) -> [URL] {
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
        
        if sortChronologically {
            Logger.parser.debug("📅 Sorting files chronologically by earliest timestamp")
            return sortFilesByTimestamp(jsonlFiles)
        } else {
            return jsonlFiles.sorted { $0.path < $1.path }
        }
    }
}