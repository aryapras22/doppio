import Foundation

public struct RunRecord: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case running, success, failed, cancelled
    }

    public var task: String
    public var title: String?
    public var parent: String?
    public var conversationId: String?
    public var model: String
    public var effort: String
    public var repo: String
    public var worktree: String
    public var branch: String
    public var base: String
    public var acceptance: String
    public var agyPid: Int32?
    public var runnerPid: Int32?
    public var status: Status
    public var rounds: Int
    public var startedAt: Double
    public var finishedAt: Double?
    public var contextPercent: Double?
    public var checkpoints: Int
    public var inputTokens: Int
    public var outputTokens: Int
    public var reported: Bool

    public init(task: String, title: String?, parent: String?, conversationId: String?, model: String, effort: String,
                repo: String, worktree: String, branch: String, base: String, acceptance: String, agyPid: Int32?,
                runnerPid: Int32?, status: Status, rounds: Int, startedAt: Double, finishedAt: Double?,
                contextPercent: Double?, checkpoints: Int, inputTokens: Int, outputTokens: Int, reported: Bool) {
        self.task = task; self.title = title; self.parent = parent; self.conversationId = conversationId
        self.model = model; self.effort = effort; self.repo = repo; self.worktree = worktree; self.branch = branch
        self.base = base; self.acceptance = acceptance; self.agyPid = agyPid; self.runnerPid = runnerPid
        self.status = status; self.rounds = rounds; self.startedAt = startedAt; self.finishedAt = finishedAt
        self.contextPercent = contextPercent; self.checkpoints = checkpoints; self.inputTokens = inputTokens
        self.outputTokens = outputTokens; self.reported = reported
    }

    public var linkEvent: BridgeEvent? {
        guard let conversationId else { return nil }
        var payload: [String: JSONValue] = [
            "conversationId": .string(conversationId),
            "task": .string(task),
            "model": .string(model),
            "effort": .string(effort),
            "worktree": .string(worktree),
            "project": .string((repo as NSString).lastPathComponent),
        ]
        if let title { payload["title"] = .string(title) }
        if let parent { payload["parent"] = .string(parent) }
        if let agyPid { payload["pid"] = .number(Double(agyPid)) }
        return BridgeEvent(agent: .agy, name: "link", ts: Date().timeIntervalSince1970, payload: .object(payload))
    }
}

public enum RunStore {
    public static var root: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Doppio/runs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func dir(for task: String) -> URL {
        let d = root.appendingPathComponent(task, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    public static func load(_ task: String) -> RunRecord? {
        let url = dir(for: task).appendingPathComponent("run.json")
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(RunRecord.self, from: $0) }
    }

    public static func save(_ record: RunRecord) {
        let url = dir(for: record.task).appendingPathComponent("run.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(record).write(to: url, options: .atomic)
    }

    public static func all() -> [RunRecord] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.compactMap(load).sorted { $0.startedAt < $1.startedAt }
    }
}
