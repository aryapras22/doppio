import Foundation

public enum ContextWindows {
    // Only Gemini 4 has a published window; Sonnet 5.5 and Opus 5.5 inside agy stay unknown until measured.
    public static func size(for model: String) -> Int? {
        model.hasPrefix("gemini-4") ? 1_048_576 : nil
    }
}

/// One line of `agy --output-format stream-json`: {"event": "init|step_update|result", "<event>": {...}}, shape confirmed by the phase 0 spike.
public struct StreamEvent: Equatable, Sendable {
    public var type: String
    public var conversationId: String?
    public var stepType: String?
    public var tool: String?
    public var state: String?
    public var status: String?
    public var text: String?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var cacheReadTokens: Int?
    public var turns: Int?
    public var isCheckpoint: Bool

    public init?(line: String) {
        guard let data = line.data(using: .utf8), let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              let type = json["event"]?.string else { return nil }
        let body = json[type]
        self.type = type
        conversationId = json["conversation_id"]?.string ?? body?["conversation_id"]?.string
        stepType = body?["step_type"]?.string
        tool = body?["tool_name"]?.string
        state = body?["state"]?.string
        status = body?["status"]?.string
        text = body?["response"]?.string
        let usage = body?["usage"]
        inputTokens = usage?["input_tokens"]?.number.map(Int.init)
        outputTokens = usage?["output_tokens"]?.number.map(Int.init)
        cacheReadTokens = usage?["cache_read_tokens"]?.number.map(Int.init)
        turns = body?["num_turns"]?.number.map(Int.init)
        // The checkpoint step name is still unconfirmed: a long run has not been captured yet.
        isCheckpoint = (stepType ?? "").contains("checkpoint") || (tool ?? "").contains("checkpoint")
    }

    /// A tool is only running between its ACTIVE and DONE updates.
    public var activeTool: String? { stepType == "tool" && state == "ACTIVE" ? tool : nil }
}

public struct RunTally: Equatable, Sendable {
    public var inputTokens = 0
    public var outputTokens = 0
    public var checkpoints = 0
    public var lastInput = 0
    public var lastCacheRead = 0

    public init() {}

    public mutating func add(_ e: StreamEvent) {
        if e.isCheckpoint { checkpoints += 1 }
        guard e.inputTokens != nil || e.outputTokens != nil else { return }
        if e.type == "result" {
            inputTokens = e.inputTokens ?? inputTokens
            outputTokens = e.outputTokens ?? outputTokens
            return
        }
        inputTokens += e.inputTokens ?? 0
        outputTokens += e.outputTokens ?? 0
        lastInput = e.inputTokens ?? lastInput
        lastCacheRead = e.cacheReadTokens ?? 0
    }

    /// Last turn's input plus cache-read tokens over the model window, as a percentage.
    public func contextPercent(window: Int?) -> Double? {
        guard let window, window > 0, lastInput + lastCacheRead > 0 else { return nil }
        return Double(lastInput + lastCacheRead) / Double(window) * 100
    }
}
