import IslandCore
import SwiftUI

private extension Animation {
    static func islandSpring(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.86)
    }
}

struct IslandRootView: View {
    @ObservedObject var model: IslandModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var mode: IslandMode { model.mode }

    private struct AnimationKey: Equatable {
        let mode: IslandMode
        let rowCount: Int
        let usage: UsageLayout
    }

    private var animation: Animation {
        .islandSpring(reduceMotion: reduceMotion)
    }

    private var transition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
    }

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .collapsed: CollapsedPill(model: model)
        case .peek: if let peek = model.peek { PeekView(model: model, peek: peek) }
        case .expanded: ExpandedPanel(model: model)
        }
    }

    var body: some View {
        let size = IslandGeometry.shapeSize(mode: mode, notch: model.notch, rowCount: model.rows.count, usage: model.usageLayout)
        let radius: CGFloat = mode == .collapsed ? 14 : 18
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)

        ZStack(alignment: .top) {
            modeContent
                .frame(width: size.width, height: size.height, alignment: .top)
                .id(mode)
                .transition(transition)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(Color.black)
        .clipShape(shape)
        .contentShape(Rectangle())
        .onTapGesture { if mode == .collapsed { model.expanded = true } }
        .animation(animation, value: AnimationKey(mode: mode, rowCount: model.rows.count, usage: model.usageLayout))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct CollapsedPill: View {
    @ObservedObject var model: IslandModel

    private var summary: (text: String, color: Color) {
        var parts: [String] = []
        if model.orderUpCount > 0 { parts.append("\(model.orderUpCount) ORDER UP") }
        if model.brewingCount > 0 { parts.append("\(model.brewingCount) BREWING") }
        if parts.isEmpty { return ("\(model.live.count) ON WARMER", .mocha) }
        return (parts.joined(separator: " · "), model.orderUpCount > 0 ? .tomato : .amber)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(model.live.prefix(4)) { CupView(session: $0, scale: 1.5) }
            }
            .frame(width: IslandGeometry.wing - 10, alignment: .leading)
            .padding(.leading, 10)
            Spacer(minLength: model.notch.width)
            Text(summary.text)
                .font(Theme.readout(15))
                .foregroundStyle(summary.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: IslandGeometry.wing - 10, alignment: .trailing)
                .padding(.trailing, 10)
        }
        .frame(maxHeight: .infinity)
    }
}

struct PeekView: View {
    @ObservedObject var model: IslandModel
    let peek: PeekItem

    var body: some View {
        let session = model.store.sessions[peek.sessionId]
        HStack(spacing: 12) {
            PixelView(sprite: Sprites.robot(for: session?.agent ?? .claude), scale: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(peek.label).font(Theme.readout(26)).foregroundStyle(peek.color)
                Text(peek.title).font(Theme.name(13)).foregroundStyle(Color.latte).lineLimit(1)
                Text(peek.detail).font(Theme.readout(13)).foregroundStyle(Color.mocha).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("CLICK\nTO JUMP").font(Theme.readout(14)).foregroundStyle(Color.amber).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 20)
        .padding(.top, model.notch.height)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { if let session { model.jump(to: session) } }
    }
}

struct ExpandedPanel: View {
    @ObservedObject var model: IslandModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var counts: String {
        [(model.cupCount, "CUP"), (model.builderCount, "BUILDER"), (model.orderUpCount, "ORDER UP")]
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.1)\($0.0 > 1 && $0.1 != "ORDER UP" ? "S" : "")" }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.notch.height)
            HStack {
                Text("DOPPIO").font(Theme.readout(24)).foregroundStyle(Color.amber).shadow(color: .amber.opacity(0.6), radius: 1)
                Spacer()
                Button {
                    model.pinned.toggle()
                } label: {
                    Image(systemName: model.pinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .foregroundStyle(model.pinned ? Color.amber : Color.mocha)
                }
                .buttonStyle(.plain)
                Text(counts).font(Theme.readout(14)).foregroundStyle(Color.mocha)
            }
            .frame(height: IslandGeometry.headerHeight)
            .padding(.horizontal, 18)
            Divider().overlay(Color.roast).padding(.horizontal, 16)
            ForEach(model.rows) { item in
                IslandRow(model: model, session: item.session, indented: item.indented)
                    .frame(height: IslandGeometry.rowHeight)
            }
            Divider().overlay(Color.roast).padding(.horizontal, 16)
            UsageSectionsView(model: model, inlineReset: true, collapsible: true)
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
        .overlay { if !reduceTransparency { Scanlines().allowsHitTesting(false) } }
    }
}

struct UsageBar: View {
    let percentage: Double
    let fill: Color

    var body: some View {
        let filled = UsageFormat.filledSegments(percentage: percentage)
        HStack(spacing: 2) {
            ForEach(0..<20, id: \.self) { index in
                Rectangle()
                    .fill(index < filled ? fill : Color.roast)
                    .frame(width: 5, height: 8)
            }
        }
    }
}

struct UsageSectionsView: View {
    @ObservedObject var model: IslandModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let inlineReset: Bool
    let collapsible: Bool

    private var isOpen: Bool {
        !collapsible || model.usageOpen
    }

    private var claudeWindows: [(label: String, window: RateLimitWindow)] {
        [("5-HOUR", model.store.rateLimits?.fiveHour), ("WEEKLY", model.store.rateLimits?.sevenDay)]
            .compactMap { label, window in window.map { (label, $0) } }
    }

    private var agyBuckets: [AgyQuotaBucket] {
        model.visibleAgyUsage
    }

    private var dropdownTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if collapsible {
                firstHeaderLine
                    .frame(height: inlineReset ? IslandGeometry.usageSectionHeight : nil)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.islandSpring(reduceMotion: reduceMotion)) {
                            model.usageOpen.toggle()
                        }
                    }
                CollapsibleLayout(progress: isOpen ? 1 : 0) {
                    if isOpen {
                        usageContent
                            .transition(dropdownTransition)
                    }
                }
                .clipped()
            } else {
                firstHeaderLine
                    .frame(height: inlineReset ? IslandGeometry.usageSectionHeight : nil)
                usageContent
            }
        }
    }

    private var usageContent: some View {
        VStack(alignment: .leading, spacing: inlineReset ? 0 : 4) {
            ForEach(claudeWindows, id: \.label) { item in
                UsageRow(
                    label: item.label,
                    percentage: item.window.usedPercentage,
                    resetsAt: item.window.resetsAt,
                    fill: .crema,
                    inlineReset: inlineReset
                )
            }
            if !agyBuckets.isEmpty {
                agyHeader
                ForEach(agyBuckets) { bucket in
                    UsageRow(
                        label: AgyUsage.label(bucket),
                        percentage: bucket.usedPercentage,
                        resetsAt: bucket.resetsAt,
                        fill: .mint,
                        inlineReset: inlineReset
                    )
                }
            }
        }
        .padding(.top, inlineReset ? 0 : 4)
    }

    private var firstHeaderLine: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(isOpen ? "CLAUDE USAGE" : "USAGE")
                    .contentTransition(.opacity)
                if collapsible {
                    Text("▸")
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
            }
            .font(Theme.readout(13))
            .foregroundStyle(Color.mocha)
            Spacer(minLength: 8)
            ZStack(alignment: .trailing) {
                if isOpen {
                    todaySummaryText
                        .transition(.opacity)
                } else {
                    closedSummaryText
                        .transition(.opacity)
                }
            }
        }
    }

    private var todaySummaryText: some View {
        (Text("TODAY ").foregroundStyle(Color.mocha)
            + Text("CLAUDE \(Self.compact(model.totals.claudeTokens))").foregroundStyle(Color.crema)
            + Text(" · ").foregroundStyle(Color.mocha)
            + Text("AGY \(Self.compact(model.totals.agyTokens))").foregroundStyle(Color.mint))
            .font(Theme.readout(13))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var closedSummaryText: some View {
        let claude = model.store.rateLimits?.fiveHour?.usedPercentage
        let gemini = model.agyUsage.first { $0.id == "gemini-5h" }?.usedPercentage

        return Group {
            if let claude, let gemini {
                Self.summaryPart(label: "CLAUDE", percentage: claude, color: .crema)
                    + Text(" · ").foregroundStyle(Color.mocha)
                    + Self.summaryPart(label: "GEMINI", percentage: gemini, color: .mint)
            } else if let claude {
                Self.summaryPart(label: "CLAUDE", percentage: claude, color: .crema)
            } else if let gemini {
                Self.summaryPart(label: "GEMINI", percentage: gemini, color: .mint)
            } else {
                Text("no data").foregroundStyle(Color.mocha)
            }
        }
        .font(Theme.readout(13))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private static func summaryPart(label: String, percentage: Double, color: Color) -> Text {
        let pctColor: Color = percentage > 80 ? .tomato : color
        return Text("\(label) ").foregroundStyle(color)
            + Text("\(Int(percentage.rounded()))%").foregroundStyle(pctColor)
    }

    private var agyHeader: some View {
        HStack {
            Text("GEMINI USAGE")
                .font(Theme.readout(13))
                .foregroundStyle(Color.mocha)
            Spacer(minLength: 0)
        }
        .frame(height: inlineReset ? IslandGeometry.usageSectionHeight : nil)
    }

    private static func compact(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : n >= 1000 ? "\(n / 1000)K" : "\(n)"
    }
}

private struct CollapsibleLayout: Layout {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func makeCache(subviews: Subviews) -> CGSize {
        .zero
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout CGSize) -> CGSize {
        if let child = subviews.first {
            let size = child.sizeThatFits(proposal)
            cache = size
            return CGSize(width: size.width, height: size.height * progress)
        }
        return CGSize(width: cache.width, height: cache.height * progress)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CGSize) {
        guard let child = subviews.first else { return }
        child.place(at: bounds.origin, proposal: proposal)
    }
}

private struct UsageRow: View {
    let label: String
    let percentage: Double
    let resetsAt: Double
    let fill: Color
    let inlineReset: Bool

    private var percentageColor: Color {
        percentage > 80 ? .tomato : fill
    }

    private var barLine: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(Theme.readout(12))
                .foregroundStyle(Color.latte)
                .lineLimit(1)
                .frame(width: 86, alignment: .leading)
            UsageBar(percentage: percentage, fill: fill)
            Text("\(Int(percentage.rounded()))%")
                .font(Theme.readout(13))
                .foregroundStyle(percentageColor)
                .frame(width: 36, alignment: .trailing)
            if inlineReset {
                Text(UsageFormat.resetText(resetsAt: resetsAt))
                    .font(Theme.readout(11))
                    .foregroundStyle(Color.mocha)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }

    var body: some View {
        if inlineReset {
            barLine.frame(height: IslandGeometry.usageBarHeight)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                barLine
                Text(UsageFormat.resetText(resetsAt: resetsAt))
                    .font(Theme.readout(11))
                    .foregroundStyle(Color.mocha)
                    .lineLimit(1)
                    .padding(.leading, 94)
            }
        }
    }
}

struct IslandRow: View {
    @ObservedObject var model: IslandModel
    let session: Session
    let indented: Bool

    var body: some View {
        HStack(spacing: 8) {
            if indented {
                Text("└").font(Theme.readout(16)).foregroundStyle(Color.mocha).frame(width: 12)
            }
            PixelView(sprite: Sprites.robot(for: session.agent), scale: indented ? 1.75 : 2)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(session.rowTitle).font(Theme.name(13)).foregroundStyle(Color.latte).lineLimit(1)
                Text(model.subtitle(for: session)).font(Theme.readout(12)).foregroundStyle(Color.mocha).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(session.stateLabel).font(Theme.readout(16)).foregroundStyle(session.stateColor)
                    .shadow(color: session.stateColor.opacity(0.5), radius: 1).lineLimit(1)
                Text("CTX \(session.contextText.dropFirst(4).uppercased()) · \(session.tokenText)")
                    .font(Theme.readout(12)).foregroundStyle(session.contextColor)
            }
            .layoutPriority(1)
            CupView(session: session, scale: 2)
        }
        .padding(.leading, indented ? 36 : 18)
        .padding(.trailing, 18)
        .contentShape(Rectangle())
        .onTapGesture { model.jump(to: session) }
    }
}

struct Scanlines: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.18)))
                y += 3
            }
        }
    }
}
