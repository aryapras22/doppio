import CoreGraphics
import XCTest
@testable import IslandCore

final class AgyUsageTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)"))
    }

    func testParsesRealUsageCommandOutput() throws {
        let buckets = try AgyUsage.parse(fixture("agy-usage.json"))
        XCTAssertEqual(buckets.map(\.id), ["gemini-weekly", "gemini-5h", "3p-weekly", "3p-5h", "gemini-argon-wtu-weekly"])
        let fiveHour = try XCTUnwrap(buckets.first { $0.id == "gemini-5h" })
        XCTAssertEqual(fiveHour.group, "Gemini Models")
        XCTAssertEqual(fiveHour.window, .fiveHour)
        XCTAssertEqual(fiveHour.usedPercentage, (1 - 0.8763156533241272) * 100, accuracy: 0.0001)
        XCTAssertEqual(fiveHour.resetsAt, 1_794_984_478)
        XCTAssertEqual(buckets.last?.window, .weekly)
    }

    func testParseRejectsOutputWithoutUsageData() {
        XCTAssertThrowsError(try AgyUsage.parse(Data(#"{"status":"ERROR","response":"not signed in"}"#.utf8)))
    }

    // Builders run on Gemini, so its group always shows; other groups only once they have been used. Within a group 5-hour comes first, as in the design.
    func testVisibleBucketsKeepGeminiAndAnyUsedGroup() throws {
        var buckets = try AgyUsage.parse(fixture("agy-usage.json"))
        XCTAssertEqual(AgyUsage.visible(buckets).map(\.id), ["gemini-5h", "gemini-weekly"])
        buckets[4].usedPercentage = 3
        XCTAssertEqual(AgyUsage.visible(buckets).map(\.id), ["gemini-5h", "gemini-weekly", "gemini-argon-wtu-weekly"])
    }

    func testLabelsAreShortGroupAndWindow() throws {
        let labels = try AgyUsage.parse(fixture("agy-usage.json")).map(AgyUsage.label)
        XCTAssertEqual(labels, ["WEEKLY", "5-HOUR", "CLAUDE/GPT WEEKLY", "CLAUDE/GPT 5-HOUR", "ARGON WEEKLY"])
    }

    func testResetTextCountsDownUnderADayThenShowsWeekdayAndTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now: Double = 1_794_981_600
        XCTAssertEqual(UsageFormat.resetText(resetsAt: now + 2 * 3600 + 14 * 60 + 20, now: now, calendar: calendar), "resets in 2h 14m")
        XCTAssertEqual(UsageFormat.resetText(resetsAt: now + 14 * 60 + 30, now: now, calendar: calendar), "resets in 14m")
        XCTAssertEqual(UsageFormat.resetText(resetsAt: 1_795_424_400, now: now, calendar: calendar), "resets Mon 09:00")
        XCTAssertEqual(UsageFormat.resetText(resetsAt: now - 5, now: now, calendar: calendar), "resets now")
    }

    func testBarFillRoundsToTwentySegmentsAndClamps() {
        XCTAssertEqual(UsageFormat.filledSegments(percentage: 42), 8)
        XCTAssertEqual(UsageFormat.filledSegments(percentage: 18), 4)
        XCTAssertEqual(UsageFormat.filledSegments(percentage: 0), 0)
        XCTAssertEqual(UsageFormat.filledSegments(percentage: 130), 20)
    }

    func testRunningAgyUsageCreatesNoSession() {
        var store = SessionStore()
        store.apply(BridgeEvent(agent: .agy, name: "SessionStart", ts: 1, payload: .object(["conversationId": .string("")])))
        XCTAssertTrue(store.sessions.isEmpty)
    }

    // The usage block replaces the old one-line footer: one header line per section plus one line per bar.
    func testExpandedHeightGrowsWithUsageSectionsAndBars() {
        let notch = CGSize(width: 185, height: 32)
        let usage = UsageLayout(sections: 2, bars: 4)
        // 32 notch + 36 header + 6 * 44 rows + 8 gap + 2 * 22 sections + 4 * 18 bars + 10 padding; written as a literal because the sum times out the type checker.
        XCTAssertEqual(IslandGeometry.shapeSize(mode: .expanded, notch: notch, rowCount: 6, usage: usage).height, 466)
        XCTAssertEqual(IslandGeometry.shapeSize(mode: .expanded, notch: notch, rowCount: 6, usage: UsageLayout(sections: 1, bars: 0)),
                       IslandGeometry.shapeSize(mode: .expanded, notch: notch, rowCount: 6))
        XCTAssertEqual(IslandGeometry.panelSize(notch: notch, rowCount: 6, usage: usage).height, 466)
    }
}
