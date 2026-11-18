import Foundation

public struct TranscriptTally: Sendable {
    private let calendar: Calendar
    private var remainder = Data()
    private var seenMessageIds: Set<String> = []
    private var tokensByDay: [String: Int] = [:]

    public private(set) var model: String?

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public mutating func ingest(_ data: Data) {
        guard !data.isEmpty else { return }
        var buffer = remainder
        buffer.append(data)
        remainder.removeAll(keepingCapacity: true)

        var start = buffer.startIndex
        while let newline = buffer[start...].firstIndex(of: 0x0A) {
            let slice = buffer[start..<newline]
            start = buffer.index(after: newline)
            if !slice.isEmpty {
                ingestLine(Data(slice))
            }
        }
        if start < buffer.endIndex {
            remainder = Data(buffer[start...])
        }
    }

    public func tokens(on day: String) -> Int {
        tokensByDay[day, default: 0]
    }

    private mutating func ingestLine(_ lineData: Data) {
        let decoder = JSONDecoder()
        guard let probe = try? decoder.decode(TypeProbe.self, from: lineData),
              probe.type == "assistant",
              let line = try? decoder.decode(AssistantLine.self, from: lineData),
              let message = line.message else {
            return
        }
        if let m = message.model, !m.isEmpty {
            model = m
        }
        guard let id = message.id,
              let usage = message.usage,
              let ts = line.timestamp,
              let date = Self.parseTimestamp(ts),
              seenMessageIds.insert(id).inserted else {
            return
        }
        let tokens = (usage.input_tokens ?? 0)
            + (usage.cache_creation_input_tokens ?? 0)
            + (usage.output_tokens ?? 0)
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return }
        let dayKey = String(format: "%04d-%02d-%02d", year, month, day)
        tokensByDay[dayKey, default: 0] += tokens
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
            return date
        }
        return try? Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(value)
    }

    private struct TypeProbe: Decodable {
        let type: String?
    }

    private struct AssistantLine: Decodable {
        let timestamp: String?
        let message: Message?

        struct Message: Decodable {
            let id: String?
            let model: String?
            let usage: Usage?
        }

        struct Usage: Decodable {
            let input_tokens: Int?
            let cache_creation_input_tokens: Int?
            let output_tokens: Int?
        }
    }
}
