import Foundation

// MARK: - Core Data Models

/// Represents a single usage entry from Claude Code JSONL files
struct UsageEntry: Codable, Equatable {
    let id: String
    let timestamp: Date
    let model: String
    let tokenCounts: TokenCounts
    let cost: Double?
    let sessionId: String?
    let projectPath: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case model
        case tokenCounts = "token_counts"
        case cost
        case sessionId = "session_id"
        case projectPath = "project_path"
    }
    
    // Regular memberwise initializer for testing and direct creation
    init(id: String, timestamp: Date, model: String, tokenCounts: TokenCounts, cost: Double? = nil, sessionId: String? = nil, projectPath: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.model = model
        self.tokenCounts = tokenCounts
        self.cost = cost
        self.sessionId = sessionId
        self.projectPath = projectPath
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        model = try container.decode(String.self, forKey: .model)
        tokenCounts = try container.decode(TokenCounts.self, forKey: .tokenCounts)
        cost = try container.decodeIfPresent(Double.self, forKey: .cost)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        projectPath = try container.decodeIfPresent(String.self, forKey: .projectPath)
        
        // Handle various timestamp formats
        if let timestampString = try? container.decode(String.self, forKey: .timestamp) {
            timestamp = ISO8601DateFormatter().date(from: timestampString) ?? Date()
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
    let cached: Int?
    
    enum CodingKeys: String, CodingKey {
        case input = "input_tokens"
        case output = "output_tokens"
        case cached = "cached_tokens"
    }
    
    var total: Int {
        return input + output + (cached ?? 0)
    }
    
    init(input: Int, output: Int, cached: Int? = nil) {
        self.input = input
        self.output = output
        self.cached = cached
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
        let cachedSum = entries.reduce(0) { $0 + ($1.tokenCounts.cached ?? 0) }
        
        self.totalTokens = TokenCounts(
            input: inputSum,
            output: outputSum,
            cached: cachedSum > 0 ? cachedSum : nil
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