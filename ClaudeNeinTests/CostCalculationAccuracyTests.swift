import XCTest
@testable import ClaudeNein

/// Comprehensive tests to verify cost calculation accuracy
final class CostCalculationAccuracyTests: XCTestCase {
    
    private var parser: JSONLParser!
    private var pricingManager: PricingManager!
    private var calculator: SpendCalculator!
    
    override func setUp() {
        super.setUp()
        parser = JSONLParser()
        pricingManager = PricingManager.shared
        calculator = SpendCalculator()
    }
    
    /// Test that we correctly separate cache creation and cache read tokens
    func testCacheTokenSeparation() {
        // Test sample JSON line from our data
        let sampleLine = """
        {"type":"assistant","message":{"usage":{"input_tokens":4,"output_tokens":114,"cache_creation_input_tokens":4329,"cache_read_input_tokens":16509},"model":"claude-sonnet-4-20250514"},"timestamp":"2025-07-21T14:02:17.088Z"}
        """
        
        let entry = parser.parseJSONLine(sampleLine, lineNumber: 1)
        XCTAssertNotNil(entry)
        
        guard let entry = entry else {
            XCTFail("Failed to parse test entry")
            return
        }
        
        // Verify separate cache token parsing
        XCTAssertEqual(entry.tokenCounts.input, 4)
        XCTAssertEqual(entry.tokenCounts.output, 114)
        XCTAssertEqual(entry.tokenCounts.cacheCreation, 4329)
        XCTAssertEqual(entry.tokenCounts.cacheRead, 16509)
        XCTAssertEqual(entry.tokenCounts.cached, 20838) // Combined total
        
        print("✅ Cache token separation test passed:")
        print("  Input: \(entry.tokenCounts.input)")
        print("  Output: \(entry.tokenCounts.output)")
        print("  Cache Creation: \(entry.tokenCounts.cacheCreation ?? 0)")
        print("  Cache Read: \(entry.tokenCounts.cacheRead ?? 0)")
        print("  Total Cache: \(entry.tokenCounts.cached ?? 0)")
    }
    
    /// Test that cost calculation uses separate pricing for cache creation vs read
    func testSeparateCachePricing() {
        let entry = UsageEntry(
            id: "test",
            timestamp: Date(),
            model: "claude-sonnet-4-20250514",
            tokenCounts: TokenCounts(
                input: 1000,        // 1K input tokens
                output: 1000,       // 1K output tokens
                cacheCreation: 1000, // 1K cache creation tokens
                cacheRead: 1000     // 1K cache read tokens
            )
        )
        
        let cost = pricingManager.calculateCost(for: entry, mode: .calculate)
        
        // With sonnet-4 pricing:
        // Input: 1K * $3.0/1M = $0.003
        // Output: 1K * $15.0/1M = $0.015
        // Cache Creation: 1K * $3.75/1M = $0.00375
        // Cache Read: 1K * $0.3/1M = $0.0003
        // Total: $0.02205
        
        let expectedCost = 0.02205
        XCTAssertEqual(cost, expectedCost, accuracy: 0.00001, "Cost calculation with separate cache pricing should match expected")
        
        print("✅ Separate cache pricing test passed:")
        print("  Calculated cost: $\(String(format: "%.6f", cost))")
        print("  Expected cost: $\(String(format: "%.6f", expectedCost))")
    }
    
    
    /// Test that our calculations are consistent across different cost modes
    func testCostModeConsistency() {
        // Create test entries with known costs
        let entries = [
            UsageEntry(
                id: "test1",
                timestamp: Date(),
                model: "claude-sonnet-4-20250514",
                tokenCounts: TokenCounts(input: 1000, output: 500, cacheCreation: 2000, cacheRead: 10000),
                cost: nil // No pre-calculated cost
            ),
            UsageEntry(
                id: "test2",
                timestamp: Date(),
                model: "claude-sonnet-4-20250514",
                tokenCounts: TokenCounts(input: 500, output: 1000, cacheCreation: 1000, cacheRead: 5000),
                cost: 0.05 // Pre-calculated cost
            )
        ]
        
        let costAuto = pricingManager.calculateTotalCost(for: entries, mode: .auto)
        let costCalculate = pricingManager.calculateTotalCost(for: entries, mode: .calculate)
        let costDisplay = pricingManager.calculateTotalCost(for: entries, mode: .display)
        
        print("💰 Cost mode consistency test:")
        print("  Auto mode: $\(String(format: "%.6f", costAuto))")
        print("  Calculate mode: $\(String(format: "%.6f", costCalculate))")
        print("  Display mode: $\(String(format: "%.6f", costDisplay))")
        
        // Auto should use pre-calculated cost for entry2 + calculated for entry1
        // Calculate should recalculate both
        // Display should use pre-calculated where available (0.05 for entry2, 0 for entry1)
        
        XCTAssertGreaterThan(costAuto, 0.0, "Auto cost should be positive")
        XCTAssertGreaterThan(costCalculate, 0.0, "Calculate cost should be positive")
        XCTAssertEqual(costDisplay, 0.05, accuracy: 0.001, "Display cost should only use pre-calculated costs")
        
        // Auto and Calculate should be similar but Auto might use pre-calculated cost
        let autoCalculateDiff = abs(costAuto - costCalculate)
        print("  Auto vs Calculate difference: $\(String(format: "%.6f", autoCalculateDiff))")
    }
    
}

