import XCTest
@testable import ClaudeNein

/// Integration tests for JSONL parsing and cost calculation using mock data
/// These tests verify our calculations and parsing logic work correctly
final class JSONLParserIntegrationTests: XCTestCase {
    
    private var parser: JSONLParser!
    private var calculator: SpendCalculator!
    private var pricingManager: PricingManager!
    
    override func setUp() {
        super.setUp()
        parser = JSONLParser()
        calculator = SpendCalculator()
        pricingManager = PricingManager.shared
    }
    
    
    /// Test cost calculation accuracy
    func testCostCalculationAccuracy() {
        // Test with mock data instead of relying on specific file paths
        let mockEntries = [
            UsageEntry(
                id: "test1",
                timestamp: ISO8601DateFormatter().date(from: "2025-07-22T10:00:00Z") ?? Date(),
                model: "claude-sonnet-4-20250514",
                tokenCounts: TokenCounts(input: 100, output: 200, cacheCreation: 1000, cacheRead: 5000),
                cost: nil
            ),
            UsageEntry(
                id: "test2", 
                timestamp: ISO8601DateFormatter().date(from: "2025-07-22T11:00:00Z") ?? Date(),
                model: "claude-sonnet-4-20250514",
                tokenCounts: TokenCounts(input: 50, output: 150, cacheCreation: 500, cacheRead: 2000),
                cost: 0.05
            )
        ]
        
        // Test different cost calculation modes
        let costAuto = pricingManager.calculateTotalCost(for: mockEntries, mode: .auto)
        let costCalculate = pricingManager.calculateTotalCost(for: mockEntries, mode: .calculate)
        let costDisplay = pricingManager.calculateTotalCost(for: mockEntries, mode: .display)
        
        // Verify calculations are reasonable
        XCTAssertGreaterThan(costAuto, 0.0, "Auto cost should be positive")
        XCTAssertGreaterThan(costCalculate, 0.0, "Calculate cost should be positive") 
        XCTAssertEqual(costDisplay, 0.05, accuracy: 0.001, "Display cost should only use pre-calculated costs")
        
        print("✅ Cost calculation test passed:")
        print("  Auto: $\(String(format: "%.6f", costAuto))")
        print("  Calculate: $\(String(format: "%.6f", costCalculate))")
        print("  Display: $\(String(format: "%.6f", costDisplay))")
    }
    
    /// Test our caching and deduplication logic
    func testDeduplicationLogic() {
        // Test deduplication with mock JSONL content instead of file dependency
        let jsonlContent = """
        {"type":"assistant","message":{"usage":{"input_tokens":4,"output_tokens":114,"cache_creation_input_tokens":4329,"cache_read_input_tokens":16509},"model":"claude-sonnet-4-20250514","id":"msg_test1"},"requestId":"req_test1","timestamp":"2025-07-21T14:02:17.088Z"}
        {"type":"assistant","message":{"usage":{"input_tokens":4,"output_tokens":114,"cache_creation_input_tokens":4329,"cache_read_input_tokens":16509},"model":"claude-sonnet-4-20250514","id":"msg_test1"},"requestId":"req_test1","timestamp":"2025-07-21T14:02:17.088Z"}
        {"type":"assistant","message":{"usage":{"input_tokens":5,"output_tokens":115,"cache_creation_input_tokens":4330,"cache_read_input_tokens":16510},"model":"claude-sonnet-4-20250514","id":"msg_test2"},"requestId":"req_test2","timestamp":"2025-07-21T14:02:18.088Z"}
        """
        
        let entriesWithDedup = parser.parseJSONLContent(jsonlContent, enableDeduplication: true)
        let entriesWithoutDedup = parser.parseJSONLContent(jsonlContent, enableDeduplication: false)
        
        print("📄 Deduplication test:")
        print("  With dedup: \(entriesWithDedup.count) entries")
        print("  Without dedup: \(entriesWithoutDedup.count) entries")
        print("  Duplicates removed: \(entriesWithoutDedup.count - entriesWithDedup.count)")
        
        // Should have fewer entries with deduplication enabled
        XCTAssertEqual(entriesWithoutDedup.count, 3, "Should parse all 3 lines without deduplication")
        XCTAssertEqual(entriesWithDedup.count, 2, "Should deduplicate identical entries")
        XCTAssertLessThan(entriesWithDedup.count, entriesWithoutDedup.count, "Deduplication should reduce entry count")
    }
    
    /// Test date-based calculations match
    func testDateBasedAggregation() {
        // Test with mock entries spanning multiple dates instead of file dependency
        let entries = [
            UsageEntry(
                id: "day1_1",
                timestamp: ISO8601DateFormatter().date(from: "2025-07-22T10:00:00Z") ?? Date(),
                model: "claude-sonnet-4-20250514",
                tokenCounts: TokenCounts(input: 100, output: 200, cacheCreation: 500, cacheRead: 1000)
            ),
            UsageEntry(
                id: "day1_2",
                timestamp: ISO8601DateFormatter().date(from: "2025-07-22T15:00:00Z") ?? Date(),
                model: "claude-sonnet-4-20250514",
                tokenCounts: TokenCounts(input: 150, output: 250, cacheCreation: 600, cacheRead: 1200)
            ),
            UsageEntry(
                id: "day2_1",
                timestamp: ISO8601DateFormatter().date(from: "2025-07-23T10:00:00Z") ?? Date(),
                model: "claude-sonnet-4-20250514",
                tokenCounts: TokenCounts(input: 80, output: 180, cacheCreation: 400, cacheRead: 800)
            )
        ]
        
        // Group by date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let entriesByDate = Dictionary(grouping: entries) { entry in
            dateFormatter.string(from: entry.timestamp)
        }
        
        var totalCalculatedCost = 0.0
        
        for (date, dateEntries) in entriesByDate.sorted(by: { $0.key < $1.key }) {
            let costCalculate = pricingManager.calculateTotalCost(for: dateEntries, mode: .calculate)
            let inputTokens = dateEntries.reduce(0) { $0 + $1.tokenCounts.input }
            let outputTokens = dateEntries.reduce(0) { $0 + $1.tokenCounts.output }
            let cacheTokens = dateEntries.reduce(0) { $0 + ($1.tokenCounts.cached ?? 0) }
            
            totalCalculatedCost += costCalculate
            
            print("📅 \(date): \(dateEntries.count) entries, input: \(inputTokens), output: \(outputTokens), cache: \(cacheTokens), cost: $\(String(format: "%.6f", costCalculate))")
        }
        
        print("💰 Total calculated cost: $\(String(format: "%.6f", totalCalculatedCost))")
        print("📊 Total days with data: \(entriesByDate.count)")
        print("📈 Total entries: \(entries.count)")
        
        // Verify aggregation works correctly
        XCTAssertEqual(entriesByDate.count, 2, "Should have 2 days of data")
        XCTAssertEqual(entries.count, 3, "Should have 3 total entries")
        XCTAssertGreaterThan(totalCalculatedCost, 0.0, "Should have positive calculated cost")
        
        // Verify July 22 has 2 entries, July 23 has 1 entry
        XCTAssertEqual(entriesByDate["2025-07-22"]?.count, 2, "July 22 should have 2 entries")
        XCTAssertEqual(entriesByDate["2025-07-23"]?.count, 1, "July 23 should have 1 entry")
    }
    
}
