import Testing
import Foundation
@testable import ClaudeNein

struct SimpleTests {
    
    @Test func testTokenCounts() {
        let tokens = TokenCounts(input: 100, output: 200, cached: 50)
        #expect(tokens.total == 350)
        
        let tokensNoCached = TokenCounts(input: 100, output: 200)
        #expect(tokensNoCached.total == 300)
    }
    
    @Test func testUsageEntry() throws {
        let entry = UsageEntry(
            id: "test-1",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: TokenCounts(input: 100, output: 200),
            cost: 1.5
        )
        
        try #require(entry.id == "test-1")
        try #require(entry.model == "claude-3-5-sonnet-20241022")
        try #require(entry.cost == 1.5)
    }
    
    @Test func testCostModes() {
        let pricingManager = PricingManager.shared
        let entry = UsageEntry(
            id: "test-1",
            timestamp: Date(),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: TokenCounts(input: 100, output: 200),
            cost: 2.5
        )
        
        // Test display mode
        let displayCost = pricingManager.calculateCost(for: entry, mode: .display)
        #expect(displayCost == 2.5)
        
        // Test auto mode
        let autoCost = pricingManager.calculateCost(for: entry, mode: .auto)
        #expect(autoCost == 2.5)
    }
}