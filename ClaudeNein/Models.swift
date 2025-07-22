import Foundation

// MARK: - Core Data Models

// MARK: - Claude Session Log Models

/// Base protocol for all Claude log entries
protocol ClaudeLogEntry: Codable {
    var type: String { get }
    var timestamp: Date? { get }
}

/// Summary entry from Claude logs
struct ClaudeSummaryEntry: ClaudeLogEntry {
    let type: String
    let summary: String
    let leafUuid: String
    let timestamp: Date?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        summary = try container.decode(String.self, forKey: .summary)
        leafUuid = try container.decode(String.self, forKey: .leafUuid)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
            .flatMap { timestampString in
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return formatter.date(from: timestampString) ?? ISO8601DateFormatter().date(from: timestampString)
            }
    }
    
    enum CodingKeys: String, CodingKey {
        case type, summary, leafUuid, timestamp
    }
}

/// User message entry from Claude logs
struct ClaudeUserEntry: ClaudeLogEntry {
    let type: String
    let uuid: String
    let timestamp: Date?
    let sessionId: String?
    let version: String?
    let cwd: String?
    let gitBranch: String?
    let parentUuid: String?
    let isSidechain: Bool?
    let userType: String?
    let isMeta: Bool?
    let message: ClaudeMessage?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        uuid = try container.decode(String.self, forKey: .uuid)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        gitBranch = try container.decodeIfPresent(String.self, forKey: .gitBranch)
        parentUuid = try container.decodeIfPresent(String.self, forKey: .parentUuid)
        isSidechain = try container.decodeIfPresent(Bool.self, forKey: .isSidechain)
        userType = try container.decodeIfPresent(String.self, forKey: .userType)
        isMeta = try container.decodeIfPresent(Bool.self, forKey: .isMeta)
        message = try container.decodeIfPresent(ClaudeMessage.self, forKey: .message)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
            .flatMap { timestampString in
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return formatter.date(from: timestampString) ?? ISO8601DateFormatter().date(from: timestampString)
            }
    }
    
    enum CodingKeys: String, CodingKey {
        case type, uuid, timestamp, sessionId, version, cwd, gitBranch
        case parentUuid, isSidechain, userType, isMeta, message
    }
}

/// Message content within Claude entries
struct ClaudeMessage: Codable {
    let role: String?
    let content: String?
    let model: String?
    let usage: ClaudeUsage?
    
    enum CodingKeys: String, CodingKey {
        case role, content, model, usage
    }
}

/// Usage information from Claude API responses
struct ClaudeUsage: Codable {
    let inputTokens: Int?
    let outputTokens: Int? 
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }
    
    /// Convert to TokenCounts format expected by the app
    var asTokenCounts: TokenCounts? {
        guard let input = inputTokens, let output = outputTokens else { return nil }
        let cached = (cacheCreationInputTokens ?? 0) + (cacheReadInputTokens ?? 0)
        return TokenCounts(
            input: input,
            output: output, 
            cached: cached > 0 ? cached : nil
        )
    }
}

/// Assistant response entry from Claude logs  
struct ClaudeAssistantEntry: ClaudeLogEntry {
    let type: String
    let uuid: String
    let timestamp: Date?
    let sessionId: String?
    let parentUuid: String?
    let message: ClaudeMessage?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        uuid = try container.decode(String.self, forKey: .uuid)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        parentUuid = try container.decodeIfPresent(String.self, forKey: .parentUuid)
        message = try container.decodeIfPresent(ClaudeMessage.self, forKey: .message)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
            .flatMap { timestampString in
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return formatter.date(from: timestampString) ?? ISO8601DateFormatter().date(from: timestampString)
            }
    }
    
    enum CodingKeys: String, CodingKey {
        case type, uuid, timestamp, sessionId, parentUuid, message
    }
}

/// Cost calculation mode for usage entries
enum CostMode {
    case auto      // Use costUSD when available, calculate otherwise
    case calculate // Always calculate from tokens, ignore costUSD
    case display   // Always use costUSD, even if undefined (shows 0)
}

/// Represents a single usage entry from Claude Code JSONL files
struct UsageEntry: Codable, Equatable, Hashable {
    let id: String
    let timestamp: Date
    let model: String
    let tokenCounts: TokenCounts
    let cost: Double?
    let sessionId: String?
    let projectPath: String?
    let requestId: String?  // For deduplication
    let messageId: String?  // For deduplication
    
    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case model
        case tokenCounts = "token_counts"
        case cost = "costUSD"
        case sessionId = "session_id"
        case projectPath = "project_path"
        case requestId = "requestId"
        case messageId
    }
    
    // Regular memberwise initializer for testing and direct creation
    init(id: String, timestamp: Date, model: String, tokenCounts: TokenCounts, cost: Double? = nil, sessionId: String? = nil, projectPath: String? = nil, requestId: String? = nil, messageId: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.model = model
        self.tokenCounts = tokenCounts
        self.cost = cost
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.requestId = requestId
        self.messageId = messageId
    }
    
    /// Generate unique hash for deduplication based on request and message IDs
    func uniqueHash() -> String? {
        guard let requestId = requestId, let messageId = messageId else { return nil }
        return "\(messageId):\(requestId)"
    }
    
    /// Implement Hashable protocol
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(timestamp)
        hasher.combine(model)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        model = try container.decode(String.self, forKey: .model)
        tokenCounts = try container.decode(TokenCounts.self, forKey: .tokenCounts)
        cost = try container.decodeIfPresent(Double.self, forKey: .cost)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        projectPath = try container.decodeIfPresent(String.self, forKey: .projectPath)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
        messageId = try container.decodeIfPresent(String.self, forKey: .messageId)
        
        // Handle various timestamp formats
        if let timestampString = try? container.decode(String.self, forKey: .timestamp) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            timestamp = formatter.date(from: timestampString) ?? ISO8601DateFormatter().date(from: timestampString) ?? Date()
        } else if let timestampDouble = try? container.decode(Double.self, forKey: .timestamp) {
            timestamp = Date(timeIntervalSince1970: timestampDouble)
        } else {
            timestamp = Date()
        }
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

/// Represents a 5-hour billing period with aggregated usage
struct SessionBlock: Equatable {
    let startTime: Date
    let endTime: Date
    let entries: [UsageEntry]
    let totalTokens: TokenCounts
    let totalCost: Double
    
    init(startTime: Date, entries: [UsageEntry]) {
        self.startTime = startTime
        self.endTime = Calendar.current.date(byAdding: .hour, value: 5, to: startTime) ?? startTime
        self.entries = entries
        
        // Aggregate token counts
        let inputSum = entries.reduce(0) { $0 + $1.tokenCounts.input }
        let outputSum = entries.reduce(0) { $0 + $1.tokenCounts.output }
        let cacheCreationSum = entries.reduce(0) { $0 + ($1.tokenCounts.cacheCreation ?? 0) }
        let cacheReadSum = entries.reduce(0) { $0 + ($1.tokenCounts.cacheRead ?? 0) }
        
        self.totalTokens = TokenCounts(
            input: inputSum,
            output: outputSum,
            cacheCreation: cacheCreationSum > 0 ? cacheCreationSum : nil,
            cacheRead: cacheReadSum > 0 ? cacheReadSum : nil
        )
        
        // Aggregate costs
        self.totalCost = entries.compactMap { $0.cost }.reduce(0, +)
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