import AppKit
import IslandCore

enum TerminalJumper {
    private static let bundleIds = [
        "iTerm.app": "com.googlecode.iterm2",
        "Apple_Terminal": "com.apple.Terminal",
        "ghostty": "com.mitchellh.ghostty",
        "WezTerm": "com.github.wez.wezterm",
    ]

    static func jump(to session: Session, parent: Session?) {
        let target = session.itermSessionId != nil || session.tmuxPane != nil || session.terminalApp != nil ? session : (parent ?? session)
        if let iterm = target.itermSessionId, let guid = iterm.split(separator: ":").last {
            selectITermSession(String(guid))
        } else if let pane = target.tmuxPane {
            run("tmux", ["select-window", "-t", pane])
            run("tmux", ["select-pane", "-t", pane])
        }
        if let app = target.terminalApp, let id = bundleIds[app] {
            NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.activate()
        }
    }

    private static func selectITermSession(_ guid: String) {
        let source = """
        tell application "iTerm2"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if unique id of s is "\(guid)" then
                  select w
                  select t
                  select s
                  return
                end if
              end repeat
            end repeat
          end repeat
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("iTerm jump failed: \(error)") }
    }

    private static func run(_ command: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [command] + args
        try? p.run()
    }
}
