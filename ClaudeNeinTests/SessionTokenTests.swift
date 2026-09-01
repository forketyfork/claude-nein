import Testing
import Foundation
@testable import ClaudeNein

struct SessionTokenTests {
    @Test func testTokensUsedInLastHours() async {
        let store = DataStore(inMemory: true)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let recent = UsageEntry(
            timestamp: now.addingTimeInterval(-3600),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: TokenCounts(input: 100, output: 50),
            cost: 0.1
        )
        let old = UsageEntry(
            timestamp: now.addingTimeInterval(-6 * 3600),
            model: "claude-3-5-sonnet-20241022",
            tokenCounts: TokenCounts(input: 200, output: 100),
            cost: 0.2
        )

        await store.upsertEntries([recent, old])
        let total = store.tokensUsed(inLast: 5, now: now)
        #expect(total == 150) // 100 + 50 from recent entry only
    }
}
