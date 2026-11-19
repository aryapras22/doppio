import XCTest
@testable import IslandCore

final class SessionStoreTests: XCTestCase {
    private func claude(_ name: String, _ extra: [String: JSONValue] = [:], ts: Double = 100, pid: Int32? = nil) -> BridgeEvent {
        var p: [String: JSONValue] = ["session_id": .string("c1"), "cwd": .string("/work/web-store")]
        p.merge(extra) { $1 }
        return BridgeEvent(agent: .claude, name: name, ts: ts, pid: pid, payload: .object(p))
    }

    private func agy(_ name: String, _ extra: [String: JSONValue] = [:], ts: Double = 100) -> BridgeEvent {
        var p: [String: JSONValue] = ["conversationId": .string("a1"), "workspacePaths": .array([.string("/work/agent-island")]), "modelName": .string("gemini-4-hydrogen-high")]
        p.merge(extra) { $1 }
        return BridgeEvent(agent: .agy, name: name, ts: ts, payload: .object(p))
    }

    func testClaudeToolCycleAndPermissionRequest() {
        var store = SessionStore()
        store.apply(claude("UserPromptSubmit"))
        XCTAssertEqual(store.sessions["c1"]?.state, .working)
        XCTAssertEqual(store.sessions["c1"]?.project, "web-store")

        store.apply(claude("PreToolUse", ["tool_name": .string("Bash")]))
        XCTAssertEqual(store.sessions["c1"]?.state, .runningTool)
        XCTAssertEqual(store.sessions["c1"]?.currentTool, "Bash")

        store.apply(claude("PermissionRequest"))
        XCTAssertEqual(store.sessions["c1"]?.state, .needsYou)
        XCTAssertNil(store.sessions["c1"]?.currentTool)

        store.apply(claude("Stop"))
        XCTAssertEqual(store.sessions["c1"]?.state, .idle)
    }

    func testRemoveDropsSessionUntilItsNextEvent() {
        var store = SessionStore()
        store.apply(claude("Stop", pid: 42))
        store.remove(id: "c1")
        XCTAssertNil(store.sessions["c1"])

        store.apply(claude("UserPromptSubmit", ts: 200))
        XCTAssertEqual(store.sessions["c1"]?.state, .working)
        XCTAssertEqual(store.sessions["c1"]?.startedAt, 200)
    }

    func testAgyStopOnlyIdlesWhenFullyIdleAndFailsOnError() {
        var store = SessionStore()
        store.apply(agy("PreInvocation"))
        store.apply(agy("Stop", ["fullyIdle": .bool(true), "error": .string("")]))
        XCTAssertEqual(store.sessions["a1"]?.state, .idle)
        store.apply(agy("PreInvocation"))
        store.apply(agy("Stop", ["fullyIdle": .bool(false)]))
        XCTAssertEqual(store.sessions["a1"]?.state, .working)

        store.apply(agy("Stop", ["fullyIdle": .bool(true)]))
        XCTAssertEqual(store.sessions["a1"]?.state, .idle)

        store.apply(agy("Stop", ["error": .string("boom")]))
        XCTAssertEqual(store.sessions["a1"]?.state, .failed)
        XCTAssertEqual(store.sessions["a1"]?.model, "gemini-4-hydrogen-high")
    }

    func testStatusLineFillsContextWithoutChangingState() {
        var store = SessionStore()
        store.apply(claude("PreToolUse", ["tool_name": .string("Edit")]))
        store.apply(claude("StatusLine", [
            "model": .object(["id": .string("claude-opus-5-5")]),
            "context_window": .object(["used_percentage": .number(34), "total_input_tokens": .number(60_000), "total_output_tokens": .number(8_000)]),
        ]))
        let s = store.sessions["c1"]
        XCTAssertEqual(s?.state, .runningTool)
        XCTAssertEqual(s?.model, "claude-opus-5-5")
        XCTAssertEqual(s?.contextPercent, 34)
        XCTAssertEqual(s?.totalTokens, 68_000)
    }

    func testSweepEndsDeadPidThenRemovesAfterLinger() {
        var store = SessionStore()
        store.apply(claude("UserPromptSubmit", pid: 4242))
        store.sweep(now: 200) { _ in true }
        XCTAssertEqual(store.sessions["c1"]?.state, .working)

        store.sweep(now: 200) { _ in false }
        XCTAssertEqual(store.sessions["c1"]?.state, .ended)

        store.sweep(now: 259) { _ in false }
        XCTAssertNotNil(store.sessions["c1"])
        store.sweep(now: 261) { _ in false }
        XCTAssertNil(store.sessions["c1"])
    }

    func testSessionWithoutPidIsNeverSweptAsDead() {
        var store = SessionStore()
        store.apply(claude("UserPromptSubmit"))
        store.sweep(now: 500) { _ in false }
        XCTAssertEqual(store.sessions["c1"]?.state, .working)
    }

    func testBridgeEventRoundTripsThroughJSON() throws {
        let e = claude("PreToolUse", ["tool_name": .string("Bash")], pid: 7)
        let decoded = try JSONDecoder().decode(BridgeEvent.self, from: JSONEncoder().encode(e))
        XCTAssertEqual(decoded, e)
    }
}

final class BuilderRunTests: XCTestCase {
    private func ev(_ name: String, _ p: [String: JSONValue], ts: Double = 100) -> BridgeEvent {
        var payload = p
        payload["conversationId"] = .string("a1")
        return BridgeEvent(agent: .agy, name: name, ts: ts, payload: .object(payload))
    }

    func testLinkAttachesBuilderToParentAndResultMakesCupReady() {
        var store = SessionStore()
        store.apply(ev("link", ["parent": .string("c1"), "task": .string("T3"), "title": .string("coupon rules"), "pid": .number(55)]))
        XCTAssertEqual(store.sessions["a1"]?.parentId, "c1")
        XCTAssertEqual(store.sessions["a1"]?.taskId, "T3")

        store.apply(ev("Result", ["status": .string("SUCCESS"), "inputTokens": .number(5000)], ts: 200))
        XCTAssertEqual(store.sessions["a1"]?.cupReady, true)
        XCTAssertEqual(store.sessions["a1"]?.state, .idle)

        store.apply(ev("Stop", ["fullyIdle": .bool(true)], ts: 201))
        XCTAssertEqual(store.sessions["a1"]?.cupReady, true)
    }

    func testFinishedBuilderIsNotEndedByDeadPidButIsRemovedAfterLinger() {
        var store = SessionStore()
        store.apply(ev("link", ["pid": .number(55)]))
        store.apply(ev("Result", ["status": .string("SUCCESS")], ts: 200))
        store.sweep(now: 250) { _ in false }
        XCTAssertEqual(store.sessions["a1"]?.state, .idle)
        store.sweep(now: 501) { _ in false }
        XCTAssertNil(store.sessions["a1"])
    }

    func testStepUpdateSetsToolAndErrorResultFails() {
        var store = SessionStore()
        store.apply(ev("StepUpdate", ["tool": .string("run_command"), "contextPercent": .number(12)]))
        XCTAssertEqual(store.sessions["a1"]?.state, .runningTool)
        XCTAssertEqual(store.sessions["a1"]?.currentTool, "run_command")
        store.apply(ev("Result", ["status": .string("ERROR")], ts: 200))
        XCTAssertEqual(store.sessions["a1"]?.state, .failed)
        XCTAssertEqual(store.sessions["a1"]?.cupReady, false)
    }
}

final class ParsingTests: XCTestCase {
    func testPacketRequiresAcceptanceAndJoinsModelWithEffort() throws {
        let text = "---\nid: T3\nmodel: gemini-4-argon\neffort: xhigh\nacceptance: npm test -- cart\nscope: [src/cart/**, src/api/cart.ts]\n---\n# Goal\nx"
        let packet = try Packet.parse(text)
        XCTAssertEqual(packet.modelSlug, "gemini-4-argon-xhigh")
        XCTAssertEqual(packet.scope, ["src/cart/**", "src/api/cart.ts"])
        XCTAssertThrowsError(try Packet.parse("---\nid: T4\n---\nbody")) { XCTAssertEqual($0 as? Packet.ParseError, .missing("acceptance")) }
        XCTAssertEqual(Packet.slug(model: "gemini-4-hydrogen-high", effort: "xhigh"), "gemini-4-hydrogen-high")
    }

    private func fixture(_ name: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)"), encoding: .utf8)
    }

    func testRealAgyStreamTalliesTokensToolsAndResult() throws {
        let events = try fixture("agy-stream.jsonl").split(separator: "\n").compactMap { StreamEvent(line: String($0)) }
        XCTAssertEqual(events.count, 8)
        XCTAssertEqual(events.first?.type, "init")
        XCTAssertEqual(events.compactMap(\.conversationId).first, "f0daa944-dd06-4b71-945c-eb22d86f5f85")
        XCTAssertEqual(events.compactMap(\.activeTool), ["write_file"])

        var tally = RunTally()
        events.forEach { tally.add($0) }
        let result = try XCTUnwrap(events.last)
        XCTAssertEqual(result.status, "SUCCESS")
        XCTAssertEqual(result.text, "DONE\n")
        XCTAssertEqual(result.turns, 1)
        XCTAssertEqual(tally.inputTokens, 13582)
        XCTAssertEqual(tally.outputTokens, 108)
        // Last turn: 2230 fresh input + 9298 cached, over the Gemini 4 window.
        XCTAssertEqual(try XCTUnwrap(tally.contextPercent(window: 1_048_576)), 11528.0 / 1_048_576 * 100, accuracy: 0.0001)
    }

    func testCheckpointStepsAreCounted() throws {
        var tally = RunTally()
        tally.add(try XCTUnwrap(StreamEvent(line: #"{"event":"step_update","step_update":{"conversation_id":"x","step_type":"checkpoint","state":"DONE"}}"#)))
        XCTAssertEqual(tally.checkpoints, 1)
    }

    func testRealAgyStopPayloadIsIdleNotFailed() throws {
        let payload = try JSONDecoder().decode(JSONValue.self, from: Data(fixture("agy-Stop.json").utf8))
        var store = SessionStore()
        store.apply(BridgeEvent(agent: .agy, name: "Stop", ts: 1, payload: payload))
        XCTAssertEqual(store.sessions.values.first?.state, .idle)
        XCTAssertEqual(store.sessions.values.first?.project, "ws1")
        XCTAssertEqual(store.sessions.values.first?.model, "gemini-4-hydrogen-low")
    }

    func testRealClaudeHookPayloadsDriveTheStore() throws {
        var store = SessionStore()
        for (file, name) in [("claude-PreToolUse.json", "PreToolUse"), ("claude-Stop.json", "Stop")] {
            let payload = try JSONDecoder().decode(JSONValue.self, from: Data(fixture(file).utf8))
            store.apply(BridgeEvent(agent: .claude, name: name, ts: 1, pid: 3911, payload: payload))
            if name == "PreToolUse" {
                XCTAssertEqual(store.sessions.values.first?.state, .runningTool)
                XCTAssertEqual(store.sessions.values.first?.currentTool, "Bash")
            }
        }
        XCTAssertEqual(store.sessions.values.first?.state, .idle)
        XCTAssertEqual(store.sessions.values.first?.project, "cl")
    }
}
