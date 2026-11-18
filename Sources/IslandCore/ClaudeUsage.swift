import Foundation

public enum ClaudeUsage {
    private struct Envelope: Decodable {
        let result: String
    }

    private static let fiveHourRegex = lineRegex(prefix: "Current session")
    private static let sevenDayRegex = lineRegex(prefix: "Current week (all models)")

    public static func parse(_ data: Data, now: Double = Date().timeIntervalSince1970) -> RateLimits? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return nil
        }
        let fiveHour = parseWindow(regex: fiveHourRegex, in: envelope.result, now: now)
        let sevenDay = parseWindow(regex: sevenDayRegex, in: envelope.result, now: now)
        guard fiveHour != nil || sevenDay != nil else {
            return nil
        }
        return RateLimits(fiveHour: fiveHour, sevenDay: sevenDay)
    }

    private static func lineRegex(prefix: String) -> NSRegularExpression {
        let escaped = NSRegularExpression.escapedPattern(for: prefix)
        return try! NSRegularExpression(
            pattern: "^\\s*\(escaped):\\s*(\\d+(?:\\.\\d+)?)%\\s+used\\s*·\\s*resets\\s+(.+?)\\s*\\(([^)]+)\\)\\s*$",
            options: [.anchorsMatchLines]
        )
    }

    private static func parseWindow(regex: NSRegularExpression, in text: String, now: Double) -> RateLimitWindow? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let pctRange = Range(match.range(at: 1), in: text),
              let resetRange = Range(match.range(at: 2), in: text),
              let zoneRange = Range(match.range(at: 3), in: text),
              let usedPercentage = Double(text[pctRange]),
              let resetsAt = parseReset(String(text[resetRange]), zoneName: String(text[zoneRange]), now: now)
        else {
            return nil
        }
        return RateLimitWindow(usedPercentage: usedPercentage, resetsAt: resetsAt)
    }

    private static func parseReset(_ text: String, zoneName: String, now: Double) -> Double? {
        guard let timeZone = TimeZone(identifier: zoneName) ?? TimeZone(abbreviation: zoneName) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.calendar = calendar

        let nowDate = Date(timeIntervalSince1970: now)
        let year = calendar.component(.year, from: nowDate)

        // Claude Code writes "3pm" on the hour and "2:59pm" otherwise.
        for format in ["yyyy MMM d 'at' h:mma", "yyyy MMM d 'at' ha"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: "\(year) \(text)"), date.timeIntervalSince1970 >= now {
                return date.timeIntervalSince1970
            }
            if let nextYearDate = formatter.date(from: "\(year + 1) \(text)"), nextYearDate.timeIntervalSince1970 >= now {
                return nextYearDate.timeIntervalSince1970
            }
        }

        let timeDate = ["h:mma", "ha"].lazy.compactMap { format -> Date? in
            formatter.dateFormat = format
            return formatter.date(from: text)
        }.first
        guard let timeDate else {
            return nil
        }
        let hm = calendar.dateComponents([.hour, .minute], from: timeDate)
        guard let hour = hm.hour, let minute = hm.minute,
              let next = calendar.nextDate(
                  after: nowDate,
                  matching: DateComponents(hour: hour, minute: minute, second: 0),
                  matchingPolicy: .nextTime
              )
        else {
            return nil
        }
        return next.timeIntervalSince1970
    }
}
