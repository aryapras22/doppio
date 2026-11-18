import AppKit
import Darwin
import Foundation
import IslandCore
import ServiceManagement
import SwiftUI

struct PeekItem: Equatable {
    let sessionId: String
    let label: String
    let color: Color
    let title: String
    let detail: String
}

struct SessionRowItem: Identifiable {
    let session: Session
    let indented: Bool
    var id: String { session.id }
}

/// Drives the menu bar animation; it only ticks while a session is brewing.
@MainActor
final class FrameTicker: ObservableObject {
    @Published private(set) var frame = 0
    private var timer: Timer?

    func run(_ on: Bool) {
        if on, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.frame += 1 }
            }
        } else if !on, let timer {
            timer.invalidate()
            self.timer = nil
        }
    }
}

@MainActor
final class IslandModel: ObservableObject {
    static let peekSeconds = 4.0

    let menuTicker = FrameTicker()
    @Published private(set) var store = SessionStore() {
        didSet { menuTicker.run(isBrewing(.claude) || isBrewing(.agy)) }
    }
    @Published private(set) var totals = IslandModel.loadTotals()
    @Published private(set) var agyUsage: [AgyQuotaBucket] = []
    @Published private(set) var peek: PeekItem?
    @Published var expanded = false
    @Published var notch = CGSize(width: 200, height: 32)
    @Published var showIsland = UserDefaults.standard.object(forKey: "showIsland") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showIsland, forKey: "showIsland") }
    }
    @Published var usageOpen = UserDefaults.standard.object(forKey: "usageOpen") as? Bool ?? false {
        didSet { UserDefaults.standard.set(usageOpen, forKey: "usageOpen") }
    }
    @Published var pinned = UserDefaults.standard.object(forKey: "islandPinned") as? Bool ?? false {
        didSet { UserDefaults.standard.set(pinned, forKey: "islandPinned") }
    }

    private struct TranscriptState: Sendable {
        var tally = TranscriptTally()
        var offset: UInt64 = 0
    }

    private var server: SocketServer?
    private var sweepTimer: Timer?
    private var agyUsageTimer: Timer?
    private var agyUsageRefreshWork: DispatchWorkItem?
    private var isFetchingAgyUsage = false
    private var isFetchingClaudeUsage = false
    private var peekClear: DispatchWorkItem?
    private var transcripts: [String: TranscriptState] = [:]
    private var transcriptTasks: [String: Task<Void, Never>] = [:]

    init() {
        replayRunningBuilders()
        let server = SocketServer { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        do { try server.start() } catch { NSLog("island socket failed: \(error)") }
        self.server = server

        sweepTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                var swept = self.store
                swept.sweep(now: Date().timeIntervalSince1970) { pid in kill(pid, 0) == 0 || errno == EPERM }
                if swept != self.store { self.store = swept }
                self.transcripts = self.transcripts.filter { self.store.sessions[$0.key] != nil }
                self.transcriptTasks = self.transcriptTasks.filter { self.store.sessions[$0.key] != nil }
            }
        }
        agyUsageTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAgyUsage()
                self?.refreshClaudeUsage()
            }
        }
        refreshAgyUsage()
        refreshClaudeUsage()
    }

    // MARK: derived state

    var sessions: [Session] { store.sessions.values.sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) } }
    var live: [Session] { sessions.filter { $0.state != .ended } }
    var cupCount: Int { live.filter { $0.agent == .claude || $0.parentId == nil }.count }
    var builderCount: Int { live.filter { $0.parentId != nil }.count }
    var orderUpCount: Int { live.filter { $0.state == .needsYou }.count }
    var brewingCount: Int { live.filter { $0.state == .working || $0.state == .runningTool }.count }
    var needsYou: Bool { orderUpCount > 0 }
    func isBrewing(_ agent: Agent) -> Bool {
        live.contains { $0.agent == agent && ($0.state == .working || $0.state == .runningTool) }
    }
    var visibleAgyUsage: [AgyQuotaBucket] { AgyUsage.visible(agyUsage) }

    var mode: IslandMode {
        IslandMode.current(expanded: expanded, pinned: pinned, peeking: peek != nil)
    }

    var usageLayout: UsageLayout { usageLayout(open: usageOpen) }
    var openUsageLayout: UsageLayout { usageLayout(open: true) }

    private func usageLayout(open: Bool) -> UsageLayout {
        let claudeBars = (store.rateLimits?.fiveHour != nil ? 1 : 0) + (store.rateLimits?.sevenDay != nil ? 1 : 0)
        let agyBars = visibleAgyUsage.count
        return UsageLayout.make(open: open, claudeBars: claudeBars, agyBars: agyBars)
    }

    /// Top-level sessions in start order, each followed by its builders; a builder whose parent is gone is promoted to top level.
    var rows: [SessionRowItem] {
        let all = live
        let ids = Set(all.map(\.id))
        return all.filter { $0.parentId.map(ids.contains) != true }.flatMap { top in
            [SessionRowItem(session: top, indented: false)] + all.filter { $0.parentId == top.id }.map { SessionRowItem(session: $0, indented: true) }
        }
    }

    var projects: [(name: String, rows: [SessionRowItem])] {
        let grouped = Dictionary(grouping: rows.filter { !$0.indented }, by: \.session.project)
        return grouped.keys.sorted().map { name in
            let items = rows.filter { item in
                let top = item.indented ? live.first { $0.id == item.session.parentId } : item.session
                return top?.project == name
            }
            return (name, items)
        }
    }

    func children(of session: Session) -> [Session] { live.filter { $0.parentId == session.id } }

    func subtitle(for s: Session) -> String {
        let model = s.model ?? "unknown model"
        if s.agent == .agy { return "\(model)\(s.effort.map { " / \($0)" } ?? "")" }
        let kids = children(of: s).filter { $0.state != .ended }.count
        if kids > 0 { return "\(model) · orchestrating \(kids)" }
        if s.state == .idle {
            let minutes = Int((Date().timeIntervalSince1970 - s.lastEventAt) / 60)
            return "\(model) · idle \(minutes) min"
        }
        return "\(model)\(s.terminalApp.map { " · \($0.replacingOccurrences(of: ".app", with: ""))" } ?? "")"
    }

    // MARK: actions

    func jump(to session: Session) {
        if session.agent == .agy, let task = session.taskId {
            NSWorkspace.shared.open(RunStore.dir(for: task).appendingPathComponent("result.txt"))
            return
        }
        TerminalJumper.jump(to: session, parent: store.sessions[session.parentId ?? ""])
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
            catch { NSLog("launch at login failed: \(error)") }
            objectWillChange.send()
        }
    }

    // MARK: events

    private func handle(_ event: BridgeEvent) {
        let before = event.sessionId.flatMap { store.sessions[$0] }
        store.apply(event)
        guard let id = event.sessionId, let after = store.sessions[id] else { return }
        showPeek(from: before, to: after)
        if event.agent == .claude, event.name == "Stop", before?.state == .working || before?.state == .runningTool {
            NSSound(named: "Brewed")?.play()
        }
        recordTotals(after)
        if event.agent == .claude, let path = event.payload["transcript_path"]?.string, !path.isEmpty {
            ingestTranscript(sessionId: id, path: path)
        }
        if event.agent == .agy, event.name == "Result" {
            scheduleAgyUsageRefresh(after: 5)
        }
    }

    private func scheduleAgyUsageRefresh(after delay: TimeInterval) {
        agyUsageRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshAgyUsage() }
        agyUsageRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func refreshAgyUsage() {
        guard !isFetchingAgyUsage, let path = Self.findAgyBinary() else { return }
        isFetchingAgyUsage = true
        Task { [weak self] in
            let buckets = await Task.detached(priority: .utility) {
                Self.fetchAgyUsage(executablePath: path)
            }.value
            guard let self else { return }
            self.isFetchingAgyUsage = false
            if let buckets {
                self.agyUsage = buckets
            }
        }
    }

    private func refreshClaudeUsage() {
        guard !isFetchingClaudeUsage, let path = Self.findClaudeBinary() else { return }
        isFetchingClaudeUsage = true
        Task { [weak self] in
            let limits = await Task.detached(priority: .utility) {
                Self.fetchClaudeUsage(executablePath: path)
            }.value
            guard let self else { return }
            self.isFetchingClaudeUsage = false
            if let limits {
                self.store.updateRateLimits(limits)
            }
        }
    }

    private nonisolated static func findAgyBinary() -> String? {
        let homeLocal = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/agy").path
        let candidates = ["/opt/homebrew/bin/agy", "/usr/local/bin/agy", homeLocal]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private nonisolated static func findClaudeBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            home.appendingPathComponent(".local/bin/claude").path,
            home.appendingPathComponent(".claude/local/claude").path,
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private nonisolated static func fetchAgyUsage(executablePath: String) -> [AgyQuotaBucket]? {
        guard let data = runUsageCommand(executablePath: executablePath, arguments: ["-p", "/usage", "--output-format", "json"]) else {
            return nil
        }
        return try? AgyUsage.parse(data)
    }

    private nonisolated static func fetchClaudeUsage(executablePath: String) -> RateLimits? {
        let arguments = [
            "-p", "/usage",
            "--output-format", "json",
            "--no-session-persistence",
            "--settings", #"{"disableAllHooks":true}"#,
        ]
        guard let data = runUsageCommand(executablePath: executablePath, arguments: arguments) else {
            return nil
        }
        return ClaudeUsage.parse(data)
    }

    private nonisolated static func runUsageCommand(executablePath: String, arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let timeoutWork = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30, execute: timeoutWork)
        defer { timeoutWork.cancel() }

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return data
    }

    private func showPeek(from before: Session?, to after: Session) {
        var item: PeekItem?
        if after.state == .needsYou, before?.state != .needsYou {
            item = PeekItem(sessionId: after.id, label: "ORDER UP!", color: .tomato,
                            title: "\(after.project) · Claude Code", detail: after.detail ?? "needs you")
        } else if after.state == .failed, before?.state != .failed {
            item = PeekItem(sessionId: after.id, label: "SPILLED", color: .tomato, title: after.rowTitle, detail: subtitle(for: after))
        } else if after.cupReady, before?.cupReady != true, after.parentId != nil {
            let turns = after.turns > 0 ? " · \(after.turns) turns" : ""
            item = PeekItem(sessionId: after.id, label: "CUP READY", color: .mint,
                            title: "agy builder \(after.taskId ?? "") · \(after.project)",
                            detail: "\(subtitle(for: after))\(turns) · back to Claude")
        }
        guard let item else { return }
        peek = item
        peekClear?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.peek = nil }
        peekClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.peekSeconds, execute: work)
    }

    private func recordTotals(_ s: Session) {
        guard s.agent == .agy else { return }
        totals.setAgy(sessionId: s.id, tokens: s.totalTokens, day: Self.today)
        saveTotals()
    }

    private func saveTotals() {
        if let data = try? JSONEncoder().encode(totals) {
            try? data.write(to: IslandPaths.totals, options: .atomic)
        }
    }

    private func ingestTranscript(sessionId: String, path: String) {
        let previous = transcriptTasks[sessionId]
        transcriptTasks[sessionId] = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let state = self.transcripts[sessionId] ?? TranscriptState()
            let updated: TranscriptState? = await Task.detached(priority: .utility) {
                guard let chunk = Self.readTranscriptChunk(path: path, offset: state.offset), !chunk.isEmpty else {
                    return nil
                }
                var next = state
                next.tally.ingest(chunk)
                next.offset += UInt64(chunk.count)
                return next
            }.value
            guard let updated else { return }
            self.transcripts[sessionId] = updated
            let today = Self.today
            self.store.updateTranscript(sessionId: sessionId, model: updated.tally.model)
            self.totals.setClaude(sessionId: sessionId, tokens: updated.tally.tokens(on: today), day: today)
            self.saveTotals()
        }
    }

    private nonisolated static func readTranscriptChunk(path: String, offset: UInt64) -> Data? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        do {
            let size = try handle.seekToEnd()
            guard size > offset else { return nil }
            try handle.seek(toOffset: offset)
            return try handle.readToEnd()
        } catch {
            return nil
        }
    }

    private func replayRunningBuilders() {
        for run in RunStore.all() where run.status == .running && isAliveProcess(run.agyPid) {
            if let link = run.linkEvent { store.apply(link) }
        }
    }

    private func isAliveProcess(_ pid: Int32?) -> Bool {
        guard let pid else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    private static var today: String { day(of: Date()) }

    private static func day(of date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Run records are the durable source for agy tokens, so a missing or unreadable totals.json loses nothing.
    private static func loadTotals() -> DailyTotals {
        let today = today
        let saved = (try? Data(contentsOf: IslandPaths.totals)).flatMap { try? JSONDecoder().decode(DailyTotals.self, from: $0) }
        var totals = saved?.day == today ? saved! : DailyTotals(day: today)
        for run in RunStore.all() where day(of: Date(timeIntervalSince1970: run.startedAt)) == today {
            totals.setAgy(sessionId: run.conversationId ?? run.task, tokens: run.inputTokens + run.outputTokens, day: today)
        }
        return totals
    }
}
