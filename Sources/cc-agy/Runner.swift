import Darwin
import Foundation
import IslandCore

/// The detached half of `start` and `continue`: owns one agy process, mirrors its stream to the app, and writes the result block.
func runBuilder(task: String, promptFile: String, resume: Bool) throws {
    guard var record = RunStore.load(task) else { throw Failure(message: "no run record for \(task)") }
    let dir = RunStore.dir(for: task)
    let prompt = try String(contentsOfFile: promptFile, encoding: .utf8)
    record.runnerPid = getpid()
    RunStore.save(record)

    let slug = Packet.slug(model: record.model, effort: record.effort)
    var agyArgs = ["-p", prompt, "--output-format", "stream-json", "--model", slug, "--agent", "builder",
                   "--dangerously-skip-permissions", "--sandbox", "--print-timeout", "30m"]
    if resume, let id = record.conversationId { agyArgs += ["--conversation", id] }

    let bin = ProcessInfo.processInfo.environment["CC_AGY_BIN"] ?? "agy"
    let usePty = ProcessInfo.processInfo.environment["CC_AGY_PTY"] == "1"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = usePty ? ["script", "-q", "/dev/null", bin] + agyArgs : [bin] + agyArgs
    process.currentDirectoryURL = URL(fileURLWithPath: record.worktree)
    var env = ProcessInfo.processInfo.environment
    env["AGENT_ISLAND_TASK"] = task
    env["AGENT_ISLAND_PARENT"] = record.parent ?? ""
    process.environment = env
    let out = Pipe()
    process.standardOutput = out
    process.standardError = FileHandle(forWritingAtPath: dir.appendingPathComponent("stderr.log").path)
        ?? { FileManager.default.createFile(atPath: dir.appendingPathComponent("stderr.log").path, contents: nil); return FileHandle.nullDevice }()
    try process.run()
    record.agyPid = process.processIdentifier
    RunStore.save(record)

    let streamLog = dir.appendingPathComponent("stream.jsonl")
    if !FileManager.default.fileExists(atPath: streamLog.path) { FileManager.default.createFile(atPath: streamLog.path, contents: nil) }
    let log = try FileHandle(forWritingTo: streamLog)
    log.seekToEndOfFile()

    var tally = RunTally()
    var finalText: String?
    var resultStatus: String?
    var turns: Int?
    var linked = false
    let window = ContextWindows.size(for: slug)
    var buffer = Data()

    func handle(line: String) {
        log.write(Data((line + "\n").utf8))
        guard let event = StreamEvent(line: line) else { return }
        tally.add(event)
        if !linked, let id = event.conversationId {
            record.conversationId = id
            RunStore.save(record)
            if let link = record.linkEvent { BridgeClient.send(link) }
            linked = true
        }
        guard let id = record.conversationId else { return }
        var payload: [String: JSONValue] = [
            "conversationId": .string(id),
            "inputTokens": .number(Double(tally.inputTokens)),
            "outputTokens": .number(Double(tally.outputTokens)),
        ]
        if let pct = tally.contextPercent(window: window) { payload["contextPercent"] = .number(pct) }
        switch event.type {
        case "step_update":
            if let tool = event.activeTool { payload["tool"] = .string(tool) }
            BridgeClient.send(BridgeEvent(agent: .agy, name: "StepUpdate", ts: Date().timeIntervalSince1970, payload: .object(payload)))
        case "result":
            finalText = event.text
            resultStatus = event.status
            turns = event.turns
        default:
            break
        }
    }

    while true {
        let chunk = out.fileHandleForReading.availableData
        if chunk.isEmpty { break }
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(buffer.startIndex...nl)
            if !line.isEmpty { handle(line: line) }
        }
    }
    process.waitUntilExit()

    let agyFailed = process.terminationStatus != 0 || resultStatus?.uppercased() == "ERROR" || resultStatus == nil
    let acceptance = run("sh", ["-c", record.acceptance], cwd: record.worktree)
    let passed = !agyFailed && acceptance.status == 0
    record.status = passed ? .success : .failed
    record.finishedAt = Date().timeIntervalSince1970
    record.contextPercent = tally.contextPercent(window: window)
    record.checkpoints = tally.checkpoints
    record.inputTokens = tally.inputTokens
    record.outputTokens = tally.outputTokens
    RunStore.save(record)

    let block = resultBlock(record: record, passed: passed, agyFailed: agyFailed, acceptance: acceptance,
                            turns: turns, window: window, text: finalText, logPath: streamLog.path)
    try block.write(to: dir.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)

    if let id = record.conversationId {
        var payload: [String: JSONValue] = [
            "conversationId": .string(id),
            "status": .string(passed ? "SUCCESS" : "ERROR"),
            "inputTokens": .number(Double(tally.inputTokens)),
            "outputTokens": .number(Double(tally.outputTokens)),
        ]
        if let pct = record.contextPercent { payload["contextPercent"] = .number(pct) }
        if let turns { payload["turns"] = .number(Double(turns)) }
        BridgeClient.send(BridgeEvent(agent: .agy, name: "Result", ts: Date().timeIntervalSince1970, payload: .object(payload)))
    }
}

func resultBlock(record: RunRecord, passed: Bool, agyFailed: Bool, acceptance: (status: Int32, output: String),
                 turns: Int?, window: Int?, text: String?, logPath: String) -> String {
    let verdict = passed ? "SUCCESS" : (agyFailed ? "FAILED (agy)" : "FAILED (acceptance)")
    let conv = record.conversationId.map { String($0.prefix(4)) + "…" } ?? "none"
    var header = "\(record.task) \(verdict) · conv \(conv) · \(record.model)/\(record.effort)"
    if let turns { header += " · \(turns) turns" }
    header += " · \(formatDuration((record.finishedAt ?? 0) - record.startedAt))"

    let tail = acceptance.output.split(separator: "\n").last.map(String.init) ?? ""
    let acceptanceLine = "acceptance: \(record.acceptance) → \(acceptance.status == 0 ? tail : "exit \(acceptance.status) \(tail)")"

    let used = (record.contextPercent ?? 0) / 100 * Double(window ?? 0)
    let context = window.map { w in
        "context ~\(formatTokens(Int(used)))/\(formatTokens(w)) (\(Int((record.contextPercent ?? 0).rounded()))%)"
    } ?? "context unknown (window not published)"
    let usage = "\(context) · checkpoints \(record.checkpoints) · tokens in \(formatTokens(record.inputTokens)) out \(formatTokens(record.outputTokens))"

    let tracked = (try? git(["diff", "--name-only", record.base], cwd: record.worktree)) ?? ""
    let untracked = (try? git(["ls-files", "--others", "--exclude-standard"], cwd: record.worktree)) ?? ""
    let files = (tracked + "\n" + untracked).split(separator: "\n").map(String.init)

    return [header, "files: \(files.isEmpty ? "none" : files.joined(separator: ", "))", acceptanceLine, usage, "log: \(logPath)", text ?? ""]
        .joined(separator: "\n") + "\n"
}
