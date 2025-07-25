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
    
    @Test func testUsageEntryEquality() throws {
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
        
        try #require(entry1 == entry2)
    }
    
    @Test func testCoreDataUpsert() async throws {
        // Create an in-memory DataStore for testing
        let dataStore = DataStore(inMemory: true)
        
        // Create test entries with cache tokens
        let entry = UsageEntry(
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: TokenCounts(input: 100, output: 200, cacheCreation: 50, cacheRead: 25),
            cost: 1.5,
            sessionId: "test-session",
            projectPath: "/test/path",
            requestId: "req-123",
            originalMessageId: "msg-456"
        )
        
        // Test upsert
        await dataStore.upsertEntries([entry])
        
        // Fetch and verify
        let fetchedEntries = dataStore.fetchAllEntries()
        try #require(fetchedEntries.count == 1)
        
        let fetchedEntry = fetchedEntries[0]
        try #require(fetchedEntry.model == "claude-3-5-sonnet-20241022")
        try #require(fetchedEntry.tokenCounts.input == 100)
        try #require(fetchedEntry.tokenCounts.output == 200)
        try #require(fetchedEntry.tokenCounts.cacheCreation == 50)
        try #require(fetchedEntry.tokenCounts.cacheRead == 25)
        try #require(fetchedEntry.cost == 1.5)
        try #require(fetchedEntry.sessionId == "test-session")
        try #require(fetchedEntry.requestId == "req-123")
        try #require(fetchedEntry.originalMessageId == "msg-456")
    }
    
    
}

// MARK: - JSONLParser Tests

struct JSONLParserTests {
    
    @Test func testValidJSONLParsing() throws {
        let parser = JSONLParser()
        let jsonlContent = """
        {"type": "assistant", "id": "test-1", "timestamp": "2024-07-21T10:00:00Z", "model": "claude-3-5-sonnet-20241022", "usage": {"input_tokens": 100, "output_tokens": 200}, "costUSD": 1.5}
        {"type": "assistant", "id": "test-2", "timestamp": 1721552400, "model": "claude-3-5-haiku-20241022", "usage": {"input_tokens": 50, "output_tokens": 100, "cache_read_input_tokens": 25}, "costUSD": 0.5}
        """
        
        let entries = parser.parseJSONLContent(jsonlContent)
        
        try #require(entries.count == 2)
        try #require(entries[0].originalMessageId == "test-1")
        try #require(entries[0].model == "claude-3-5-sonnet-20241022")
        try #require(entries[0].tokenCounts.input == 100)
        try #require(entries[0].tokenCounts.output == 200)
        try #require(entries[0].cost == 1.5)
        
        try #require(entries[1].originalMessageId == "test-2")
        try #require(entries[1].model == "claude-3-5-haiku-20241022")
        try #require(entries[1].tokenCounts.cached == 25)
    }
    
    @Test func testMalformedJSONLHandling() throws {
        let parser = JSONLParser()
        let jsonlContent = """
        {"type": "assistant", "id": "test-1", "timestamp": "2024-07-21T10:00:00Z", "model": "claude-3-5-sonnet-20241022", "usage": {"input_tokens": 100, "output_tokens": 200}}
        invalid json line
        {"type": "assistant", "id": "test-2", "timestamp": "2024-07-21T10:05:00Z", "model": "claude-3-5-haiku-20241022", "usage": {"input_tokens": 50, "output_tokens": 100}}
        {"incomplete": "data"
        """
        
        let entries = parser.parseJSONLContent(jsonlContent)
        
        // Should successfully parse valid entries and skip malformed ones
        try #require(entries.count == 2)
        try #require(entries[0].originalMessageId == "test-1")
        try #require(entries[1].originalMessageId == "test-2")
    }
    
    @Test func testEmptyAndWhitespaceLines() throws {
        let parser = JSONLParser()
        let jsonlContent = """
        
        {"type": "assistant", "id": "test-1", "timestamp": "2024-07-21T10:00:00Z", "model": "claude-3-5-sonnet-20241022", "usage": {"input_tokens": 100, "output_tokens": 200}}
        
        
        {"type": "assistant", "id": "test-2", "timestamp": "2024-07-21T10:05:00Z", "model": "claude-3-5-haiku-20241022", "usage": {"input_tokens": 50, "output_tokens": 100}}
        
        """
        
        let entries = parser.parseJSONLContent(jsonlContent)
        
        try #require(entries.count == 2)
        try #require(entries[0].originalMessageId == "test-1")
        try #require(entries[1].originalMessageId == "test-2")
    }
    
    @Test func testDeduplicationFunctionality() throws {
        let parser = JSONLParser()
        
        // Test entries with same request and message IDs (should be deduplicated)
        let jsonlContent = """
        {"type": "assistant", "timestamp": "2024-07-21T10:00:00Z", "message": {"model": "claude-3-5-sonnet-20241022", "usage": {"input_tokens": 100, "output_tokens": 200}}, "requestId": "req-123", "messageId": "msg-456"}
        {"type": "assistant", "timestamp": "2024-07-21T10:01:00Z", "message": {"model": "claude-3-5-sonnet-20241022", "usage": {"input_tokens": 150, "output_tokens": 250}}, "requestId": "req-123", "messageId": "msg-456"}
        {"type": "assistant", "timestamp": "2024-07-21T10:02:00Z", "message": {"model": "claude-3-5-haiku-20241022", "usage": {"input_tokens": 50, "output_tokens": 100}}, "requestId": "req-789", "messageId": "msg-101"}
        """
        
        let entriesWithDedup = parser.parseJSONLContent(jsonlContent, enableDeduplication: true)
        try #require(entriesWithDedup.count == 2) // Should deduplicate first two entries
        try #require(entriesWithDedup[0].requestId == "req-123")
        try #require(entriesWithDedup[1].requestId == "req-789")
        
        // Clear cache and test without deduplication
        parser.clearDeduplicationCache()
        let entriesWithoutDedup = parser.parseJSONLContent(jsonlContent, enableDeduplication: false)
        try #require(entriesWithoutDedup.count == 3) // Should include all entries
    }
    
    @Test func testUniqueHashGeneration() throws {
        let entry1 = UsageEntry(
            id: "test-1",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: TokenCounts(input: 100, output: 200),
            requestId: "req-123",
            originalMessageId: "msg-456"
        )
        
        let entry2 = UsageEntry(
            id: "test-2",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: TokenCounts(input: 100, output: 200),
            requestId: "req-123",
            originalMessageId: "msg-456"
        )
        
        let entry3 = UsageEntry(
            id: "test-3",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: TokenCounts(input: 100, output: 200),
            requestId: nil,
            originalMessageId: "msg-456"
        )
        
        // Same request and message IDs should produce same hash with new format
        let expectedHash = "msg-456:req-123"
        try #require(entry1.uniqueHash() == expectedHash)
        try #require(entry2.uniqueHash() == expectedHash)
        
        // Missing request ID should return nil
        try #require(entry3.uniqueHash() == nil)
    }
    
    @Test func testFractionalSecondsTimestampParsing() throws {
        let parser = JSONLParser()
        
        // Test parsing entries with fractional seconds in timestamps
        let jsonlContent = """
        {"type": "assistant", "timestamp": "2024-07-21T10:00:00.123Z", "message": {"id": "msg-1", "model": "claude-3-5-sonnet-20241022", "usage": {"input_tokens": 100, "output_tokens": 200}}}
        {"type": "assistant", "timestamp": "2024-07-21T10:00:00.456789Z", "message": {"id": "msg-2", "model": "claude-3-5-haiku-20241022", "usage": {"input_tokens": 50, "output_tokens": 100}}}
        {"type": "assistant", "timestamp": "2024-07-21T10:00:00Z", "message": {"id": "msg-3", "model": "claude-3-opus-20240229", "usage": {"input_tokens": 75, "output_tokens": 150}}}
        """
        
        let entries = parser.parseJSONLContent(jsonlContent)
        
        try #require(entries.count == 3)
        
        // Check that timestamps with fractional seconds were parsed correctly
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // First entry with .123 fractional seconds
        let expectedTime1 = formatter.date(from: "2024-07-21T10:00:00.123Z")
        try #require(entries[0].timestamp == expectedTime1)
        
        // Second entry with .456789 fractional seconds
        let expectedTime2 = formatter.date(from: "2024-07-21T10:00:00.456789Z")
        try #require(entries[1].timestamp == expectedTime2)
        
        // Third entry without fractional seconds (should still work)
        let standardFormatter = ISO8601DateFormatter()
        let expectedTime3 = standardFormatter.date(from: "2024-07-21T10:00:00Z")
        try #require(entries[2].timestamp == expectedTime3)
    }
    
    @Test func testStandardUsageFormatParsing() throws {
        let parser = JSONLParser()
        
        // Test standard usage entry format with proper schema
        let jsonlContent = """
        {"type": "assistant", "timestamp": "2024-07-21T10:00:00.123Z", "requestId": "req-123", "version": "1.0", "message": {"id": "msg-456", "model": "claude-3-5-sonnet-20241022", "usage": {"input_tokens": 1000, "output_tokens": 2000, "cache_creation_input_tokens": 100, "cache_read_input_tokens": 200}}, "costUSD": 15.5}
        {"type": "assistant", "timestamp": "2024-07-21T10:01:00Z", "message": {"model": "claude-3-5-haiku-20241022", "usage": {"input_tokens": 500, "output_tokens": 1000}}}
        """
        
        let entries = parser.parseJSONLContent(jsonlContent)
        
        try #require(entries.count == 2)
        
        // First entry - full schema with cached tokens
        let entry1 = entries[0]
        try #require(entry1.model == "claude-3-5-sonnet-20241022")
        try #require(entry1.tokenCounts.input == 1000)
        try #require(entry1.tokenCounts.output == 2000)
        try #require(entry1.tokenCounts.cached == 300) // 100 + 200
        try #require(entry1.cost == 15.5)
        try #require(entry1.requestId == "req-123")
        try #require(entry1.originalMessageId == "msg-456")
        
        // Second entry - minimal schema
        let entry2 = entries[1]
        try #require(entry2.model == "claude-3-5-haiku-20241022")
        try #require(entry2.tokenCounts.input == 500)
        try #require(entry2.tokenCounts.output == 1000)
        try #require(entry2.tokenCounts.cached == nil)
        try #require(entry2.cost == nil)
    }
    
    @Test func testImprovedLineParsingWithNewlines() throws {
        let parser = JSONLParser()
        
        // Test consistent line parsing with different line ending styles
        let contentWithMixedLineEndings = "{\"type\": \"assistant\", \"timestamp\": \"2024-07-21T10:00:00Z\", \"message\": {\"model\": \"claude-3-5-sonnet-20241022\", \"usage\": {\"input_tokens\": 100, \"output_tokens\": 200}}}\n{\"type\": \"assistant\", \"timestamp\": \"2024-07-21T10:01:00Z\", \"message\": {\"model\": \"claude-3-5-haiku-20241022\", \"usage\": {\"input_tokens\": 50, \"output_tokens\": 100}}}\n"
        
        let entries = parser.parseJSONLContent(contentWithMixedLineEndings)
        
        try #require(entries.count == 2)
        try #require(entries[0].model == "claude-3-5-sonnet-20241022")
        try #require(entries[1].model == "claude-3-5-haiku-20241022")
    }
    
    @Test func testRobustErrorHandlingInParsing() throws {
        let parser = JSONLParser()
        
        // Test that invalid lines are silently skipped without causing errors
        let jsonlContent = """
        {"type": "assistant", "timestamp": "2024-07-21T10:00:00Z", "message": {"model": "claude-3-5-sonnet-20241022", "usage": {"input_tokens": 100, "output_tokens": 200}}}
        {invalid json without proper structure
        {"timestamp": "invalid-timestamp", "message": {"model": "claude-3-5-haiku-20241022", "usage": {"input_tokens": 50, "output_tokens": 100}}}
        {"type": "assistant", "timestamp": "2024-07-21T10:02:00Z", "message": {"model": "claude-3-opus-20240229", "usage": {"input_tokens": 75, "output_tokens": 150}}}
        """
        
        let entries = parser.parseJSONLContent(jsonlContent)
        
        // Should parse the valid entries and silently skip invalid ones
        try #require(entries.count == 2)
        try #require(entries[0].model == "claude-3-5-sonnet-20241022")
        try #require(entries[1].model == "claude-3-opus-20240229")
    }
    
    @Test func testEntryTypeFiltering() throws {
        let parser = JSONLParser()
        
        // Test that only assistant entries with usage data are parsed
        let jsonlContent = """
        {"type": "user", "timestamp": "2024-07-21T10:00:00Z", "message": {"role": "user", "content": [{"type": "text", "text": "Hello"}]}, "uuid": "user-uuid-1"}
        {"type": "assistant", "timestamp": "2024-07-21T10:01:00Z", "message": {"id": "msg-1", "model": "claude-3-5-sonnet-20241022", "usage": {"input_tokens": 100, "output_tokens": 200}}, "requestId": "req-123"}
        {"type": "summary", "timestamp": "2024-07-21T10:02:00Z", "summary": "This is a summary", "leafUuid": "leaf-uuid"}
        {"type": "assistant", "timestamp": "2024-07-21T10:03:00Z", "message": {"id": "msg-2", "model": "claude-3-5-haiku-20241022", "usage": {"input_tokens": 50, "output_tokens": 100}}, "requestId": "req-456"}
        """
        
        let entries = parser.parseJSONLContent(jsonlContent)
        
        // Should only parse the 2 assistant entries, ignoring user and summary entries
        try #require(entries.count == 2)
        try #require(entries[0].model == "claude-3-5-sonnet-20241022")
        try #require(entries[0].originalMessageId == "msg-1")
        try #require(entries[0].requestId == "req-123")
        try #require(entries[1].model == "claude-3-5-haiku-20241022")
        try #require(entries[1].originalMessageId == "msg-2")
        try #require(entries[1].requestId == "req-456")
    }
    
    @Test func testAssistantEntryWithoutUsageData() throws {
        let parser = JSONLParser()
        
        // Test assistant entry that doesn't have usage data (should be filtered out)
        let jsonlContent = """
        {"type": "assistant", "timestamp": "2024-07-21T10:01:00Z", "message": {"id": "msg-1", "model": "claude-3-5-sonnet-20241022", "content": [{"type": "text", "text": "Hello"}]}, "requestId": "req-123"}
        {"type": "assistant", "timestamp": "2024-07-21T10:02:00Z", "message": {"id": "msg-2", "model": "claude-3-5-haiku-20241022", "usage": {"input_tokens": 50, "output_tokens": 100}}, "requestId": "req-456"}
        """
        
        let entries = parser.parseJSONLContent(jsonlContent)
        
        // Should only parse the entry with usage data
        try #require(entries.count == 1)
        try #require(entries[0].model == "claude-3-5-haiku-20241022")
        try #require(entries[0].originalMessageId == "msg-2")
        try #require(entries[0].requestId == "req-456")
    }
    
    @Test func testUserEntryWithToolResults() throws {
        let parser = JSONLParser()
        
        // Test the specific user entry format from the error message
        let jsonlContent = """
        {"parentUuid":"9d3120af-7075-4338-81ac-f0cc7d2a6d8d","isSidechain":true,"userType":"external","cwd":"/Users/sergei.petunin/dev/jb/CodeCanvas/codecanvas","sessionId":"1af9c387-f946-4ff7-aea2-9714ca69348b","version":"1.0.35","type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01PbVyEXoVzfzUEAB1QDaTDS","type":"tool_result","content":"No files found"}]},"uuid":"9e3f02a5-5a9a-4307-9de0-c335e58f7847","timestamp":"2025-06-26T11:14:58.178Z","toolUseResult":{"filenames":[],"numFiles":0}}
        {"type": "assistant", "timestamp": "2025-06-26T11:15:00Z", "message": {"id": "msg-1", "model": "claude-3-5-sonnet-20241022", "usage": {"input_tokens": 100, "output_tokens": 200}}, "requestId": "req-123"}
        """
        
        let entries = parser.parseJSONLContent(jsonlContent)
        
        // Should only parse the assistant entry, ignoring the user entry with tool results
        try #require(entries.count == 1)
        try #require(entries[0].model == "claude-3-5-sonnet-20241022")
        try #require(entries[0].originalMessageId == "msg-1")
        try #require(entries[0].requestId == "req-123")
    }
    
    @Test func testChronologicalFileSorting() throws {
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
            try #require(sortedFiles[0] == file2)
            try #require(sortedFiles[1] == file3)
            try #require(sortedFiles[2] == file1)
            
            // Clean up
            try? FileManager.default.removeItem(at: file1)
            try? FileManager.default.removeItem(at: file2)
            try? FileManager.default.removeItem(at: file3)
        } catch {
            // Test failed due to file system error
            try #require(Bool(false), "File system error: \\(error)")
        }
    }
    
    @Test func testDiscoverClaudeConfigDirectories() throws {
        let directories = JSONLParser.findClaudeConfigDirectories()
        
        // Should return at least some directories (even if they don't exist)
        // The function checks standard locations and environment variables
        #expect(directories.count >= 0)
        
        // Check that standard paths are included if they exist
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let claudeDir = homeDirectory.appendingPathComponent(".claude/projects")
        let configClaudeDir = homeDirectory.appendingPathComponent(".config/claude/projects")
        
        if FileManager.default.fileExists(atPath: claudeDir.path) {
            try #require(directories.contains(claudeDir))
        }
        
        if FileManager.default.fileExists(atPath: configClaudeDir.path) {
            try #require(directories.contains(configClaudeDir))
        }
    }
}

// MARK: - PricingManager Tests

struct PricingManagerTests {
    
    @Test func testBundledPricingData() throws {
        let pricingManager = PricingManager.shared
        let pricing = pricingManager.getCurrentPricing()
        
        // Verify bundled data contains expected models
        try #require(pricing.models["claude-3-5-sonnet-20241022"] != nil)
        try #require(pricing.models["claude-3-5-haiku-20241022"] != nil)
        try #require(pricing.models["claude-3-opus-20240229"] != nil)
        
        // Verify pricing structure
        if let sonnetPricing = pricing.models["claude-3-5-sonnet-20241022"] {
            try #require(sonnetPricing.inputPrice == 3.0)
            try #require(sonnetPricing.outputPrice == 15.0)
            try #require(sonnetPricing.cacheReadPrice == 0.3)
        }
    }
    
    @Test func testCostCalculationWithPrecalculatedCost() throws {
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
        try #require(calculatedCost == 2.5)
    }
    
    @Test func testCostCalculationModesDisplay() throws {
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
        try #require(displayCost == 2.5)
        
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
        try #require(displayCostZero == 0.0)
    }
    
    @Test func testCostCalculationModesCalculate() throws {
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
        try #require(abs(calculatedCost - expectedCost) < 0.001)
    }
    
    @Test func testCostCalculationModesAuto() throws {
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
        try #require(autoCostWithCost == 2.5)
        
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
    
    @Test func testCostCalculationFromTokens() throws {
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
        try #require(abs(calculatedCost - expectedCost) < 0.001)
    }
    
    @Test func testCostCalculationUnknownModel() throws {
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
        try #require(calculatedCost == 0.0) // Should return 0 for unknown models
    }
    
    @Test func testCalculateTotalCostForMultipleEntries() throws {
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
        try #require(abs(totalCost - expectedCost) < 0.001)
    }
}

// MARK: - SpendCalculator Tests

struct SpendCalculatorTests {
    
    @Test func testCalculateSpendSummary() throws {
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
        try #require(summary.todaySpend == 1.0)

        // Week spend should include entries from startOfWeek onwards
        let expectedWeekSpend = PricingManager.shared.calculateTotalCost(for: [todayEntry, weekStartEntry])
        try #require(abs(summary.weekSpend - expectedWeekSpend) < 0.001)

        // Month spend should include entries from startOfMonth onwards
        let expectedMonthEntries = [todayEntry, weekStartEntry, beforeWeekEntry, monthStartEntry]
        let expectedMonthSpend = PricingManager.shared.calculateTotalCost(for: expectedMonthEntries)
        try #require(abs(summary.monthSpend - expectedMonthSpend) < 0.001)
    }
    
    @Test func testCalculateSpendSummaryWithCostModes() throws {
        let calculator = SpendCalculator()
        let now = Date()
        
        // Create entries with both costUSD and token counts
        let entryWithCost = createTestEntry(id: "with-cost", timestamp: now, cost: 5.0)
        let entryWithoutCost = createTestEntry(id: "without-cost", timestamp: now, cost: nil)
        let entries = [entryWithCost, entryWithoutCost]
        
        // Test display mode - should only use costUSD values
        let displaySummary = calculator.calculateSpendSummary(from: entries, costMode: .display)
        try #require(displaySummary.todaySpend == 5.0) // Only the entry with cost contributes
        
        // Test calculate mode - should ignore costUSD and calculate from tokens
        let calculateSummary = calculator.calculateSpendSummary(from: entries, costMode: .calculate)
        try #require(calculateSummary.todaySpend > 0.0) // Should calculate costs from tokens for both entries
        
        // Test auto mode - should use costUSD when available, calculate otherwise
        let autoSummary = calculator.calculateSpendSummary(from: entries, costMode: .auto)
        try #require(autoSummary.todaySpend > 5.0) // Should use 5.0 + calculated cost for second entry
    }
    
    @Test func testFilterEntriesToday() throws {
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
        try #require(abs(summary.todaySpend - expectedTodaySpend) < 0.001)
    }
    
    @Test func testCalculateDailySpendForSpecificDate() throws {
        let calculator = SpendCalculator()
        let calendar = Calendar.current
        let targetDate = Date()
        
        // Create entries for the target date and other dates
        let targetEntry1 = createTestEntry(id: "target-1", timestamp: targetDate, cost: 1.5)
        let targetEntry2 = createTestEntry(id: "target-2", timestamp: calendar.date(byAdding: .hour, value: -3, to: targetDate)!, cost: 2.5)
        let otherDateEntry = createTestEntry(id: "other", timestamp: calendar.date(byAdding: .day, value: -1, to: targetDate)!, cost: 3.0)
        
        let entries = [targetEntry1, targetEntry2, otherDateEntry]
        let dailySpend = calculator.calculateDailySpend(from: entries, for: targetDate)
        
        try #require(dailySpend == 4.0) // 1.5 + 2.5
    }
    
    @Test func testCalculateSpendInRange() throws {
        let calculator = SpendCalculator()
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -3, to: endDate)!;
        
        // Create entries within and outside the range
        let inRangeEntry1 = createTestEntry(id: "in-1", timestamp: startDate, cost: 1.0)
        let inRangeEntry2 = createTestEntry(id: "in-2", timestamp: calendar.date(byAdding: .day, value: -1, to: endDate)!, cost: 2.0)
        let outOfRangeEntry = createTestEntry(id: "out", timestamp: calendar.date(byAdding: .day, value: -5, to: endDate)!, cost: 3.0)
        
        let entries = [inRangeEntry1, inRangeEntry2, outOfRangeEntry]
        let rangeSpend = calculator.calculateSpendInRange(from: entries, startDate: startDate, endDate: endDate)
        
        try #require(rangeSpend == 3.0) // 1.0 + 2.0
    }
    
    @Test func testCalculateModelBreakdown() throws {
        let calculator = SpendCalculator()
        
        // Create entries with different models
        let sonnetEntry1 = createTestEntry(id: "sonnet-1", model: "claude-3-5-sonnet-20241022", cost: 2.0)
        let sonnetEntry2 = createTestEntry(id: "sonnet-2", model: "claude-3-5-sonnet-20241022", cost: 3.0)
        let haikuEntry = createTestEntry(id: "haiku", model: "claude-3-5-haiku-20241022", cost: 1.0)
        
        let entries = [sonnetEntry1, sonnetEntry2, haikuEntry]
        let breakdown = calculator.calculateModelBreakdown(from: entries)
        
        try #require(breakdown["claude-3-5-sonnet-20241022"] == 5.0)
        try #require(breakdown["claude-3-5-haiku-20241022"] == 1.0)
        try #require(breakdown.count == 2)
    }
    
    @Test func testModelBreakdownFiltersSyntheticModels() throws {
        let calculator = SpendCalculator()
        
        let normalEntry = createTestEntry(id: "normal-1", model: "claude-3-5-sonnet-20241022", cost: 2.0)
        let syntheticEntry = createTestEntry(id: "synthetic-1", model: "<synthetic>", cost: 1.5)
        let anotherNormalEntry = createTestEntry(id: "normal-2", model: "claude-3-haiku-20240307", cost: 0.5)
        
        let entries = [normalEntry, syntheticEntry, anotherNormalEntry]
        let breakdown = calculator.calculateModelBreakdown(from: entries)
        
        // Should only include non-synthetic models
        #expect(breakdown["claude-3-5-sonnet-20241022"] == 2.0)
        #expect(breakdown["claude-3-haiku-20240307"] == 0.5)
        #expect(breakdown["<synthetic>"] == nil) // Should be filtered out
        #expect(breakdown.count == 2) // Only 2 models, synthetic filtered out
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
    
    @Test func testSpendFormatting() throws {
        let summary = SpendSummary(
            todaySpend: 1.2345,
            weekSpend: 0.0067,
            monthSpend: 123.456,
            modelBreakdown: ["claude-3-5-sonnet-20241022": 10.5, "claude-3-5-haiku-20241022": 0.25]
        )
        
        // Test currency formatting
        try #require(summary.formattedTodaySpend.contains("1.23") || summary.formattedTodaySpend.contains("1.2345"))
        try #require(summary.formattedWeekSpend.contains("0.00") || summary.formattedWeekSpend.contains("0.006"))
        try #require(summary.formattedMonthSpend.contains("123.46") || summary.formattedMonthSpend.contains("123.456"))
        
        // Test model breakdown formatting
        let formattedBreakdown = summary.formattedModelBreakdown
        try #require(formattedBreakdown.count == 2)
        
        // Should be sorted by spend amount (descending)
        try #require(formattedBreakdown[0].model == "claude-3-5-sonnet-20241022")
        try #require(formattedBreakdown[1].model == "claude-3-5-haiku-20241022")
    }
    
    @Test func testSmallAmountFormatting() throws {
        let summary = SpendSummary(todaySpend: 0.000123)
        
        // Small amounts should show more decimal places
        let formatted = summary.formattedTodaySpend
        try #require(formatted.contains("0.000123") || formatted.contains("$0.00"))
    }
}

// MARK: - Error Handling Tests

struct ErrorHandlingTests {
    
    @Test func testPricingManagerWithEmptyEntries() throws {
        let pricingManager = PricingManager.shared
        let totalCost = pricingManager.calculateTotalCost(for: [])
        
        try #require(totalCost == 0.0)
    }
    
    @Test func testSpendCalculatorWithEmptyEntries() throws {
        let calculator = SpendCalculator()
        let summary = calculator.calculateSpendSummary(from: [])
        
        try #require(summary.todaySpend == 0.0)
        try #require(summary.weekSpend == 0.0)
        try #require(summary.monthSpend == 0.0)
        try #require(summary.modelBreakdown.isEmpty)
    }
    
    @Test func testJSONLParserWithEmptyContent() throws {
        let parser = JSONLParser()
        let entries = parser.parseJSONLContent("")
        
        try #require(entries.isEmpty)
    }
    
}

