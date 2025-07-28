import Testing
@testable import ClaudeNein
import Foundation

struct SpendAggregationTests {
    @Test func testHourlySpendLength() {
        let store = DataStore(inMemory: true)
        // Use a fixed date to avoid flaky tests that depend on current date
        let fixedDate = Date(timeIntervalSince1970: 1609459200) // 2021-01-01 00:00:00 UTC
        let values = store.hourlySpend(for: fixedDate)
        // should return 24 values, one per hour
        #expect(values.count == 24)
    }

    @Test func testMonthlySpendLength() {
        let store = DataStore(inMemory: true)
        // Use a fixed date to avoid flaky tests that depend on current date
        let fixedDate = Date(timeIntervalSince1970: 1609459200) // 2021-01-01 00:00:00 UTC
        let values = store.monthlySpend(for: fixedDate)
        // should return 12 values, one per month
        #expect(values.count == 12)
    }
}
