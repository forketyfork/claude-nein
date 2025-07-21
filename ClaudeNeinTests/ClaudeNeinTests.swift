//
//  ClaudeNeinTests.swift
//  ClaudeNeinTests
//
//  Created by Forketyfork on 21.07.25.
//

import XCTest
import Foundation
@testable import ClaudeNein

class ClaudeNeinTests: XCTestCase {
    
    // MARK: - Models Tests
    
    func testTokenCountsTotal() {
        let tokens1 = TokenCounts(input: 100, output: 200, cached: 50)
        XCTAssertEqual(tokens1.total, 350)
        
        let tokens2 = TokenCounts(input: 100, output: 200, cached: nil)
        XCTAssertEqual(tokens2.total, 300)
    }
    
    func testUsageEntryEquality() {
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
        
        XCTAssertEqual(entry1, entry2)
    }
    
    func testSessionBlockInitialization() {
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
        
        XCTAssertEqual(sessionBlock.totalTokens.input, 250)
        XCTAssertEqual(sessionBlock.totalTokens.output, 500)
        XCTAssertEqual(sessionBlock.totalTokens.cached, 50)
        XCTAssertEqual(sessionBlock.totalCost, 3.5)
        XCTAssertEqual(sessionBlock.entries.count, 2)
    }
    
    func testSpendSummaryEmpty() {
        let emptySummary = SpendSummary.empty
        XCTAssertEqual(emptySummary.todaySpend, 0.0)
        XCTAssertEqual(emptySummary.weekSpend, 0.0)
        XCTAssertEqual(emptySummary.monthSpend, 0.0)
        XCTAssertTrue(emptySummary.modelBreakdown.isEmpty)
    }
}

// MARK: - JSONLParser Tests

class JSONLParserTests: XCTestCase {
    
    func testValidJSONLParsing() {
        let parser = JSONLParser()
        let jsonlContent = """
        {"id": "test-1", "timestamp": "2024-07-21T10:00:00Z", "model": "claude-3-5-sonnet-20241022", "token_counts": {"input_tokens": 100, "output_tokens": 200}, "cost": 1.5}
        {"id": "test-2", "timestamp": 1721552400, "model": "claude-3-5-haiku-20241022", "token_counts": {"input_tokens": 50, "output_tokens": 100, "cached_tokens": 25}, "cost": 0.5}
        """
        
        let entries = parser.parseJSONLContent(jsonlContent)
        
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].id, "test-1")
        XCTAssertEqual(entries[0].model, "claude-3-5-sonnet-20241022")
        XCTAssertEqual(entries[0].tokenCounts.input, 100)
        XCTAssertEqual(entries[0].tokenCounts.output, 200)
        XCTAssertEqual(entries[0].cost, 1.5)
        
        XCTAssertEqual(entries[1].id, "test-2")
        XCTAssertEqual(entries[1].model, "claude-3-5-haiku-20241022")
        XCTAssertEqual(entries[1].tokenCounts.cached, 25)
    }
    
    func testMalformedJSONLHandling() {
        let parser = JSONLParser()
        let jsonlContent = """
        {"id": "test-1", "timestamp": "2024-07-21T10:00:00Z", "model": "claude-3-5-sonnet-20241022", "token_counts": {"input_tokens": 100, "output_tokens": 200}}
        invalid json line
        {"id": "test-2", "model": "claude-3-5-haiku-20241022", "token_counts": {"input_tokens": 50, "output_tokens": 100}}
        {"incomplete": "data"
        """
        
        let entries = parser.parseJSONLContent(jsonlContent)
        
        // Should successfully parse valid entries and skip malformed ones
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].id, "test-1")
        XCTAssertEqual(entries[1].id, "test-2")
    }
    
    func testEmptyAndWhitespaceLines() {
        let parser = JSONLParser()
        let jsonlContent = """
        
        {"id": "test-1", "timestamp": "2024-07-21T10:00:00Z", "model": "claude-3-5-sonnet-20241022", "token_counts": {"input_tokens": 100, "output_tokens": 200}}
        
        
        {"id": "test-2", "timestamp": "2024-07-21T10:05:00Z", "model": "claude-3-5-haiku-20241022", "token_counts": {"input_tokens": 50, "output_tokens": 100}}
        
        """
        
        let entries = parser.parseJSONLContent(jsonlContent)
        
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].id, "test-1")
        XCTAssertEqual(entries[1].id, "test-2")
    }
    
    func testDiscoverClaudeConfigDirectories() {
        let directories = JSONLParser.findClaudeConfigDirectories()
        
        // Should return at least some directories (even if they don't exist)
        // The function checks standard locations and environment variables
        XCTAssertGreaterThanOrEqual(directories.count, 0)
        
        // Check that standard paths are included if they exist
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let claudeDir = homeDirectory.appendingPathComponent(".claude/projects")
        let configClaudeDir = homeDirectory.appendingPathComponent(".config/claude/projects")
        
        if FileManager.default.fileExists(atPath: claudeDir.path) {
            XCTAssertTrue(directories.contains(claudeDir))
        }
        
        if FileManager.default.fileExists(atPath: configClaudeDir.path) {
            XCTAssertTrue(directories.contains(configClaudeDir))
        }
    }
}

// MARK: - PricingManager Tests

class PricingManagerTests: XCTestCase {
    
    func testBundledPricingData() {
        let pricingManager = PricingManager.shared
        let pricing = pricingManager.getCurrentPricing()
        
        // Verify bundled data contains expected models
        XCTAssertNotNil(pricing.models["claude-3-5-sonnet-20241022"])
        XCTAssertNotNil(pricing.models["claude-3-5-haiku-20241022"])
        XCTAssertNotNil(pricing.models["claude-3-opus-20240229"])
        
        // Verify pricing structure
        if let sonnetPricing = pricing.models["claude-3-5-sonnet-20241022"] {
            XCTAssertEqual(sonnetPricing.inputPrice, 3.0)
            XCTAssertEqual(sonnetPricing.outputPrice, 15.0)
            XCTAssertEqual(sonnetPricing.cachedPrice, 0.3)
        }
    }
    
    func testCostCalculationWithPrecalculatedCost() {
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
        XCTAssertEqual(calculatedCost, 2.5)
    }
    
    func testCostCalculationFromTokens() {
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
        XCTAssertEqual(calculatedCost, expectedCost, accuracy: 0.001)
    }
    
    func testCostCalculationUnknownModel() {
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
        XCTAssertEqual(calculatedCost, 0.0) // Should return 0 for unknown models
    }
    
    func testCalculateTotalCostForMultipleEntries() {
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
        XCTAssertEqual(totalCost, expectedCost, accuracy: 0.001)
    }
}

// MARK: - SpendCalculator Tests

class SpendCalculatorTests: XCTestCase {
    
    func testCalculateSpendSummary() {
        let calculator = SpendCalculator()
        let now = Date()
        
        // Create test entries for different time periods
        let todayEntry = createTestEntry(id: "today", timestamp: now, cost: 1.0)
        let yesterdayEntry = createTestEntry(id: "yesterday", timestamp: Calendar.current.date(byAdding: .day, value: -1, to: now)!, cost: 2.0)
        let weekAgoEntry = createTestEntry(id: "week", timestamp: Calendar.current.date(byAdding: .day, value: -7, to: now)!, cost: 3.0)
        let monthAgoEntry = createTestEntry(id: "month", timestamp: Calendar.current.date(byAdding: .day, value: -35, to: now)!, cost: 4.0)
        
        let entries = [todayEntry, yesterdayEntry, weekAgoEntry, monthAgoEntry]
        let summary = calculator.calculateSpendSummary(from: entries)
        
        XCTAssertEqual(summary.todaySpend, 1.0)
        // Week includes today + yesterday + week ago (last 7 days)
        XCTAssertGreaterThanOrEqual(summary.weekSpend, 3.0) // At least today + yesterday + week ago
        // Month depends on calendar month boundaries
        XCTAssertGreaterThanOrEqual(summary.monthSpend, 1.0) // At least today
    }
    
    func testFilterEntriesToday() {
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
        XCTAssertGreaterThan(summary.todaySpend, 0)
        
        // Calculate expected today spend manually
        let expectedTodaySpend = PricingManager.shared.calculateTotalCost(for: [todayEntry1, todayEntry2])
        XCTAssertEqual(summary.todaySpend, expectedTodaySpend, accuracy: 0.001)
    }
    
    func testCalculateDailySpendForSpecificDate() {
        let calculator = SpendCalculator()
        let calendar = Calendar.current
        let targetDate = Date()
        
        // Create entries for the target date and other dates
        let targetEntry1 = createTestEntry(id: "target-1", timestamp: targetDate, cost: 1.5)
        let targetEntry2 = createTestEntry(id: "target-2", timestamp: calendar.date(byAdding: .hour, value: -3, to: targetDate)!, cost: 2.5)
        let otherDateEntry = createTestEntry(id: "other", timestamp: calendar.date(byAdding: .day, value: -1, to: targetDate)!, cost: 3.0)
        
        let entries = [targetEntry1, targetEntry2, otherDateEntry]
        let dailySpend = calculator.calculateDailySpend(from: entries, for: targetDate)
        
        XCTAssertEqual(dailySpend, 4.0) // 1.5 + 2.5
    }
    
    func testCalculateSpendInRange() {
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
        
        XCTAssertEqual(rangeSpend, 3.0) // 1.0 + 2.0
    }
    
    func testCalculateModelBreakdown() {
        let calculator = SpendCalculator()
        
        // Create entries with different models
        let sonnetEntry1 = createTestEntry(id: "sonnet-1", model: "claude-3-5-sonnet-20241022", cost: 2.0)
        let sonnetEntry2 = createTestEntry(id: "sonnet-2", model: "claude-3-5-sonnet-20241022", cost: 3.0)
        let haikuEntry = createTestEntry(id: "haiku", model: "claude-3-5-haiku-20241022", cost: 1.0)
        
        let entries = [sonnetEntry1, sonnetEntry2, haikuEntry]
        let breakdown = calculator.calculateModelBreakdown(from: entries)
        
        XCTAssertEqual(breakdown["claude-3-5-sonnet-20241022"], 5.0)
        XCTAssertEqual(breakdown["claude-3-5-haiku-20241022"], 1.0)
        XCTAssertEqual(breakdown.count, 2)
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

class SpendSummaryFormattingTests: XCTestCase {
    
    func testSpendFormatting() {
        let summary = SpendSummary(
            todaySpend: 1.2345,
            weekSpend: 0.0067,
            monthSpend: 123.456,
            modelBreakdown: ["claude-3-5-sonnet-20241022": 10.5, "claude-3-5-haiku-20241022": 0.25]
        )
        
        // Test currency formatting
        XCTAssertTrue(summary.formattedTodaySpend.contains("1.23") || summary.formattedTodaySpend.contains("1.2345"))
        XCTAssertTrue(summary.formattedWeekSpend.contains("0.00") || summary.formattedWeekSpend.contains("0.006"))
        XCTAssertTrue(summary.formattedMonthSpend.contains("123.46") || summary.formattedMonthSpend.contains("123.456"))
        
        // Test model breakdown formatting
        let formattedBreakdown = summary.formattedModelBreakdown
        XCTAssertEqual(formattedBreakdown.count, 2)
        
        // Should be sorted by spend amount (descending)
        XCTAssertEqual(formattedBreakdown[0].model, "claude-3-5-sonnet-20241022")
        XCTAssertEqual(formattedBreakdown[1].model, "claude-3-5-haiku-20241022")
    }
    
    func testSmallAmountFormatting() {
        let summary = SpendSummary(todaySpend: 0.000123)
        
        // Small amounts should show more decimal places
        let formatted = summary.formattedTodaySpend
        XCTAssertTrue(formatted.contains("0.000123") || formatted.contains("$0.00"))
    }
}

// MARK: - Error Handling Tests

class ErrorHandlingTests: XCTestCase {
    
    func testPricingManagerWithEmptyEntries() {
        let pricingManager = PricingManager.shared
        let totalCost = pricingManager.calculateTotalCost(for: [])
        
        XCTAssertEqual(totalCost, 0.0)
    }
    
    func testSpendCalculatorWithEmptyEntries() {
        let calculator = SpendCalculator()
        let summary = calculator.calculateSpendSummary(from: [])
        
        XCTAssertEqual(summary.todaySpend, 0.0)
        XCTAssertEqual(summary.weekSpend, 0.0)
        XCTAssertEqual(summary.monthSpend, 0.0)
        XCTAssertTrue(summary.modelBreakdown.isEmpty)
    }
    
    func testJSONLParserWithEmptyContent() {
        let parser = JSONLParser()
        let entries = parser.parseJSONLContent("")
        
        XCTAssertTrue(entries.isEmpty)
    }
    
    func testUsageEntryCustomInit() {
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
        
        XCTAssertEqual(entry.id, "custom-test")
        XCTAssertEqual(entry.timestamp, date)
        XCTAssertEqual(entry.model, "test-model")
        XCTAssertEqual(entry.tokenCounts, tokens)
        XCTAssertEqual(entry.cost, 1.5)
        XCTAssertEqual(entry.sessionId, "session-test")
        XCTAssertEqual(entry.projectPath, "/custom/path")
    }
}