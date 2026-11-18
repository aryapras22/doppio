import Darwin
import Foundation
import IslandCore

// Runs inside agent hooks: must never fail the hook, so every error path ends in exit(0).
let args = CommandLine.arguments
guard args.count >= 3, let agent = Agent(rawValue: args[1]) else { exit(0) }

// Drain stdin first so the agent never sees a broken pipe even if the app is down.
let input = FileHandle.standardInput.readDataToEndOfFile()
let payload = (try? JSONDecoder().decode(JSONValue.self, from: input))
    ?? .object(["raw": .string(String(decoding: input, as: UTF8.self))])

// Fallback when CLAUDE_PID is absent (agy hooks): the direct parent may be a short-lived shell, so walk up to the agent process.
func agentPid(named names: [String]) -> Int32? {
    var pid = getppid()
    for _ in 0..<8 where pid > 1 {
        var name = [CChar](repeating: 0, count: 256)
        proc_name(pid, &name, 256)
        let process = String(cString: name)
        if names.contains(where: process.contains) { return pid }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        pid = Int32(info.pbi_ppid)
    }
    return nil
}

let env = ProcessInfo.processInfo.environment
let event = BridgeEvent(
    agent: agent,
    name: args[2],
    ts: Date().timeIntervalSince1970,
    pid: (agent == .claude ? env["CLAUDE_PID"].flatMap { Int32($0) } : nil) ?? agentPid(named: agent == .claude ? ["claude"] : ["agy"]),
    terminalApp: env["TERM_PROGRAM"],
    itermSessionId: env["ITERM_SESSION_ID"],
    tmuxPane: env["TMUX_PANE"],
    payload: payload
)

// agy requires a decision from Stop hooks; anything other than "continue" lets the agent stop.
if agent == .agy { print(args[2] == "Stop" ? #"{"decision":"stop"}"# : "{}") }

BridgeClient.send(event)
exit(0)
