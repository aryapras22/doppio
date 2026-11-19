import AppKit
import IslandCore
import SwiftUI

@main
struct DoppioApp: App {
    @StateObject private var model: IslandModel
    @StateObject private var ticker: FrameTicker
    private let island: IslandController

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        Theme.registerFont()
        let model = IslandModel()
        _model = StateObject(wrappedValue: model)
        _ticker = StateObject(wrappedValue: model.menuTicker)
        island = IslandController(model: model)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            // A plain Image only: a custom view with its own observed state here makes MenuBarExtra redraw nonstop.
            let frame = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : ticker.frame % 12
            Image(nsImage: MenuBarLabel.image(
                cupFrame: model.isBrewing(.claude) ? frame : nil,
                robotFrame: model.isBrewing(.agy) ? frame : nil,
                needsYou: model.needsYou
            ))
        }
        .menuBarExtraStyle(.window)
    }
}

/// The status item is drawn as a non-template image; a plain SwiftUI label is recoloured monochrome by the menu bar.
struct MenuBarLabel: View {
    let cupFrame: Int?
    let robotFrame: Int?
    let needsYou: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            PixelView(sprite: Sprites.menuBarCup(steamFrame: cupFrame), scale: 1.5)
            PixelView(sprite: Sprites.menuBarRobot(frame: robotFrame), scale: 1.5)
            if needsYou { Rectangle().fill(Color.tomato).frame(width: 7, height: 7) }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.roast))
    }

    private static var cache: [String: NSImage] = [:]

    /// Cached by frame: the cup and robot cycle through 12 frames, so rendering each once is enough.
    @MainActor
    static func image(cupFrame: Int?, robotFrame: Int?, needsYou: Bool) -> NSImage {
        let key = "\(cupFrame ?? -1)/\(robotFrame ?? -1)/\(needsYou)"
        if let cached = cache[key] { return cached }
        let renderer = ImageRenderer(content: MenuBarLabel(cupFrame: cupFrame, robotFrame: robotFrame, needsYou: needsYou))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = false
        cache[key] = image
        return image
    }
}

struct MenuView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.rows.isEmpty {
                Text("NO CUPS BREWING").font(Theme.readout(16)).foregroundStyle(Color.mocha)
            }
            ForEach(model.projects, id: \.name) { project in
                Text(project.name.uppercased()).font(Theme.readout(14)).foregroundStyle(Color.mocha)
                ForEach(project.rows) { item in
                    MenuRow(model: model, session: item.session, indented: item.indented)
                }
            }
            Divider().overlay(Color.roast)
            UsageSectionsView(model: model, inlineReset: false, collapsible: false)
            Divider().overlay(Color.roast)
            ToggleLine(title: "Show island on notch", isOn: Binding(get: { model.showIsland }, set: { model.showIsland = $0 }))
            ToggleLine(title: "Pin island open", isOn: Binding(get: { model.pinned }, set: { model.pinned = $0 }))
            ToggleLine(title: "Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
            HStack {
                Button("Quit Doppio") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain)
                Spacer()
                Text("⌘Q").font(Theme.readout(14)).foregroundStyle(Color.mocha)
            }
            .keyboardShortcut("q")
            .font(Theme.name(13))
            .foregroundStyle(Color.latte)
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(Color.espresso)
    }
}

struct ToggleLine: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title).font(Theme.name(13)).foregroundStyle(Color.latte)
            Spacer()
            Text(isOn ? "ON" : "OFF").font(Theme.readout(16)).foregroundStyle(isOn ? Color.mint : Color.mocha)
        }
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

struct MenuRow: View {
    @ObservedObject var model: IslandModel
    let session: Session
    let indented: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(session.stateColor).frame(width: 8, height: 8).padding(.top, 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.agent == .claude ? "Claude Code" : "agy \(session.rowTitle)").font(Theme.name(13)).foregroundStyle(Color.latte).lineLimit(1)
                    Text("\(session.model ?? "unknown model") · \(session.contextText)")
                        .font(Theme.readout(12)).foregroundStyle(session.contextColor).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(session.state == .runningTool ? "GRINDING" : session.stateLabel).font(Theme.readout(14)).foregroundStyle(session.stateColor).lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture { model.jump(to: session) }
            sessionActionButton(model: model, session: session)
        }
        .padding(.leading, indented ? 20 : 0)
    }
}
