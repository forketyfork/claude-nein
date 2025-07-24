import Foundation

// MARK: - Core Data Models

/// Cost calculation mode for usage entries
enum CostMode {
    case auto      // Use costUSD when available, calculate otherwise
    case calculate // Always calculate from tokens, ignore costUSD
    case display   // Always use costUSD, even if undefined (shows 0)
}

/// Represents a single usage entry from Claude Code JSONL files
struct UsageEntry: Codable, Equatable, Hashable {
    let id: String // Unique ID for Core Data, always UUID
    let timestamp: Date
    let model: String
    let tokenCounts: TokenCounts
    let cost: Double?
    let sessionId: String?
    let projectPath: String?
    let requestId: String?
    let originalMessageId: String? // The original messageId from the JSONL for deduplication
    
    enum CodingKeys: String, CodingKey {
        case timestamp
        case model
        case tokenCounts = "token_counts"
        case cost = "costUSD"
        case sessionId = "sessionId"
        case projectPath = "project_path"
        case requestId = "requestId"
        case originalMessageId = "messageId" // Map messageId from JSONL to originalMessageId
        case message // For nested structure
        case type // For filtering entry types
    }
    
    // Regular memberwise initializer for testing and direct creation
    init(id: String = UUID().uuidString, timestamp: Date, model: String, tokenCounts: TokenCounts, cost: Double? = nil, sessionId: String? = nil, projectPath: String? = nil, requestId: String? = nil, originalMessageId: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.model = model
        self.tokenCounts = tokenCounts
        self.cost = cost
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.requestId = requestId
        self.originalMessageId = originalMessageId
    }
    
    /// Generate unique hash for deduplication based on available identifiers
    /// Returns nil if we don't have both requestId and originalMessageId for reliable deduplication
    func uniqueHash() -> String? {
        // Only use requestId and originalMessageId if both are available for reliable deduplication
        if let requestId = requestId, let originalMessageId = originalMessageId {
            return "\(originalMessageId):\(requestId)"
        }
        
        // Return nil if we don't have both identifiers - entries without both will not be deduplicated
        // This is safer than using fallback hashes that might not be truly unique
        return nil
    }
    
    /// Implement Hashable protocol
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(timestamp)
        hasher.combine(model)
        // Include originalMessageId and requestId in hash for better deduplication
        hasher.combine(originalMessageId)
        hasher.combine(requestId)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Check if this is an assistant entry with usage data - only these should be decoded as UsageEntry
        let entryType = try? container.decode(String.self, forKey: .type)
        guard entryType == "assistant" else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Only assistant entries with usage data can be decoded as UsageEntry")
        }
        
        // Generate a new UUID for the id to ensure uniqueness for Core Data
        id = UUID().uuidString
        
        // Try to get model and usage from nested message structure first, then fall back to flat structure
        if let messageContainer = try? container.nestedContainer(keyedBy: MessageCodingKeys.self, forKey: .message),
           messageContainer.contains(.model), messageContainer.contains(.usage) {
            // Extract from nested message structure
            model = try messageContainer.decode(String.self, forKey: .model)
            let usage = try messageContainer.decode(ClaudeUsage.self, forKey: .usage)
            tokenCounts = TokenCounts(
                input: usage.inputTokens ?? 0,
                output: usage.outputTokens ?? 0,
                cacheCreation: usage.cacheCreationInputTokens,
                cacheRead: usage.cacheReadInputTokens
            )
            originalMessageId = try? messageContainer.decode(String.self, forKey: .originalMessageId)
        } else {
            // Fall back to flat structure
            model = try container.decode(String.self, forKey: .model)
            tokenCounts = try container.decode(TokenCounts.self, forKey: .tokenCounts)
            originalMessageId = try container.decodeIfPresent(String.self, forKey: .originalMessageId)
        }
        
        cost = try container.decodeIfPresent(Double.self, forKey: .cost)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        projectPath = try container.decodeIfPresent(String.self, forKey: .projectPath)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
        
        // Handle various timestamp formats
        if let timestampString = try? container.decode(String.self, forKey: .timestamp) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            timestamp = formatter.date(from: timestampString) ?? ISO8601DateFormatter().date(from: timestampString) ?? Date()
        } else if let timestampDouble = try? container.decode(Double.self, forKey: .timestamp) {
            timestamp = Date(timeIntervalSince1970: timestampDouble)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .timestamp, in: container, debugDescription: "Timestamp is not in a recognized format.")
        }
    }
    
    private enum MessageCodingKeys: String, CodingKey {
        case model, usage
        case originalMessageId = "id"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(model, forKey: .model)
        try container.encode(tokenCounts, forKey: .tokenCounts)
        try container.encodeIfPresent(cost, forKey: .cost)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
        try container.encodeIfPresent(projectPath, forKey: .projectPath)
        try container.encodeIfPresent(requestId, forKey: .requestId)
        try container.encodeIfPresent(originalMessageId, forKey: .originalMessageId)
    }
}

/// Represents token counts for input, output, and cached tokens
struct TokenCounts: Codable, Equatable {
    let input: Int
    let output: Int
    let cacheCreation: Int?
    let cacheRead: Int?
    
    enum CodingKeys: String, CodingKey {
        case input = "input_tokens"
        case output = "output_tokens"
        case cacheCreation = "cache_creation_tokens"
        case cacheRead = "cache_read_tokens"
    }
    
    /// Total cached tokens (creation + read)
    var cached: Int? {
        guard cacheCreation != nil || cacheRead != nil else { return nil }
        return (cacheCreation ?? 0) + (cacheRead ?? 0)
    }
    
    /// Total tokens including all types
    var total: Int {
        return input + output + (cached ?? 0)
    }
    
    init(input: Int, output: Int, cacheCreation: Int? = nil, cacheRead: Int? = nil) {
        self.input = input
        self.output = output
        self.cacheCreation = cacheCreation
        self.cacheRead = cacheRead
    }
    
    /// Legacy convenience initializer for backward compatibility
    init(input: Int, output: Int, cached: Int? = nil) {
        self.input = input
        self.output = output
        self.cacheCreation = cached
        self.cacheRead = nil
    }
}

/// Summary data structure for UI display
struct SpendSummary: Equatable {
    let todaySpend: Double
    let weekSpend: Double
    let monthSpend: Double
    let lastUpdated: Date
    let modelBreakdown: [String: Double]
    
    init(todaySpend: Double = 0.0, 
         weekSpend: Double = 0.0, 
         monthSpend: Double = 0.0, 
         lastUpdated: Date = Date(), 
         modelBreakdown: [String: Double] = [:]) {
        self.todaySpend = todaySpend
        self.weekSpend = weekSpend
        self.monthSpend = monthSpend
        self.lastUpdated = lastUpdated
        self.modelBreakdown = modelBreakdown
    }
    
    static let empty = SpendSummary()
}