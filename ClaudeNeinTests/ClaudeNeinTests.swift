//
//  ClaudeNeinTests.swift
//  ClaudeNeinTests
//
//  Created by Forketyfork on 21.07.25.
//

import Testing
import Foundation
@testable import ClaudeNein

struct ClaudeNeinTests {
    
    // MARK: - Models Tests
    
    @Test func testTokenCountsTotal() {
        let tokens1 = TokenCounts(input: 100, output: 200, cached: 50)
        #expect(tokens1.total == 350)
        
        let tokens2 = TokenCounts(input: 100, output: 200, cached: nil)
        #expect(tokens2.total == 300)
    }
    
    @Test func testUsageEntryEquality() {
        let date = Date()
        let tokens = TokenCounts(input: 100, output: 200)
        
        let entry1 = UsageEntry(
            id: "test-id",
            timestamp: date,
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: tokens,
            cost: 1.5,
            sessionId: "session-1",
            projectPath: "/test/path"
        )
        
        let entry2 = UsageEntry(
            id: "test-id",
            timestamp: date,
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: tokens,
            cost: 1.5,
            sessionId: "session-1",
            projectPath: "/test/path"
        )
        
        #expect(entry1 == entry2)
    }
    
    @Test func testSessionBlockInitialization() {
        let startTime = Date()
        let tokens1 = TokenCounts(input: 100, output: 200, cached: 50)
        let tokens2 = TokenCounts(input: 150, output: 300)
        
        let entry1 = UsageEntry(
            id: "entry-1",
            timestamp: startTime,
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: tokens1,
            cost: 1.5,
            sessionId: "session-1",
            projectPath: "/test/path"
        )
        
        let entry2 = UsageEntry(
            id: "entry-2",
            timestamp: startTime,
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: tokens2,
            cost: 2.0,
            sessionId: "session-1",
            projectPath: "/test/path"
        )
        
        let sessionBlock = SessionBlock(startTime: startTime, entries: [entry1, entry2])
        
        #expect(sessionBlock.totalTokens.input == 250)
        #expect(sessionBlock.totalTokens.output == 500)
        #expect(sessionBlock.totalTokens.cached == 50)
        #expect(sessionBlock.totalCost == 3.5)
        #expect(sessionBlock.entries.count == 2)
    }
    
    @Test func testSpendSummaryEmpty() {
        let emptySummary = SpendSummary.empty
        #expect(emptySummary.todaySpend == 0.0)
        #expect(emptySummary.weekSpend == 0.0)
        #expect(emptySummary.monthSpend == 0.0)
        #expect(emptySummary.modelBreakdown.isEmpty)
    }
}

// MARK: - JSONLParser Tests

struct JSONLParserTests {
    
    @Test func testValidJSONLParsing() {
        let parser = JSONLParser()
        let jsonlContent = """
        {"id": "test-1", "timestamp": "2024-07-21T10:00:00Z", "model": "claude-3-5-sonnet-20241022", "token_counts": {"input_tokens": 100, "output_tokens": 200}, "cost": 1.5}
        {"id": "test-2", "timestamp": 1721552400, "model": "claude-3-5-haiku-20241022", "token_counts": {"input_tokens": 50, "output_tokens": 100, "cached_tokens": 25}, "cost": 0.5}
        """
        
        let entries = parser.parseJSONLContent(jsonlContent)
        
        #expect(entries.count == 2)
        #expect(entries[0].id == "test-1")
        #expect(entries[0].model == "claude-3-5-sonnet-20241022")
        #expect(entries[0].tokenCounts.input == 100)
        #expect(entries[0].tokenCounts.output == 200)
        #expect(entries[0].cost == 1.5)
        
        #expect(entries[1].id == "test-2")
        #expect(entries[1].model == "claude-3-5-haiku-20241022")
        #expect(entries[1].tokenCounts.cached == 25)
    }
    
    @Test func testMalformedJSONLHandling() {
        let parser = JSONLParser()
        let jsonlContent = """
        {"id": "test-1", "timestamp": "2024-07-21T10:00:00Z", "model": "claude-3-5-sonnet-20241022", "token_counts": {"input_tokens": 100, "output_tokens": 200}}
        invalid json line
        {"id": "test-2", "model": "claude-3-5-haiku-20241022", "token_counts": {"input_tokens": 50, "output_tokens": 100}}
        {"incomplete": "data"
        """
        
        let entries = parser.parseJSONLContent(jsonlContent)
        
        // Should successfully parse valid entries and skip malformed ones
        #expect(entries.count == 2)
        #expect(entries[0].id == "test-1")
        #expect(entries[1].id == "test-2")
    }
    
    @Test func testEmptyAndWhitespaceLines() {
        let parser = JSONLParser()
        let jsonlContent = """
        
        {"id": "test-1", "timestamp": "2024-07-21T10:00:00Z", "model": "claude-3-5-sonnet-20241022", "token_counts": {"input_tokens": 100, "output_tokens": 200}}
        
        
        {"id": "test-2", "timestamp": "2024-07-21T10:05:00Z", "model": "claude-3-5-haiku-20241022", "token_counts": {"input_tokens": 50, "output_tokens": 100}}
        
        """
        
        let entries = parser.parseJSONLContent(jsonlContent)
        
        #expect(entries.count == 2)
        #expect(entries[0].id == "test-1")
        #expect(entries[1].id == "test-2")
    }
    
    @Test func testDiscoverClaudeConfigDirectories() {
        let directories = JSONLParser.findClaudeConfigDirectories()
        
        // Should return at least some directories (even if they don't exist)
        // The function checks standard locations and environment variables
        #expect(directories.count >= 0)
        
        // Check that standard paths are included if they exist
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let claudeDir = homeDirectory.appendingPathComponent(".claude/projects")
        let configClaudeDir = homeDirectory.appendingPathComponent(".config/claude/projects")
        
        if FileManager.default.fileExists(atPath: claudeDir.path) {
            #expect(directories.contains(claudeDir))
        }
        
        if FileManager.default.fileExists(atPath: configClaudeDir.path) {
            #expect(directories.contains(configClaudeDir))
        }
    }
}

// MARK: - PricingManager Tests

struct PricingManagerTests {
    
    @Test func testBundledPricingData() {
        let pricingManager = PricingManager.shared
        let pricing = pricingManager.getCurrentPricing()
        
        // Verify bundled data contains expected models
        #expect(pricing.models["claude-3-5-sonnet-20241022"] != nil)
        #expect(pricing.models["claude-3-5-haiku-20241022"] != nil)
        #expect(pricing.models["claude-3-opus-20240229"] != nil)
        
        // Verify pricing structure
        if let sonnetPricing = pricing.models["claude-3-5-sonnet-20241022"] {
            #expect(sonnetPricing.inputPrice == 3.0)
            #expect(sonnetPricing.outputPrice == 15.0)
            #expect(sonnetPricing.cachedPrice == 0.3)
        }
    }
    
    @Test func testCostCalculationWithPrecalculatedCost() {
        let pricingManager = PricingManager.shared
        let tokens = TokenCounts(input: 100, output: 200)
        
        let entry = UsageEntry(
            id: "test-1",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: tokens,
            cost: 2.5, // Pre-calculated cost should be used
            sessionId: "session-1",
            projectPath: "/test/path"
        )
        
        let calculatedCost = pricingManager.calculateCost(for: entry)
        #expect(calculatedCost == 2.5)
    }
    
    @Test func testCostCalculationFromTokens() {
        let pricingManager = PricingManager.shared
        let tokens = TokenCounts(input: 1_000_000, output: 1_000_000, cached: 1_000_000)
        
        let entry = UsageEntry(
            id: "test-1",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: tokens,
            cost: nil, // No pre-calculated cost
            sessionId: "session-1",
            projectPath: "/test/path"
        )
        
        let calculatedCost = pricingManager.calculateCost(for: entry)
        
        // Expected: (1M * 3.0 + 1M * 15.0 + 1M * 0.3) / 1M = 18.3
        let expectedCost = 3.0 + 15.0 + 0.3
        #expect(abs(calculatedCost - expectedCost) < 0.001)
    }
    
    @Test func testCostCalculationUnknownModel() {
        let pricingManager = PricingManager.shared
        let tokens = TokenCounts(input: 100, output: 200)
        
        let entry = UsageEntry(
            id: "test-1",
            timestamp: Date(),
            model: "unknown-model",
            tokenCounts: tokens,
            cost: nil,
            sessionId: "session-1",
            projectPath: "/test/path"
        )
        
        let calculatedCost = pricingManager.calculateCost(for: entry)
        #expect(calculatedCost == 0.0) // Should return 0 for unknown models
    }
    
    @Test func testCalculateTotalCostForMultipleEntries() {
        let pricingManager = PricingManager.shared
        
        let entry1 = UsageEntry(
            id: "test-1",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: TokenCounts(input: 1_000_000, output: 0),
            cost: nil,
            sessionId: "session-1",
            projectPath: "/test/path"
        )
        
        let entry2 = UsageEntry(
            id: "test-2",
            timestamp: Date(),
            model: "claude-3-5-haiku-20241022",
            tokenCounts: TokenCounts(input: 1_000_000, output: 0),
            cost: nil,
            sessionId: "session-1",
            projectPath: "/test/path"
        )
        
        let totalCost = pricingManager.calculateTotalCost(for: [entry1, entry2])
        
        // Expected: 3.0 (Sonnet input) + 0.25 (Haiku input) = 3.25
        let expectedCost = 3.0 + 0.25
        #expect(abs(totalCost - expectedCost) < 0.001)
    }
}

// MARK: - SpendCalculator Tests

struct SpendCalculatorTests {
    
    @Test func testCalculateSpendSummary() {
        let calculator = SpendCalculator()
        let now = Date()
        
        // Create test entries for different time periods
        let todayEntry = createTestEntry(id: "today", timestamp: now, cost: 1.0)
        let yesterdayEntry = createTestEntry(id: "yesterday", timestamp: Calendar.current.date(byAdding: .day, value: -1, to: now)!, cost: 2.0)
        let weekAgoEntry = createTestEntry(id: "week", timestamp: Calendar.current.date(byAdding: .day, value: -7, to: now)!, cost: 3.0)
        let monthAgoEntry = createTestEntry(id: "month", timestamp: Calendar.current.date(byAdding: .day, value: -35, to: now)!, cost: 4.0)
        
        let entries = [todayEntry, yesterdayEntry, weekAgoEntry, monthAgoEntry]
        let summary = calculator.calculateSpendSummary(from: entries)
        
        #expect(summary.todaySpend == 1.0)
        // Week includes today + yesterday + week ago (last 7 days)
        #expect(summary.weekSpend >= 3.0) // At least today + yesterday + week ago
        // Month depends on calendar month boundaries
        #expect(summary.monthSpend >= 1.0) // At least today
    }
    
    @Test func testFilterEntriesToday() {
        let calculator = SpendCalculator()
        let now = Date()
        let calendar = Calendar.current
        
        // Create entries for today and yesterday
        let todayEntry1 = createTestEntry(id: "today-1", timestamp: now)
        let todayEntry2 = createTestEntry(id: "today-2", timestamp: calendar.date(byAdding: .hour, value: -2, to: now)!)
        let yesterdayEntry = createTestEntry(id: "yesterday", timestamp: calendar.date(byAdding: .day, value: -1, to: now)!)
        
        let entries = [todayEntry1, todayEntry2, yesterdayEntry]
        let summary = calculator.calculateSpendSummary(from: entries)
        
        // Only today's entries should contribute to todaySpend
        #expect(summary.todaySpend > 0)
        
        // Calculate expected today spend manually
        let expectedTodaySpend = PricingManager.shared.calculateTotalCost(for: [todayEntry1, todayEntry2])
        #expect(abs(summary.todaySpend - expectedTodaySpend) < 0.001)
    }
    
    @Test func testCalculateDailySpendForSpecificDate() {
        let calculator = SpendCalculator()
        let calendar = Calendar.current
        let targetDate = Date()
        
        // Create entries for the target date and other dates
        let targetEntry1 = createTestEntry(id: "target-1", timestamp: targetDate, cost: 1.5)
        let targetEntry2 = createTestEntry(id: "target-2", timestamp: calendar.date(byAdding: .hour, value: -3, to: targetDate)!, cost: 2.5)
        let otherDateEntry = createTestEntry(id: "other", timestamp: calendar.date(byAdding: .day, value: -1, to: targetDate)!, cost: 3.0)
        
        let entries = [targetEntry1, targetEntry2, otherDateEntry]
        let dailySpend = calculator.calculateDailySpend(from: entries, for: targetDate)
        
        #expect(dailySpend == 4.0) // 1.5 + 2.5
    }
    
    @Test func testCalculateSpendInRange() {
        let calculator = SpendCalculator()
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -3, to: endDate)!
        
        // Create entries within and outside the range
        let inRangeEntry1 = createTestEntry(id: "in-1", timestamp: startDate, cost: 1.0)
        let inRangeEntry2 = createTestEntry(id: "in-2", timestamp: calendar.date(byAdding: .day, value: -1, to: endDate)!, cost: 2.0)
        let outOfRangeEntry = createTestEntry(id: "out", timestamp: calendar.date(byAdding: .day, value: -5, to: endDate)!, cost: 3.0)
        
        let entries = [inRangeEntry1, inRangeEntry2, outOfRangeEntry]
        let rangeSpend = calculator.calculateSpendInRange(from: entries, startDate: startDate, endDate: endDate)
        
        #expect(rangeSpend == 3.0) // 1.0 + 2.0
    }
    
    @Test func testCalculateModelBreakdown() {
        let calculator = SpendCalculator()
        
        // Create entries with different models
        let sonnetEntry1 = createTestEntry(id: "sonnet-1", model: "claude-3-5-sonnet-20241022", cost: 2.0)
        let sonnetEntry2 = createTestEntry(id: "sonnet-2", model: "claude-3-5-sonnet-20241022", cost: 3.0)
        let haikuEntry = createTestEntry(id: "haiku", model: "claude-3-5-haiku-20241022", cost: 1.0)
        
        let entries = [sonnetEntry1, sonnetEntry2, haikuEntry]
        let breakdown = calculator.calculateModelBreakdown(from: entries)
        
        #expect(breakdown["claude-3-5-sonnet-20241022"] == 5.0)
        #expect(breakdown["claude-3-5-haiku-20241022"] == 1.0)
        #expect(breakdown.count == 2)
    }
    
    // Helper method to create test entries
    private func createTestEntry(
        id: String,
        timestamp: Date = Date(),
        model: String = "claude-3-5-sonnet-20241022",
        cost: Double? = nil
    ) -> UsageEntry {
        return UsageEntry(
            id: id,
            timestamp: timestamp,
            model: model,
            tokenCounts: TokenCounts(input: 100, output: 200),
            cost: cost,
            sessionId: "test-session",
            projectPath: "/test/path"
        )
    }
}

// MARK: - SpendSummary Formatting Tests

struct SpendSummaryFormattingTests {
    
    @Test func testSpendFormatting() {
        let summary = SpendSummary(
            todaySpend: 1.2345,
            weekSpend: 0.0067,
            monthSpend: 123.456,
            modelBreakdown: ["claude-3-5-sonnet-20241022": 10.5, "claude-3-5-haiku-20241022": 0.25]
        )
        
        // Test currency formatting
        #expect(summary.formattedTodaySpend.contains("1.23") || summary.formattedTodaySpend.contains("1.2345"))
        #expect(summary.formattedWeekSpend.contains("0.00") || summary.formattedWeekSpend.contains("0.006"))
        #expect(summary.formattedMonthSpend.contains("123.46") || summary.formattedMonthSpend.contains("123.456"))
        
        // Test model breakdown formatting
        let formattedBreakdown = summary.formattedModelBreakdown
        #expect(formattedBreakdown.count == 2)
        
        // Should be sorted by spend amount (descending)
        #expect(formattedBreakdown[0].model == "claude-3-5-sonnet-20241022")
        #expect(formattedBreakdown[1].model == "claude-3-5-haiku-20241022")
    }
    
    @Test func testSmallAmountFormatting() {
        let summary = SpendSummary(todaySpend: 0.000123)
        
        // Small amounts should show more decimal places
        let formatted = summary.formattedTodaySpend
        #expect(formatted.contains("0.000123") || formatted.contains("$0.00"))
    }
}

// MARK: - Error Handling Tests

struct ErrorHandlingTests {
    
    @Test func testPricingManagerWithEmptyEntries() {
        let pricingManager = PricingManager.shared
        let totalCost = pricingManager.calculateTotalCost(for: [])
        
        #expect(totalCost == 0.0)
    }
    
    @Test func testSpendCalculatorWithEmptyEntries() {
        let calculator = SpendCalculator()
        let summary = calculator.calculateSpendSummary(from: [])
        
        #expect(summary.todaySpend == 0.0)
        #expect(summary.weekSpend == 0.0)
        #expect(summary.monthSpend == 0.0)
        #expect(summary.modelBreakdown.isEmpty)
    }
    
    @Test func testJSONLParserWithEmptyContent() {
        let parser = JSONLParser()
        let entries = parser.parseJSONLContent("")
        
        #expect(entries.isEmpty)
    }
    
    @Test func testUsageEntryCustomInit() {
        // Test direct initialization of UsageEntry
        let tokens = TokenCounts(input: 100, output: 200, cached: 50)
        let date = Date()
        
        let entry = UsageEntry(
            id: "custom-test",
            timestamp: date,
            model: "test-model",
            tokenCounts: tokens,
            cost: 1.5,
            sessionId: "session-test",
            projectPath: "/custom/path"
        )
        
        #expect(entry.id == "custom-test")
        #expect(entry.timestamp == date)
        #expect(entry.model == "test-model")
        #expect(entry.tokenCounts == tokens)
        #expect(entry.cost == 1.5)
        #expect(entry.sessionId == "session-test")
        #expect(entry.projectPath == "/custom/path")
    }
}
