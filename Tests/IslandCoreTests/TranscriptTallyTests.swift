import XCTest
@testable import IslandCore

final class TranscriptTallyTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func fixture() throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/claude-transcript.jsonl"))
    }

    // Claude Code writes one line per content block and repeats the message's usage on each, so replies are counted once by message id. Cache reads are left out: every reply re-reads the whole context.
    func testCountsEachReplyOnceExcludingCacheReads() throws {
        var tally = TranscriptTally(calendar: utc)
        tally.ingest(try fixture())
        XCTAssertEqual(tally.tokens(on: "2026-11-18"), 22_314)
        XCTAssertEqual(tally.model, "claude-opus-5-5")
    }

    // The app reads the file in chunks as it grows, so a line can be cut in half between reads.
    func testLineSplitAcrossChunksCountsTheSame() throws {
        let data = try fixture()
        var tally = TranscriptTally(calendar: utc)
        tally.ingest(data.prefix(1000))
        tally.ingest(data.dropFirst(1000))
        XCTAssertEqual(tally.tokens(on: "2026-11-18"), 22_314)
    }

    func testRepliesAreBucketedByTheirLocalDay() {
        let line = #"{"type":"assistant","timestamp":"2026-11-18T23:30:00.000Z","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":9999,"output_tokens":30}}}"#
        var jakarta = Calendar(identifier: .gregorian)
        jakarta.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        var tally = TranscriptTally(calendar: jakarta)
        tally.ingest(Data((line + "\n").utf8))
        XCTAssertEqual(tally.tokens(on: "2026-11-19"), 60)
        XCTAssertEqual(tally.tokens(on: "2026-11-18"), 0)
    }

    // Daily Claude tokens are the sum of each session's tokens for today, set rather than added, so re-reading a transcript never double counts.
    func testDailyClaudeTokensSumSessionsAndResetOnNewDay() {
        var totals = DailyTotals(day: "2026-11-18")
        totals.setClaude(sessionId: "a", tokens: 1000, day: "2026-11-18")
        totals.setClaude(sessionId: "b", tokens: 500, day: "2026-11-18")
        totals.setClaude(sessionId: "a", tokens: 1200, day: "2026-11-18")
        XCTAssertEqual(totals.claudeTokens, 1700)
        totals.setClaude(sessionId: "a", tokens: 50, day: "2026-11-19")
        XCTAssertEqual(totals.claudeTokens, 50)
    }

    func testTranscriptModelFillsAMissingSessionModel() {
        var store = SessionStore()
        store.apply(BridgeEvent(agent: .claude, name: "Stop", ts: 1, payload: .object(["session_id": .string("c1")])))
        store.updateTranscript(sessionId: "c1", model: "claude-opus-5-5")
        XCTAssertEqual(store.sessions["c1"]?.model, "claude-opus-5-5")
    }
}
