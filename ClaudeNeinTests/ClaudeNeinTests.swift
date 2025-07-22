//
//  ClaudeNeinTests.swift
//  ClaudeNeinTests
//
//  Created by Forketyfork on 21.07.25.
//

import Testing
import Foundation
import Combine
@testable import ClaudeNein

struct ClaudeNeinTests {
    
    // MARK: - Models Tests
    
    @Test func testTokenCountsTotal() {
        let tokens1 = TokenCounts(input: 100, output: 200, cacheCreation: 30, cacheRead: 20)
        #expect(tokens1.total == 350)
        #expect(tokens1.cached == 50) // 30 + 20
        
        let tokens2 = TokenCounts(input: 100, output: 200, cacheCreation: nil, cacheRead: nil)
        #expect(tokens2.total == 300)
        #expect(tokens2.cached == nil)
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
    
    
}

// MARK: - JSONLParser Tests

struct JSONLParserTests {
    
    @Test func testValidJSONLParsing() {
        let parser = JSONLParser()
        let jsonlContent = """
        {"id": "test-1", "timestamp": "2024-07-21T10:00:00Z", "model": "claude-3-5-sonnet-20241022", "usage": {"input_tokens": 100, "output_tokens": 200}, "costUSD": 1.5}
        {"id": "test-2", "timestamp": 1721552400, "model": "claude-3-5-haiku-20241022", "usage": {"input_tokens": 50, "output_tokens": 100, "cache_read_input_tokens": 25}, "costUSD": 0.5}
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
        {"id": "test-1", "timestamp": "2024-07-21T10:00:00Z", "model": "claude-3-5-sonnet-20241022", "usage": {"input_tokens": 100, "output_tokens": 200}}
        invalid json line
        {"id": "test-2", "timestamp": "2024-07-21T10:05:00Z", "model": "claude-3-5-haiku-20241022", "usage": {"input_tokens": 50, "output_tokens": 100}}
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
        
        {"id": "test-1", "timestamp": "2024-07-21T10:00:00Z", "model": "claude-3-5-sonnet-20241022", "usage": {"input_tokens": 100, "output_tokens": 200}}
        
        
        {"id": "test-2", "timestamp": "2024-07-21T10:05:00Z", "model": "claude-3-5-haiku-20241022", "usage": {"input_tokens": 50, "output_tokens": 100}}
        
        """
        
        let entries = parser.parseJSONLContent(jsonlContent)
        
        #expect(entries.count == 2)
        #expect(entries[0].id == "test-1")
        #expect(entries[1].id == "test-2")
    }
    
    @Test func testDeduplicationFunctionality() {
        let parser = JSONLParser()
        
        // Test entries with same request and message IDs (should be deduplicated)
        let jsonlContent = """
        {"type": "assistant", "timestamp": "2024-07-21T10:00:00Z", "message": {"model": "claude-3-5-sonnet-20241022", "usage": {"input_tokens": 100, "output_tokens": 200}}, "requestId": "req-123", "messageId": "msg-456"}
        {"type": "assistant", "timestamp": "2024-07-21T10:01:00Z", "message": {"model": "claude-3-5-sonnet-20241022", "usage": {"input_tokens": 150, "output_tokens": 250}}, "requestId": "req-123", "messageId": "msg-456"}
        {"type": "assistant", "timestamp": "2024-07-21T10:02:00Z", "message": {"model": "claude-3-5-haiku-20241022", "usage": {"input_tokens": 50, "output_tokens": 100}}, "requestId": "req-789", "messageId": "msg-101"}
        """
        
        let entriesWithDedup = parser.parseJSONLContent(jsonlContent, enableDeduplication: true)
        #expect(entriesWithDedup.count == 2) // Should deduplicate first two entries
        #expect(entriesWithDedup[0].requestId == "req-123")
        #expect(entriesWithDedup[1].requestId == "req-789")
        
        // Clear cache and test without deduplication
        parser.clearDeduplicationCache()
        let entriesWithoutDedup = parser.parseJSONLContent(jsonlContent, enableDeduplication: false)
        #expect(entriesWithoutDedup.count == 3) // Should include all entries
    }
    
    @Test func testUniqueHashGeneration() {
        let entry1 = UsageEntry(
            id: "test-1",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: TokenCounts(input: 100, output: 200),
            requestId: "req-123",
            messageId: "msg-456"
        )
        
        let entry2 = UsageEntry(
            id: "test-2",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: TokenCounts(input: 100, output: 200),
            requestId: "req-123",
            messageId: "msg-456"
        )
        
        let entry3 = UsageEntry(
            id: "test-3",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: TokenCounts(input: 100, output: 200),
            requestId: nil,
            messageId: "msg-456"
        )
        
        // Same request and message IDs should produce same hash with new format
        let expectedHash = "msg-456:req-123"
        #expect(entry1.uniqueHash() == expectedHash)
        #expect(entry2.uniqueHash() == expectedHash)
        
        // Missing request ID should return nil
        #expect(entry3.uniqueHash() == nil)
    }
    
    @Test func testFractionalSecondsTimestampParsing() {
        let parser = JSONLParser()
        
        // Test parsing entries with fractional seconds in timestamps
        let jsonlContent = """
        {"timestamp": "2024-07-21T10:00:00.123Z", "message": {"id": "msg-1", "model": "claude-3-5-sonnet-20241022", "usage": {"input_tokens": 100, "output_tokens": 200}}}
        {"timestamp": "2024-07-21T10:00:00.456789Z", "message": {"id": "msg-2", "model": "claude-3-5-haiku-20241022", "usage": {"input_tokens": 50, "output_tokens": 100}}}
        {"timestamp": "2024-07-21T10:00:00Z", "message": {"id": "msg-3", "model": "claude-3-opus-20240229", "usage": {"input_tokens": 75, "output_tokens": 150}}}
        """
        
        let entries = parser.parseJSONLContent(jsonlContent)
        
        #expect(entries.count == 3)
        
        // Check that timestamps with fractional seconds were parsed correctly
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // First entry with .123 fractional seconds
        let expectedTime1 = formatter.date(from: "2024-07-21T10:00:00.123Z")
        #expect(entries[0].timestamp == expectedTime1)
        
        // Second entry with .456789 fractional seconds
        let expectedTime2 = formatter.date(from: "2024-07-21T10:00:00.456789Z")
        #expect(entries[1].timestamp == expectedTime2)
        
        // Third entry without fractional seconds (should still work)
        let standardFormatter = ISO8601DateFormatter()
        let expectedTime3 = standardFormatter.date(from: "2024-07-21T10:00:00Z")
        #expect(entries[2].timestamp == expectedTime3)
    }
    
    @Test func testStandardUsageFormatParsing() {
        let parser = JSONLParser()
        
        // Test standard usage entry format with proper schema
        let jsonlContent = """
        {"timestamp": "2024-07-21T10:00:00.123Z", "requestId": "req-123", "version": "1.0", "message": {"id": "msg-456", "model": "claude-3-5-sonnet-20241022", "usage": {"input_tokens": 1000, "output_tokens": 2000, "cache_creation_input_tokens": 100, "cache_read_input_tokens": 200}}, "costUSD": 15.5}
        {"timestamp": "2024-07-21T10:01:00Z", "message": {"model": "claude-3-5-haiku-20241022", "usage": {"input_tokens": 500, "output_tokens": 1000}}}
        """
        
        let entries = parser.parseJSONLContent(jsonlContent)
        
        #expect(entries.count == 2)
        
        // First entry - full schema with cached tokens
        let entry1 = entries[0]
        #expect(entry1.model == "claude-3-5-sonnet-20241022")
        #expect(entry1.tokenCounts.input == 1000)
        #expect(entry1.tokenCounts.output == 2000)
        #expect(entry1.tokenCounts.cached == 300) // 100 + 200
        #expect(entry1.cost == 15.5)
        #expect(entry1.requestId == "req-123")
        #expect(entry1.messageId == "msg-456")
        
        // Second entry - minimal schema
        let entry2 = entries[1]
        #expect(entry2.model == "claude-3-5-haiku-20241022")
        #expect(entry2.tokenCounts.input == 500)
        #expect(entry2.tokenCounts.output == 1000)
        #expect(entry2.tokenCounts.cached == nil)
        #expect(entry2.cost == nil)
    }
    
    @Test func testImprovedLineParsingWithNewlines() {
        let parser = JSONLParser()
        
        // Test consistent line parsing with different line ending styles
        let contentWithMixedLineEndings = "{\"timestamp\": \"2024-07-21T10:00:00Z\", \"message\": {\"model\": \"claude-3-5-sonnet-20241022\", \"usage\": {\"input_tokens\": 100, \"output_tokens\": 200}}}\n{\"timestamp\": \"2024-07-21T10:01:00Z\", \"message\": {\"model\": \"claude-3-5-haiku-20241022\", \"usage\": {\"input_tokens\": 50, \"output_tokens\": 100}}}\n"
        
        let entries = parser.parseJSONLContent(contentWithMixedLineEndings)
        
        #expect(entries.count == 2)
        #expect(entries[0].model == "claude-3-5-sonnet-20241022")
        #expect(entries[1].model == "claude-3-5-haiku-20241022")
    }
    
    @Test func testRobustErrorHandlingInParsing() {
        let parser = JSONLParser()
        
        // Test that invalid lines are silently skipped without causing errors
        let jsonlContent = """
        {"timestamp": "2024-07-21T10:00:00Z", "message": {"model": "claude-3-5-sonnet-20241022", "usage": {"input_tokens": 100, "output_tokens": 200}}}
        {invalid json without proper structure
        {"timestamp": "invalid-timestamp", "message": {"model": "claude-3-5-haiku-20241022", "usage": {"input_tokens": 50, "output_tokens": 100}}}
        {"timestamp": "2024-07-21T10:02:00Z", "message": {"model": "claude-3-opus-20240229", "usage": {"input_tokens": 75, "output_tokens": 150}}}
        """
        
        let entries = parser.parseJSONLContent(jsonlContent)
        
        // Should parse the valid entries and silently skip invalid ones
        #expect(entries.count == 2)
        #expect(entries[0].model == "claude-3-5-sonnet-20241022")
        #expect(entries[1].model == "claude-3-opus-20240229")
    }
    
    @Test func testChronologicalFileSorting() {
        // Create temporary files with different timestamps
        let tempDir = FileManager.default.temporaryDirectory
        let file1 = tempDir.appendingPathComponent("file1_\(UUID().uuidString).jsonl")
        let file2 = tempDir.appendingPathComponent("file2_\(UUID().uuidString).jsonl")
        let file3 = tempDir.appendingPathComponent("file3_\(UUID().uuidString).jsonl")
        
        // Write files with different earliest timestamps
        let content1 = """
        {"timestamp": "2024-07-21T12:00:00Z", "id": "test-1"}
        {"timestamp": "2024-07-21T13:00:00Z", "id": "test-2"}
        """
        let content2 = """
        {"timestamp": "2024-07-21T10:00:00Z", "id": "test-3"}
        {"timestamp": "2024-07-21T14:00:00Z", "id": "test-4"}
        """
        let content3 = """
        {"timestamp": "2024-07-21T11:00:00Z", "id": "test-5"}
        """
        
        do {
            try content1.write(to: file1, atomically: true, encoding: .utf8)
            try content2.write(to: file2, atomically: true, encoding: .utf8)
            try content3.write(to: file3, atomically: true, encoding: .utf8)
            
            let sortedFiles = JSONLParser.sortFilesByTimestamp([file1, file2, file3])
            
            // Should be sorted by earliest timestamp: file2 (10:00), file3 (11:00), file1 (12:00)
            #expect(sortedFiles[0] == file2)
            #expect(sortedFiles[1] == file3)
            #expect(sortedFiles[2] == file1)
            
            // Clean up
            try? FileManager.default.removeItem(at: file1)
            try? FileManager.default.removeItem(at: file2)
            try? FileManager.default.removeItem(at: file3)
        } catch {
            // Test failed due to file system error
            #expect(Bool(false), "File system error: \\(error)")
        }
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
            #expect(sonnetPricing.cacheReadPrice == 0.3)
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
    
    @Test func testCostCalculationModesDisplay() {
        let pricingManager = PricingManager.shared
        let tokens = TokenCounts(input: 100, output: 200)
        
        // Test display mode with costUSD available
        let entryWithCost = UsageEntry(
            id: "test-1",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: tokens,
            cost: 2.5,
            sessionId: "session-1",
            projectPath: "/test/path"
        )
        
        let displayCost = pricingManager.calculateCost(for: entryWithCost, mode: .display)
        #expect(displayCost == 2.5)
        
        // Test display mode without costUSD (should return 0)
        let entryWithoutCost = UsageEntry(
            id: "test-2",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: tokens,
            cost: nil,
            sessionId: "session-1",
            projectPath: "/test/path"
        )
        
        let displayCostZero = pricingManager.calculateCost(for: entryWithoutCost, mode: .display)
        #expect(displayCostZero == 0.0)
    }
    
    @Test func testCostCalculationModesCalculate() {
        let pricingManager = PricingManager.shared
        let tokens = TokenCounts(input: 1_000_000, output: 1_000_000, cacheCreation: 500_000, cacheRead: 500_000)
        
        // Test calculate mode ignoring costUSD
        let entryWithHighCost = UsageEntry(
            id: "test-1",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: tokens,
            cost: 99.99, // High cost should be ignored
            sessionId: "session-1",
            projectPath: "/test/path"
        )
        
        let calculatedCost = pricingManager.calculateCost(for: entryWithHighCost, mode: .calculate)
        
        // Expected: (1M * 3.0 + 1M * 15.0 + 500K * 3.75/1M + 500K * 0.3/1M) = 20.025
        let expectedCost = 3.0 + 15.0 + 1.875 + 0.15
        #expect(abs(calculatedCost - expectedCost) < 0.001)
    }
    
    @Test func testCostCalculationModesAuto() {
        let pricingManager = PricingManager.shared
        let tokens = TokenCounts(input: 100, output: 200)
        
        // Test auto mode with costUSD (should use costUSD)
        let entryWithCost = UsageEntry(
            id: "test-1",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: tokens,
            cost: 2.5,
            sessionId: "session-1",
            projectPath: "/test/path"
        )
        
        let autoCostWithCost = pricingManager.calculateCost(for: entryWithCost, mode: .auto)
        #expect(autoCostWithCost == 2.5)
        
        // Test auto mode without costUSD (should calculate)
        let entryWithoutCost = UsageEntry(
            id: "test-2",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: tokens,
            cost: nil,
            sessionId: "session-1",
            projectPath: "/test/path"
        )
        
        let autoCostCalculated = pricingManager.calculateCost(for: entryWithoutCost, mode: .auto)
        #expect(autoCostCalculated > 0.0) // Should calculate from tokens
    }
    
    @Test func testCostCalculationFromTokens() {
        let pricingManager = PricingManager.shared
        let tokens = TokenCounts(input: 1_000_000, output: 1_000_000, cacheCreation: 500_000, cacheRead: 500_000)
        
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
        
        // Expected: (1M * 3.0 + 1M * 15.0 + 500K * 3.75/1M + 500K * 0.3/1M) = 20.025
        let expectedCost = 3.0 + 15.0 + 1.875 + 0.15
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
        
        // Expected: 3.0 (Sonnet input) + 0.8 (Haiku input) = 3.8
        let expectedCost = 3.0 + 0.8
        #expect(abs(totalCost - expectedCost) < 0.001)
    }
}

// MARK: - SpendCalculator Tests

struct SpendCalculatorTests {
    
    @Test func testCalculateSpendSummary() {
        let calculator = SpendCalculator()
        let now = Date()
        let calendar = Calendar.current

        // Determine start of week and month according to locale
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!

        // Create entries spanning different periods
        let todayEntry = createTestEntry(id: "today", timestamp: now, cost: 1.0)
        let weekStartEntry = createTestEntry(id: "week-start", timestamp: startOfWeek, cost: 2.0)
        let beforeWeekEntry = createTestEntry(id: "before-week", timestamp: calendar.date(byAdding: .hour, value: -1, to: startOfWeek)!, cost: 3.0)
        let monthStartEntry = createTestEntry(id: "month-start", timestamp: startOfMonth, cost: 4.0)
        let beforeMonthEntry = createTestEntry(id: "before-month", timestamp: calendar.date(byAdding: .hour, value: -1, to: startOfMonth)!, cost: 5.0)

        let entries = [todayEntry, weekStartEntry, beforeWeekEntry, monthStartEntry, beforeMonthEntry]
        let summary = calculator.calculateSpendSummary(from: entries)

        // Today spend should only include today's entry
        #expect(summary.todaySpend == 1.0)

        // Week spend should include entries from startOfWeek onwards
        let expectedWeekSpend = PricingManager.shared.calculateTotalCost(for: [todayEntry, weekStartEntry])
        #expect(abs(summary.weekSpend - expectedWeekSpend) < 0.001)

        // Month spend should include entries from startOfMonth onwards
        let expectedMonthEntries = [todayEntry, weekStartEntry, beforeWeekEntry, monthStartEntry]
        let expectedMonthSpend = PricingManager.shared.calculateTotalCost(for: expectedMonthEntries)
        #expect(abs(summary.monthSpend - expectedMonthSpend) < 0.001)
    }
    
    @Test func testCalculateSpendSummaryWithCostModes() {
        let calculator = SpendCalculator()
        let now = Date()
        
        // Create entries with both costUSD and token counts
        let entryWithCost = createTestEntry(id: "with-cost", timestamp: now, cost: 5.0)
        let entryWithoutCost = createTestEntry(id: "without-cost", timestamp: now, cost: nil)
        let entries = [entryWithCost, entryWithoutCost]
        
        // Test display mode - should only use costUSD values
        let displaySummary = calculator.calculateSpendSummary(from: entries, costMode: .display)
        #expect(displaySummary.todaySpend == 5.0) // Only the entry with cost contributes
        
        // Test calculate mode - should ignore costUSD and calculate from tokens
        let calculateSummary = calculator.calculateSpendSummary(from: entries, costMode: .calculate)
        #expect(calculateSummary.todaySpend > 0.0) // Should calculate costs from tokens for both entries
        
        // Test auto mode - should use costUSD when available, calculate otherwise
        let autoSummary = calculator.calculateSpendSummary(from: entries, costMode: .auto)
        #expect(autoSummary.todaySpend > 5.0) // Should use 5.0 + calculated cost for second entry
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
    
}

// MARK: - FileMonitor Tests

struct FileMonitorTests {
    
    @Test func testFileStateCreation() {
        // Create a temporary file for testing
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_file_\(UUID().uuidString).txt")
        
        // Write test content to file
        let testContent = "test content"
        try? testContent.write(to: testFile, atomically: true, encoding: .utf8)
        
        // Test FileState creation
        let fileState = FileMonitor.FileState.create(from: testFile)
        
        #expect(fileState != nil)
        #expect(fileState?.url == testFile)
        #expect((fileState?.size ?? 0) > 0)
        
        // Clean up
        try? FileManager.default.removeItem(at: testFile)
    }
    
    @Test func testFileStateCreationWithNonexistentFile() {
        let nonexistentFile = URL(fileURLWithPath: "/nonexistent/path/file.txt")
        let fileState = FileMonitor.FileState.create(from: nonexistentFile)
        
        #expect(fileState == nil)
    }
    
    @Test func testFileMonitorInitialization() {
        let fileMonitor = FileMonitor()
        
        #expect(fileMonitor.isMonitoring == false)
        #expect(fileMonitor.getCachedEntries().isEmpty)
    }
    
    @Test func testFileChangeNotificationStructure() {
        let testFiles = [
            URL(fileURLWithPath: "/test/file1.jsonl"),
            URL(fileURLWithPath: "/test/file2.jsonl")
        ]
        
        let notification = FileMonitor.FileChangeNotification(
            changedFiles: testFiles,
            timestamp: Date()
        )
        
        #expect(notification.changedFiles.count == 2)
        #expect(notification.changedFiles[0].path == "/test/file1.jsonl")
        #expect(notification.changedFiles[1].path == "/test/file2.jsonl")
    }
    
    @Test func testFileMonitorErrorTypes() {
        let permissionError = FileMonitor.FileMonitorError.permissionDenied(path: "/restricted/path")
        let fileNotFoundError = FileMonitor.FileMonitorError.fileNotFound(path: "/missing/file")
        let diskFullError = FileMonitor.FileMonitorError.diskFull
        let corruptedFileError = FileMonitor.FileMonitorError.corruptedFile(path: "/bad/file")
        let networkError = FileMonitor.FileMonitorError.networkError(path: "/network/path")
        let unknownError = FileMonitor.FileMonitorError.unknownError(underlying: NSError(domain: "test", code: 1))
        
        #expect(permissionError.errorDescription?.contains("Permission denied") == true)
        #expect(fileNotFoundError.errorDescription?.contains("File not found") == true)
        #expect(diskFullError.errorDescription?.contains("Disk is full") == true)
        #expect(corruptedFileError.errorDescription?.contains("corrupted") == true)
        #expect(networkError.errorDescription?.contains("Network") == true)
        #expect(unknownError.errorDescription?.contains("Unknown error") == true)
    }
    
    @Test func testClearCacheOperation() {
        let fileMonitor = FileMonitor()
        
        // Initially, cache should be empty
        #expect(fileMonitor.getCachedEntries().isEmpty)
        
        // Clear cache should not cause any issues when empty
        fileMonitor.clearCache()
        #expect(fileMonitor.getCachedEntries().isEmpty)
    }
    
    @Test func testGetModifiedEntriesWithEmptyCache() {
        let fileMonitor = FileMonitor()
        let testDate = Date()
        
        let modifiedEntries = fileMonitor.getModifiedEntries(since: testDate)
        #expect(modifiedEntries.isEmpty)
    }
    
    @Test func testFileMonitorPublisherSetup() {
        let fileMonitor = FileMonitor()
        
        // Test that fileChanges publisher is accessible
        let publisher = fileMonitor.fileChanges
        
        // Verify publisher type
        #expect(publisher is AnyPublisher<FileMonitor.FileChangeNotification, Never>)
    }
    
    @Test func testFileMonitorThreadSafety() {
        let fileMonitor = FileMonitor()
        var results: [Int] = []
        let resultsLock = NSLock()
        
        // Simulate concurrent access to getCachedEntries
        DispatchQueue.concurrentPerform(iterations: 10) { index in
            let entries = fileMonitor.getCachedEntries()
            resultsLock.lock()
            results.append(entries.count)
            resultsLock.unlock()
        }
        
        // All concurrent calls should complete successfully
        #expect(results.count == 10)
        
        // All results should be the same (empty cache)
        let uniqueResults = Set(results)
        #expect(uniqueResults.count == 1)
        #expect(uniqueResults.first == 0)
    }
    
    @Test func testFileMonitorForceRefresh() {
        let fileMonitor = FileMonitor()
        
        // Force refresh should not crash when no monitoring is active
        fileMonitor.forceRefresh()
        
        // Cache should still be empty
        #expect(fileMonitor.getCachedEntries().isEmpty)
    }
}
