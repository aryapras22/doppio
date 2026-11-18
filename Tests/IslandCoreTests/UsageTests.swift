import XCTest
@testable import IslandCore

final class UsageTests: XCTestCase {
    private func status(_ session: String, _ p: [String: JSONValue]) -> BridgeEvent {
        var payload = p
        payload["session_id"] = .string(session)
        return BridgeEvent(agent: .claude, name: "StatusLine", ts: 1, payload: .object(payload))
    }

    private func limits(fiveHour: Double?, sevenDay: Double?) -> JSONValue {
        var o: [String: JSONValue] = [:]
        if let fiveHour { o["five_hour"] = .object(["used_percentage": .number(fiveHour), "resets_at": .number(1_738_425_600)]) }
        if let sevenDay { o["seven_day"] = .object(["used_percentage": .number(sevenDay), "resets_at": .number(1_738_857_600)]) }
        return .object(o)
    }

    func testStatusLineCarriesPlanLimitsAndSessionCost() {
        var store = SessionStore()
        store.apply(status("c1", ["cost": .object(["total_cost_usd": .number(1.25)]), "rate_limits": limits(fiveHour: 23.5, sevenDay: 41.2)]))
        XCTAssertEqual(store.sessions["c1"]?.costUSD, 1.25)
        XCTAssertEqual(store.rateLimits?.fiveHour, RateLimitWindow(usedPercentage: 23.5, resetsAt: 1_738_425_600))
        XCTAssertEqual(store.rateLimits?.sevenDay?.usedPercentage, 41.2)
    }

    // API-key sessions send no rate_limits and must not erase what a subscription session reported; Claude Code drops a window after it resets, so a present object replaces the old one whole.
    func testLimitsSurviveSessionsWithoutThemAndAreReplacedWhole() {
        var store = SessionStore()
        store.apply(status("c1", ["rate_limits": limits(fiveHour: 23.5, sevenDay: 41.2)]))
        store.apply(status("c2", ["cost": .object(["total_cost_usd": .number(0.4)])]))
        XCTAssertEqual(store.rateLimits?.fiveHour?.usedPercentage, 23.5)
        store.apply(status("c1", ["rate_limits": limits(fiveHour: nil, sevenDay: 44)]))
        XCTAssertNil(store.rateLimits?.fiveHour)
        XCTAssertEqual(store.rateLimits?.sevenDay?.usedPercentage, 44)
    }

    func testDailyAgyTokensKeepEachRunsLargestCount() {
        var totals = DailyTotals(day: "2026-11-18")
        totals.setAgy(sessionId: "a", tokens: 5000, day: "2026-11-18")
        totals.setAgy(sessionId: "a", tokens: 7000, day: "2026-11-18")
        totals.setAgy(sessionId: "a", tokens: 0, day: "2026-11-18")
        totals.setAgy(sessionId: "b", tokens: 1000, day: "2026-11-18")
        XCTAssertEqual(totals.agyTokens, 8000)
        XCTAssertEqual(totals.claudeTokens, 0)
    }

    func testDailyTotalsStartOverOnANewDay() {
        var totals = DailyTotals(day: "2026-11-18")
        totals.setAgy(sessionId: "a", tokens: 5000, day: "2026-11-18")
        totals.setAgy(sessionId: "b", tokens: 300, day: "2026-11-19")
        XCTAssertEqual(totals.day, "2026-11-19")
        XCTAssertEqual(totals.agyTokens, 300)
    }
}
