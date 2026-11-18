import Darwin
import Foundation
import IslandCore

struct Failure: Error { let message: String }

@discardableResult
func run(_ command: String, _ args: [String], cwd: String? = nil) -> (status: Int32, output: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = [command] + args
    if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (127, "\(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}

@discardableResult
func git(_ args: [String], cwd: String) throws -> String {
    let r = run("git", args, cwd: cwd)
    guard r.status == 0 else { throw Failure(message: "git \(args.joined(separator: " ")) failed: \(r.output)") }
    return r.output
}

func isAlive(_ pid: Int32?) -> Bool {
    guard let pid else { return false }
    return kill(pid, 0) == 0 || errno == EPERM
}

/// Starts a process in its own session with stdio redirected, so it survives the Bash tool call that launched cc-agy.
func spawnDetached(_ exe: String, _ args: [String], log: String) -> pid_t? {
    var attr: posix_spawnattr_t? = nil
    posix_spawnattr_init(&attr)
    posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
    var actions: posix_spawn_file_actions_t? = nil
    posix_spawn_file_actions_init(&actions)
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_addopen(&actions, 1, log, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    posix_spawn_file_actions_adddup2(&actions, 1, 2)
    let argv: [UnsafeMutablePointer<CChar>?] = ([exe] + args).map { strdup($0) } + [nil]
    defer { argv.forEach { free($0) } }
    var pid: pid_t = 0
    let rc = posix_spawn(&pid, exe, &actions, &attr, argv, environ)
    return rc == 0 ? pid : nil
}

func formatTokens(_ n: Int) -> String {
    n >= 1_000_000 ? String(format: "%.2fM", Double(n) / 1e6) : n >= 1000 ? "\(n / 1000)K" : "\(n)"
}

func formatDuration(_ seconds: Double) -> String {
    let s = Int(seconds)
    return s >= 60 ? "\(s / 60)m\(String(format: "%02d", s % 60))s" : "\(s)s"
}

func worktreesRoot() -> URL {
    let dir = RunStore.root.deletingLastPathComponent().appendingPathComponent("worktrees", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
