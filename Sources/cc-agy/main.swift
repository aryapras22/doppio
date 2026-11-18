import Darwin
import Foundation
import IslandCore

let maxBuilders = 3
let rolloverPercent = 50.0

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("cc-agy: \(message)\n".utf8))
    exit(1)
}

func running() -> [RunRecord] {
    RunStore.all().filter { $0.status == .running && isAlive($0.runnerPid ?? $0.agyPid) }
}

func spawnRunner(task: String, promptFile: String, resume: Bool) throws {
    let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
    let args = ["_run", task, promptFile] + (resume ? ["--resume"] : [])
    let log = RunStore.dir(for: task).appendingPathComponent("runner.log").path
    guard let pid = spawnDetached(exe, args, log: log) else { throw Failure(message: "could not start runner") }
    guard var record = RunStore.load(task) else { return }
    record.runnerPid = pid
    RunStore.save(record)
}

func start(packetPath: String, handoffPath: String?) throws {
    let packet = try Packet.parse(String(contentsOfFile: packetPath, encoding: .utf8))
    let active = running()
    guard active.count < maxBuilders else { throw Failure(message: "\(maxBuilders) builders already running: \(active.map(\.task).joined(separator: ", "))") }
    if active.contains(where: { $0.task == packet.id }) { throw Failure(message: "\(packet.id) is already running") }

    let cwd = FileManager.default.currentDirectoryPath
    let repo = try git(["rev-parse", "--show-toplevel"], cwd: cwd)
    // Refusing instead of committing: a clean start state is required, but committing your work-in-progress is not mine to do.
    let dirty = try git(["status", "--porcelain"], cwd: repo).split(separator: "\n").filter { !$0.hasSuffix(".plans/") && !$0.contains(" .plans/") }
    guard dirty.isEmpty else { throw Failure(message: "working tree is not clean; commit or stash first:\n" + dirty.joined(separator: "\n")) }

    let branch = "agy/\(packet.id)"
    let worktree = worktreesRoot().appendingPathComponent("\((repo as NSString).lastPathComponent)-\(packet.id)").path
    let previous = RunStore.load(packet.id)
    var base = try git(["rev-parse", "HEAD"], cwd: repo)
    if FileManager.default.fileExists(atPath: worktree) {
        guard handoffPath != nil, let previous else { throw Failure(message: "\(packet.id) already has a worktree at \(worktree); pass --handoff to continue in it, or remove it first") }
        base = previous.base
    } else {
        try git(["worktree", "add", "-b", branch, worktree], cwd: repo)
    }

    var prompt = packet.text + "\n\nWorktree: \(worktree)\nAcceptance command: \(packet.acceptance)\n"
    if let handoffPath { prompt += "\n# Handoff from the previous run\n" + (try String(contentsOfFile: handoffPath, encoding: .utf8)) }
    let dir = RunStore.dir(for: packet.id)
    let promptFile = dir.appendingPathComponent("prompt-1.txt").path
    try prompt.write(toFile: promptFile, atomically: true, encoding: .utf8)
    try? FileManager.default.removeItem(at: dir.appendingPathComponent("result.txt"))

    RunStore.save(RunRecord(
        task: packet.id, title: packet.title, parent: ProcessInfo.processInfo.environment["CLAUDE_CODE_SESSION_ID"],
        conversationId: nil, model: packet.model, effort: packet.effort, repo: repo, worktree: worktree, branch: branch, base: base,
        acceptance: packet.acceptance, agyPid: nil, runnerPid: nil, status: .running, rounds: 1,
        startedAt: Date().timeIntervalSince1970, finishedAt: nil, contextPercent: nil, checkpoints: 0,
        inputTokens: 0, outputTokens: 0, reported: false
    ))
    try spawnRunner(task: packet.id, promptFile: promptFile, resume: false)
    print("started \(packet.id) in \(worktree)")
}

func wait(timeout: Double) {
    let deadline = Date().addingTimeInterval(timeout)
    var printed = false
    while true {
        for var record in RunStore.all() where record.status == .running && !isAlive(record.runnerPid ?? record.agyPid) && record.runnerPid != nil {
            record.status = .failed
            record.finishedAt = Date().timeIntervalSince1970
            RunStore.save(record)
            try? "\(record.task) FAILED (runner died) · see \(RunStore.dir(for: record.task).path)\n"
                .write(to: RunStore.dir(for: record.task).appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
        }
        for var record in RunStore.all() where record.status != .running && !record.reported {
            let resultFile = RunStore.dir(for: record.task).appendingPathComponent("result.txt")
            guard let block = try? String(contentsOf: resultFile, encoding: .utf8) else { continue }
            print(block, terminator: "")
            record.reported = true
            RunStore.save(record)
            printed = true
        }
        let stillRunning = running().map(\.task)
        if stillRunning.isEmpty {
            if !printed { print("nothing running and nothing new to report") }
            return
        }
        if Date() >= deadline {
            print("still running: \(stillRunning.joined(separator: ", ")); call wait again")
            return
        }
        fflush(stdout)
        sleep(2)
    }
}

func status() {
    for r in RunStore.all() {
        let ctx = r.contextPercent.map { "ctx ~\(Int($0.rounded()))%" } ?? "ctx --"
        let conv = r.conversationId.map { String($0.prefix(4)) + "…" } ?? "-"
        print("\(r.task)\t\(r.status.rawValue)\t\(r.model)/\(r.effort)\t\(ctx)\tconv \(conv)\trounds \(r.rounds)\t\(r.worktree)")
    }
}

func continueRun(task: String, feedback: String) throws {
    guard var record = RunStore.load(task) else { throw Failure(message: "unknown task \(task)") }
    guard record.status != .running else { throw Failure(message: "\(task) is still running") }
    guard record.conversationId != nil else { throw Failure(message: "\(task) never started a conversation") }
    if (record.contextPercent ?? 0) >= rolloverPercent || record.checkpoints > 0 {
        throw Failure(message: "\(task) needs a rollover (context \(Int(record.contextPercent ?? 0))%, \(record.checkpoints) checkpoints): write a handoff and run cc-agy start <packet> --handoff <file>")
    }
    guard running().count < maxBuilders else { throw Failure(message: "\(maxBuilders) builders already running") }
    record.rounds += 1
    record.status = .running
    record.reported = false
    record.finishedAt = nil
    RunStore.save(record)
    let promptFile = RunStore.dir(for: task).appendingPathComponent("prompt-\(record.rounds).txt").path
    try feedback.write(toFile: promptFile, atomically: true, encoding: .utf8)
    try spawnRunner(task: task, promptFile: promptFile, resume: true)
    print("continued \(task), round \(record.rounds)")
}

func cancel(task: String) throws {
    guard var record = RunStore.load(task) else { throw Failure(message: "unknown task \(task)") }
    guard record.status == .running else { throw Failure(message: "\(task) is not running") }
    if let pid = record.runnerPid { kill(-pid, SIGTERM) }
    if let pid = record.agyPid { kill(pid, SIGTERM) }
    record.status = .cancelled
    record.finishedAt = Date().timeIntervalSince1970
    record.reported = true
    RunStore.save(record)
    if let id = record.conversationId {
        BridgeClient.send(BridgeEvent(agent: .agy, name: "Result", ts: Date().timeIntervalSince1970,
                                      payload: .object(["conversationId": .string(id), "status": .string("ERROR")])))
    }
    print("cancelled \(task)")
}

let args = Array(CommandLine.arguments.dropFirst())
let usage = "usage: cc-agy start <packet.md> [--handoff file] | wait [--all] [--timeout s] | status | continue <task> <feedback> | cancel <task>"
do {
    guard let command = args.first else { fail(usage) }
    switch command {
    case "start":
        guard args.count >= 2 else { fail(usage) }
        let handoff = args.firstIndex(of: "--handoff").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        try start(packetPath: args[1], handoffPath: handoff)
    case "wait":
        let timeout = args.firstIndex(of: "--timeout").flatMap { args.indices.contains($0 + 1) ? Double(args[$0 + 1]) : nil } ?? 540
        wait(timeout: timeout)
    case "status":
        status()
    case "continue":
        guard args.count >= 3 else { fail(usage) }
        try continueRun(task: args[1], feedback: args[2])
    case "cancel":
        guard args.count >= 2 else { fail(usage) }
        try cancel(task: args[1])
    case "_run":
        try runBuilder(task: args[1], promptFile: args[2], resume: args.contains("--resume"))
    default:
        fail(usage)
    }
} catch let f as Failure {
    fail(f.message)
} catch {
    fail("\(error)")
}
