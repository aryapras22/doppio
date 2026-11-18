import Foundation

public enum Agent: String, Codable, Sendable {
    case claude
    case agy
}

public struct BridgeEvent: Codable, Equatable, Sendable {
    public var agent: Agent
    public var name: String
    public var ts: Double
    public var pid: Int32?
    public var terminalApp: String?
    public var itermSessionId: String?
    public var tmuxPane: String?
    public var payload: JSONValue

    public init(agent: Agent, name: String, ts: Double, pid: Int32? = nil, terminalApp: String? = nil,
                itermSessionId: String? = nil, tmuxPane: String? = nil, payload: JSONValue) {
        self.agent = agent
        self.name = name
        self.ts = ts
        self.pid = pid
        self.terminalApp = terminalApp
        self.itermSessionId = itermSessionId
        self.tmuxPane = tmuxPane
        self.payload = payload
    }

    public var sessionId: String? {
        switch agent {
        case .claude: payload["session_id"]?.string
        case .agy: payload["conversationId"]?.string
        }
    }

    public var cwd: String? {
        switch agent {
        case .claude: payload["cwd"]?.string
        case .agy: payload["workspacePaths"]?.first?.string
        }
    }
}

public enum IslandPaths {
    public static var socket: String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Doppio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("island.sock").path
    }
}

public extension IslandPaths {
    static var totals: URL {
        URL(fileURLWithPath: socket).deletingLastPathComponent().appendingPathComponent("totals.json")
    }
}
