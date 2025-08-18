import Testing
import Foundation
@testable import ClaudeNein

/// Integration tests for PricingManager's unknown model handling
struct PricingManagerIntegrationTests {
    
    /// Test that calculateCostFromTokens handles unknown models correctly
    @Test func testUnknownModelCostCalculation() async {
        let pricingManager = PricingManager.shared
        
        // Create an entry with an unknown model
        let unknownEntry = UsageEntry(
            id: "unknown-1",
            timestamp: Date(),
            model: "claude-ultra-future-model-xyz", // Model that doesn't exist
            tokenCounts: TokenCounts(input: 1000, output: 2000),
            cost: nil
        )
        
        // Calculate cost for unknown model - should return 0
        let cost = pricingManager.calculateCost(for: unknownEntry, mode: .calculate)
        #expect(cost == 0.0, "Unknown model should return 0 cost")
        
        // The coordinator should have been triggered internally
        // We can't directly test this without accessing private properties
        // but we can verify the behavior is correct
    }
    
    /// Test that known models calculate costs correctly
    @Test func testKnownModelCostCalculation() {
        let pricingManager = PricingManager.shared
        
        // Use a model we know exists in bundled data
        let knownEntry = UsageEntry(
            id: "known-1",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: TokenCounts(input: 1000, output: 2000),
            cost: nil
        )
        
        // Calculate cost - should be non-zero
        let cost = pricingManager.calculateCost(for: knownEntry, mode: .calculate)
        #expect(cost > 0, "Known model should return non-zero cost")
        
        // Verify the calculation is correct
        // claude-3-5-sonnet-20241022: input=$3/M, output=$15/M
        let inputCost = 1000.0 * 3.0 / 1_000_000.0
        let outputCost = 2000.0 * 15.0 / 1_000_000.0
        let expectedCost = inputCost + outputCost
        #expect(cost == expectedCost, "Cost calculation should be correct")
    }
    
    /// Test cost calculation with cache tokens
    @Test func testCostCalculationWithCacheTokens() {
        let pricingManager = PricingManager.shared
        
        let entryWithCache = UsageEntry(
            id: "cache-1",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: TokenCounts(
                input: 1000,
                output: 2000,
                cacheCreation: 500,
                cacheRead: 300
            ),
            cost: nil
        )
        
        let cost = pricingManager.calculateCost(for: entryWithCache, mode: .calculate)
        #expect(cost > 0, "Should calculate cost including cache tokens")
        
        // Verify calculation includes cache costs
        // claude-3-5-sonnet-20241022: 
        // input=$3/M, output=$15/M, cacheCreation=$3.75/M, cacheRead=$0.3/M
        let inputCost = 1000.0 * 3.0 / 1_000_000.0
        let outputCost = 2000.0 * 15.0 / 1_000_000.0
        let cacheCreationCost = 500.0 * 3.75 / 1_000_000.0
        let cacheReadCost = 300.0 * 0.3 / 1_000_000.0
        let expectedCost = inputCost + outputCost + cacheCreationCost + cacheReadCost
        #expect(cost == expectedCost, "Cache token costs should be included")
    }
    
    /// Test that multiple entries are calculated correctly
    @Test func testCalculateTotalCostForMultipleEntries() {
        let pricingManager = PricingManager.shared
        
        let entries = [
            UsageEntry(
                id: "1",
                timestamp: Date(),
                model: "claude-3-5-sonnet-20241022",
                tokenCounts: TokenCounts(input: 100, output: 200),
                cost: nil
            ),
            UsageEntry(
                id: "2",
                timestamp: Date(),
                model: "claude-3-5-haiku-20241022",
                tokenCounts: TokenCounts(input: 500, output: 1000),
                cost: nil
            ),
            UsageEntry(
                id: "3",
                timestamp: Date(),
                model: "unknown-model-xyz", // Unknown model
                tokenCounts: TokenCounts(input: 1000, output: 2000),
                cost: nil
            )
        ]
        
        let totalCost = pricingManager.calculateTotalCost(for: entries, mode: .calculate)
        #expect(totalCost > 0, "Should calculate total cost for known models")
        
        // The unknown model should contribute 0 to the total
        let knownModelsCost = pricingManager.calculateCost(for: entries[0], mode: .calculate) +
                             pricingManager.calculateCost(for: entries[1], mode: .calculate)
        #expect(totalCost == knownModelsCost, "Unknown model should not add to total cost")
    }
    
    /// Test the different cost modes
    @Test func testCostModes() {
        let pricingManager = PricingManager.shared
        
        // Entry with precalculated cost
        let entryWithCost = UsageEntry(
            id: "1",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: TokenCounts(input: 100, output: 200),
            cost: 10.0 // Precalculated cost
        )
        
        // Display mode should use precalculated cost
        let displayCost = pricingManager.calculateCost(for: entryWithCost, mode: .display)
        #expect(displayCost == 10.0, "Display mode should use precalculated cost")
        
        // Calculate mode should ignore precalculated cost
        let calculateCost = pricingManager.calculateCost(for: entryWithCost, mode: .calculate)
        #expect(calculateCost != 10.0, "Calculate mode should recalculate from tokens")
        #expect(calculateCost > 0, "Calculate mode should return non-zero for known model")
        
        // Auto mode should use precalculated when available
        let autoCost = pricingManager.calculateCost(for: entryWithCost, mode: .auto)
        #expect(autoCost == 10.0, "Auto mode should use precalculated cost when available")
        
        // Entry without precalculated cost
        let entryWithoutCost = UsageEntry(
            id: "2",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: TokenCounts(input: 100, output: 200),
            cost: nil
        )
        
        // Auto mode should calculate when no precalculated cost
        let autoCalculatedCost = pricingManager.calculateCost(for: entryWithoutCost, mode: .auto)
        #expect(autoCalculatedCost == calculateCost, "Auto mode should calculate when no precalculated cost")
    }
    
    /// Test that pricing data source is correctly identified
    @Test func testPricingDataSource() async {
        let pricingManager = PricingManager.shared
        
        // Initial state might be bundled, cache, or API depending on app state
        let currentSource = pricingManager.getCurrentDataSource()
        // Verify we have one of the valid data sources
        #expect([PricingDataSource.api, .cache, .bundled].contains(currentSource), "Should have a valid data source")
        
        // Get current pricing
        let pricing = pricingManager.getCurrentPricing()
        #expect(pricing.models.count > 0, "Should have some pricing data")
        
        // Verify bundled data has expected models
        if currentSource == .bundled {
            #expect(pricing.models["claude-3-5-sonnet-20241022"] != nil, "Bundled data should have known models")
            #expect(pricing.models["claude-3-opus-20240229"] != nil, "Bundled data should have known models")
        }
    }
    
    /// Test that bundled pricing includes cache prices
    @Test func testBundledPricingHasCachePrices() {
        let pricingManager = PricingManager.shared
        let pricing = pricingManager.getCurrentPricing()
        
        // Check a known model has cache prices
        if let sonnetPricing = pricing.models["claude-3-5-sonnet-20241022"] {
            #expect(sonnetPricing.cacheCreationPrice != nil, "Should have cache creation price")
            #expect(sonnetPricing.cacheReadPrice != nil, "Should have cache read price")
            #expect(sonnetPricing.cacheCreationPrice! > sonnetPricing.inputPrice, "Cache creation should be more expensive than input")
            #expect(sonnetPricing.cacheReadPrice! < sonnetPricing.inputPrice, "Cache read should be cheaper than input")
        }
    }
}

// MARK: - Error Handling Tests

struct PricingErrorHandlingTests {
    
    @Test func testPricingManagerWithEmptyEntries() {
        let pricingManager = PricingManager.shared
        let totalCost = pricingManager.calculateTotalCost(for: [], mode: .auto)
        #expect(totalCost == 0.0, "Empty array should return 0 cost")
    }
    
    @Test func testEntryWithZeroTokens() {
        let pricingManager = PricingManager.shared
        let entry = UsageEntry(
            id: "zero",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: TokenCounts(input: 0, output: 0),
            cost: nil
        )
        
        let cost = pricingManager.calculateCost(for: entry, mode: .calculate)
        #expect(cost == 0.0, "Zero tokens should result in zero cost")
    }
    
    @Test func testEntryWithOnlyInputTokens() {
        let pricingManager = PricingManager.shared
        let entry = UsageEntry(
            id: "input-only",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: TokenCounts(input: 1000, output: 0),
            cost: nil
        )
        
        let cost = pricingManager.calculateCost(for: entry, mode: .calculate)
        #expect(cost > 0, "Input-only should still have cost")
        #expect(cost == 1000 * 3.0 / 1_000_000, "Should only charge for input tokens")
    }
    
    @Test func testEntryWithOnlyOutputTokens() {
        let pricingManager = PricingManager.shared
        let entry = UsageEntry(
            id: "output-only",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: TokenCounts(input: 0, output: 1000),
            cost: nil
        )
        
        let cost = pricingManager.calculateCost(for: entry, mode: .calculate)
        #expect(cost > 0, "Output-only should still have cost")
        #expect(cost == 1000 * 15.0 / 1_000_000, "Should only charge for output tokens")
    }
}
