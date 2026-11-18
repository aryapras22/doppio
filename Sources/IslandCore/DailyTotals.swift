import Foundation

/// Claude and agy token totals for one day, stored per session so a restart can refill them from transcripts and run records.
public struct DailyTotals: Codable, Equatable, Sendable {
    public var day: String
    private var claudeTokensBySession: [String: Int] = [:]
    private var agyTokensBySession: [String: Int] = [:]

    public var claudeTokens: Int {
        claudeTokensBySession.values.reduce(0, +)
    }

    public var agyTokens: Int {
        agyTokensBySession.values.reduce(0, +)
    }

    public init(day: String) { self.day = day }

    public mutating func setClaude(sessionId: String, tokens: Int, day today: String) {
        if today != day { self = DailyTotals(day: today) }
        claudeTokensBySession[sessionId] = tokens
    }

    /// Keeps the larger count: a run's tokens only grow, and run.json still says 0 while the run is in progress.
    public mutating func setAgy(sessionId: String, tokens: Int, day today: String) {
        if today != day { self = DailyTotals(day: today) }
        agyTokensBySession[sessionId] = max(agyTokensBySession[sessionId] ?? 0, tokens)
    }
}
