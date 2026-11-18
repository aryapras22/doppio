import Foundation

public struct RateLimitWindow: Equatable, Sendable {
    public var usedPercentage: Double
    public var resetsAt: Double

    public init(usedPercentage: Double, resetsAt: Double) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }
}

public struct RateLimits: Equatable, Sendable {
    public var fiveHour: RateLimitWindow?
    public var sevenDay: RateLimitWindow?

    public init(fiveHour: RateLimitWindow? = nil, sevenDay: RateLimitWindow? = nil) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }
}

public enum SessionState: Equatable, Sendable {
    case working, runningTool, needsYou, idle, failed, ended
}

public struct Session: Identifiable, Equatable, Sendable {
    public let id: String
    public let agent: Agent
    public var parentId: String?
    public var taskId: String?
    public var title: String?
    public var worktree: String?
    public var project: String
    public var model: String?
    public var effort: String?
    public var state: SessionState = .idle
    public var currentTool: String?
    public var detail: String?
    public var turns: Int = 0
    public var startedAt: Double
    public var lastEventAt: Double
    public var endedAt: Double?
    public var finishedAt: Double?
    public var cupReady = false
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0
    public var contextPercent: Double?
    public var costUSD: Double?
    public var pid: Int32?
    public var terminalApp: String?
    public var itermSessionId: String?
    public var tmuxPane: String?

    public var totalTokens: Int { inputTokens + outputTokens }
    // agy reports no context field in its hooks; cc-agy computes it from token usage.
    public var contextIsEstimate: Bool { agent == .agy }
}

public struct SessionStore: Equatable, Sendable {
    public static let endedLingerSeconds: Double = 60
    public static let finishedBuilderLingerSeconds: Double = 300

    public private(set) var sessions: [String: Session] = [:]
    public private(set) var rateLimits: RateLimits?

    public init() {}

    public mutating func updateRateLimits(_ limits: RateLimits) {
        rateLimits = limits
    }

    public mutating func updateTranscript(sessionId: String, model: String?) {
        guard let model, !model.isEmpty, var s = sessions[sessionId], s.model == nil else { return }
        s.model = model
        sessions[sessionId] = s
    }

    public mutating func apply(_ event: BridgeEvent) {
        guard let id = event.sessionId, !id.isEmpty else { return }
        var s = sessions[id] ?? Session(id: id, agent: event.agent, project: "unknown", startedAt: event.ts, lastEventAt: event.ts)
        s.lastEventAt = event.ts
        if let cwd = event.cwd { s.project = (cwd as NSString).lastPathComponent }
        if let pid = event.pid { s.pid = pid }
        s.terminalApp = event.terminalApp ?? s.terminalApp
        s.itermSessionId = event.itermSessionId ?? s.itermSessionId
        s.tmuxPane = event.tmuxPane ?? s.tmuxPane
        if event.agent == .agy, let m = event.payload["modelName"]?.string { s.model = m }

        switch (event.agent, event.name) {
        case (_, "StatusLine"):
            applyStatusLine(event.payload, to: &s)
        case (.agy, "link"):
            applyLink(event.payload, to: &s)
        case (.agy, "StepUpdate"):
            applyStep(event.payload, to: &s)
        case (.agy, "Result"):
            applyResult(event.payload, at: event.ts, to: &s)
        case (.claude, "SessionStart"), (.agy, "SessionStart"), (.claude, "Stop"):
            setState(.idle, on: &s)
        case (.claude, "UserPromptSubmit"):
            setState(.working, on: &s)
        case (.agy, "PreInvocation"):
            setState(.working, on: &s)
        case (.claude, "PostToolUse"):
            setState(.working, on: &s)
        case (.agy, "PostToolUse"):
            setState(.working, on: &s)
            s.currentTool = event.payload["toolCall"]?["name"]?.string
        case (.claude, "PreToolUse"):
            setState(.runningTool, on: &s)
            s.currentTool = event.payload["tool_name"]?.string
        case (.claude, "PermissionRequest"):
            setState(.needsYou, on: &s)
            s.detail = approvalDetail(event.payload)
        case (.claude, "Notification"):
            setState(.needsYou, on: &s)
            s.detail = event.payload["message"]?.string
        case (.claude, "StopFailure"):
            setState(.failed, on: &s)
        case (.claude, "SessionEnd"):
            setState(.ended, on: &s)
            s.endedAt = event.ts
        case (.agy, "Stop"):
            // agy sends "error":"" on a normal stop, so only a non-empty string is a failure.
            if event.payload["error"]?.string?.isEmpty == false {
                setState(.failed, on: &s)
            } else if event.payload["fullyIdle"]?.bool == true, !s.cupReady {
                setState(.idle, on: &s)
            }
        default:
            break
        }
        sessions[id] = s
    }

    // Ends sessions whose agent process is gone, then drops what has lingered long enough.
    public mutating func sweep(now: Double, isAlive: (Int32) -> Bool) {
        for (id, var s) in sessions where s.state != .ended && s.finishedAt == nil {
            if let pid = s.pid, !isAlive(pid) {
                s.state = .ended
                s.endedAt = now
                sessions[id] = s
            }
        }
        sessions = sessions.filter { _, s in
            if let endedAt = s.endedAt, now - endedAt > Self.endedLingerSeconds { return false }
            if let finishedAt = s.finishedAt, now - finishedAt > Self.finishedBuilderLingerSeconds { return false }
            return true
        }
    }

    private func setState(_ state: SessionState, on s: inout Session) {
        s.state = state
        s.endedAt = nil
        if state != .runningTool { s.currentTool = nil }
        if state != .needsYou { s.detail = nil }
        if state == .working || state == .runningTool {
            s.cupReady = false
            s.finishedAt = nil
        }
    }

    private func approvalDetail(_ p: JSONValue) -> String? {
        guard let tool = p["tool_name"]?.string else { return nil }
        let input = p["tool_input"]
        let target = input?["command"]?.string ?? input?["file_path"]?.string
        return target.map { "\(tool) wants approval: \($0)" } ?? "\(tool) wants approval"
    }

    private mutating func applyStatusLine(_ p: JSONValue, to s: inout Session) {
        if let m = p["model"]?["id"]?.string ?? p["model"]?["display_name"]?.string { s.model = m }
        if let v = p["context_window"]?["used_percentage"]?.number { s.contextPercent = v }
        if let v = p["context_window"]?["total_input_tokens"]?.number { s.inputTokens = Int(v) }
        if let v = p["context_window"]?["total_output_tokens"]?.number { s.outputTokens = Int(v) }
        if let v = p["cost"]?["total_cost_usd"]?.number { s.costUSD = v }
        if let rl = p["rate_limits"], case .object = rl {
            rateLimits = RateLimits(
                fiveHour: Self.rateLimitWindow(rl["five_hour"]),
                sevenDay: Self.rateLimitWindow(rl["seven_day"])
            )
        }
    }

    private static func rateLimitWindow(_ v: JSONValue?) -> RateLimitWindow? {
        guard let used = v?["used_percentage"]?.number, let resets = v?["resets_at"]?.number else { return nil }
        return RateLimitWindow(usedPercentage: used, resetsAt: resets)
    }

    private func applyLink(_ p: JSONValue, to s: inout Session) {
        s.parentId = p["parent"]?.string
        s.taskId = p["task"]?.string
        s.title = p["title"]?.string
        s.model = p["model"]?.string ?? s.model
        s.effort = p["effort"]?.string
        s.worktree = p["worktree"]?.string
        if let pid = p["pid"]?.number { s.pid = Int32(pid) }
        if let project = p["project"]?.string { s.project = project }
        setState(.working, on: &s)
    }

    private func applyStep(_ p: JSONValue, to s: inout Session) {
        applyUsage(p, to: &s)
        if let tool = p["tool"]?.string, !tool.isEmpty {
            setState(.runningTool, on: &s)
            s.currentTool = tool
        } else {
            setState(.working, on: &s)
        }
    }

    private func applyResult(_ p: JSONValue, at ts: Double, to s: inout Session) {
        applyUsage(p, to: &s)
        if let v = p["turns"]?.number { s.turns = Int(v) }
        let succeeded = p["status"]?.string?.uppercased() != "ERROR"
        s.state = succeeded ? .idle : .failed
        s.currentTool = nil
        s.cupReady = succeeded
        s.finishedAt = ts
    }

    private func applyUsage(_ p: JSONValue, to s: inout Session) {
        if let v = p["inputTokens"]?.number { s.inputTokens = Int(v) }
        if let v = p["outputTokens"]?.number { s.outputTokens = Int(v) }
        if let v = p["contextPercent"]?.number { s.contextPercent = v }
    }
}
