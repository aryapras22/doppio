import Foundation

public enum UsageWindow: Equatable, Sendable {
    case fiveHour
    case weekly
}

public struct AgyQuotaBucket: Identifiable, Equatable, Sendable {
    public let id: String
    public let group: String
    public let window: UsageWindow
    public var usedPercentage: Double
    public let resetsAt: Double

    public init(id: String, group: String, window: UsageWindow, usedPercentage: Double, resetsAt: Double) {
        self.id = id
        self.group = group
        self.window = window
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }
}

public enum AgyUsage {
    public enum ParseError: Error {
        case invalidWindow(String)
        case invalidResetTime(String)
    }

    private struct Root: Decodable {
        let command: Command
    }

    private struct Command: Decodable {
        let data: CommandData
    }

    private struct CommandData: Decodable {
        let groups: [Group]
    }

    private struct Group: Decodable {
        let name: String
        let buckets: [Bucket]
    }

    private struct Bucket: Decodable {
        let id: String
        let window: String
        let remaining_fraction: Double
        let reset_time: String
    }

    public static func parse(_ data: Data) throws -> [AgyQuotaBucket] {
        let root = try JSONDecoder().decode(Root.self, from: data)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var result: [AgyQuotaBucket] = []
        for group in root.command.data.groups {
            for bucket in group.buckets {
                let window: UsageWindow = switch bucket.window {
                case "5h": .fiveHour
                case "weekly": .weekly
                default: throw ParseError.invalidWindow(bucket.window)
                }
                guard let date = iso.date(from: bucket.reset_time) ?? isoFractional.date(from: bucket.reset_time) else {
                    throw ParseError.invalidResetTime(bucket.reset_time)
                }
                result.append(AgyQuotaBucket(
                    id: bucket.id,
                    group: group.name,
                    window: window,
                    usedPercentage: (1 - bucket.remaining_fraction) * 100,
                    resetsAt: date.timeIntervalSince1970
                ))
            }
        }
        return result
    }

    public static func visible(_ buckets: [AgyQuotaBucket]) -> [AgyQuotaBucket] {
        var groupOrder: [String] = []
        var byGroup: [String: [AgyQuotaBucket]] = [:]
        for bucket in buckets {
            if byGroup[bucket.group] == nil {
                groupOrder.append(bucket.group)
            }
            byGroup[bucket.group, default: []].append(bucket)
        }

        var result: [AgyQuotaBucket] = []
        for group in groupOrder {
            guard let groupBuckets = byGroup[group] else { continue }
            guard group == "Gemini Models" || groupBuckets.contains(where: { $0.usedPercentage > 0 }) else {
                continue
            }
            result.append(contentsOf: groupBuckets.filter { $0.window == .fiveHour })
            result.append(contentsOf: groupBuckets.filter { $0.window != .fiveHour })
        }
        return result
    }

    public static func label(_ bucket: AgyQuotaBucket) -> String {
        let shortGroup: String = switch bucket.group {
        case "Gemini Models": "GEMINI"
        case "Claude and GPT models": "CLAUDE/GPT"
        case "Gemini 4 Argon": "ARGON"
        default: bucket.group.uppercased()
        }
        let windowSuffix = bucket.window == .fiveHour ? "5H" : "WEEK"
        return "\(shortGroup) \(windowSuffix)"
    }
}

public enum UsageFormat {
    public static func resetText(
        resetsAt: Double,
        now: Double = Date().timeIntervalSince1970,
        calendar: Calendar = .current
    ) -> String {
        let remaining = resetsAt - now
        if remaining <= 0 {
            return "resets now"
        }
        if remaining < 24 * 3600 {
            let totalMinutes = Int(remaining) / 60
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return hours > 0 ? "resets in \(hours)h \(minutes)m" : "resets in \(minutes)m"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE HH:mm"
        return "resets \(formatter.string(from: Date(timeIntervalSince1970: resetsAt)))"
    }

    public static func filledSegments(percentage: Double) -> Int {
        guard percentage.isFinite else { return 0 }
        let clamped = min(100, max(0, percentage))
        return Int((clamped / 5).rounded())
    }
}
