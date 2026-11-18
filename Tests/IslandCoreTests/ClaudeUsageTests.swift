import XCTest
@testable import IslandCore

final class ClaudeUsageTests: XCTestCase {
    private func envelope(_ text: String) -> Data {
        try! JSONEncoder().encode(["result": text])
    }

    func testParsesRealUsageCommandOutput() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/claude-usage.json"))
        let limits = try XCTUnwrap(ClaudeUsage.parse(data, now: 1_794_960_000))
        XCTAssertEqual(limits.fiveHour, RateLimitWindow(usedPercentage: 73, resetsAt: 1_794_988_740))
        XCTAssertEqual(limits.sevenDay, RateLimitWindow(usedPercentage: 99, resetsAt: 1_794_988_740))
    }

    // The text names a month and day but no year, so a date already past means next year.
    func testResetDateEarlierThanNowRollsIntoNextYear() throws {
        let text = "Current session: 5% used · resets Jan 2 at 9:00am (UTC)"
        let limits = try XCTUnwrap(ClaudeUsage.parse(envelope(text), now: 1_798_675_200))
        XCTAssertEqual(limits.fiveHour?.resetsAt, 1_798_880_400)
        XCTAssertNil(limits.sevenDay)
    }

    func testResetWithOnlyATimeMeansItsNextOccurrence() throws {
        let text = "Current week (all models): 40% used · resets 4:30pm (UTC)"
        let limits = try XCTUnwrap(ClaudeUsage.parse(envelope(text), now: 1_794_996_000))
        XCTAssertEqual(limits.sevenDay, RateLimitWindow(usedPercentage: 40, resetsAt: 1_795_019_400))
    }

    // Claude Code drops the minutes on the hour: "resets Nov 18 at 3pm".
    func testResetTimeWithoutMinutesParses() throws {
        let text = "Current session: 77% used · resets Nov 18 at 3pm (Asia/Jakarta)\nCurrent week (all models): 100% used · resets 3pm (Asia/Jakarta)"
        let limits = try XCTUnwrap(ClaudeUsage.parse(envelope(text), now: 1_794_960_000))
        XCTAssertEqual(limits.fiveHour, RateLimitWindow(usedPercentage: 77, resetsAt: 1_794_988_800))
        XCTAssertEqual(limits.sevenDay, RateLimitWindow(usedPercentage: 100, resetsAt: 1_794_988_800))
    }

    func testOutputWithoutPlanLimitsGivesNil() {
        XCTAssertNil(ClaudeUsage.parse(envelope("You are using an API key; plan limits do not apply."), now: 1_794_960_000))
        XCTAssertNil(ClaudeUsage.parse(Data("not json".utf8), now: 1_794_960_000))
    }

    func testPolledLimitsReplaceStoredOnes() {
        var store = SessionStore()
        let limits = RateLimits(fiveHour: RateLimitWindow(usedPercentage: 73, resetsAt: 1), sevenDay: nil)
        store.updateRateLimits(limits)
        XCTAssertEqual(store.rateLimits, limits)
    }
}
