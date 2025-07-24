import Testing
@testable import ClaudeNein
import Foundation

struct SpendAggregationTests {
    @Test func testHourlySpendLength() {
        let store = DataStore(inMemory: true)
        let values = store.hourlySpend(for: Date())
        #expect(values.count == 24)
    }

    @Test func testMonthlySpendLength() {
        let store = DataStore(inMemory: true)
        let values = store.monthlySpend(for: Date())
        #expect(values.count == 12)
    }
}
