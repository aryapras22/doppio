import CoreGraphics

public enum IslandMode: CaseIterable {
    case collapsed
    case peek
    case expanded

    public static func current(expanded: Bool, pinned: Bool, peeking: Bool) -> IslandMode {
        if pinned || expanded { return .expanded }
        return peeking ? .peek : .collapsed
    }
}

public struct UsageLayout: Equatable, Sendable {
    public var sections: Int
    public var bars: Int

    public init(sections: Int = 1, bars: Int = 0) {
        self.sections = sections
        self.bars = bars
    }

    public static func make(open: Bool, claudeBars: Int, agyBars: Int) -> UsageLayout {
        guard open else { return UsageLayout(sections: 1, bars: 0) }
        return UsageLayout(sections: 1 + (agyBars > 0 ? 1 : 0), bars: claudeBars + agyBars)
    }
}

public enum IslandGeometry {
    public static let rowHeight: CGFloat = 44
    public static let headerHeight: CGFloat = 36
    public static let usageSectionHeight: CGFloat = 22
    public static let usageBarHeight: CGFloat = 18
    public static let expandedWidth: CGFloat = 440
    public static let peekWidth: CGFloat = 380
    public static let peekBodyHeight: CGFloat = 64
    public static let wing: CGFloat = 120

    public static func shapeSize(
        mode: IslandMode,
        notch: CGSize,
        rowCount: Int,
        usage: UsageLayout = UsageLayout(sections: 1, bars: 0)
    ) -> CGSize {
        switch mode {
        case .collapsed:
            CGSize(width: notch.width + wing * 2, height: notch.height)
        case .peek:
            CGSize(width: max(peekWidth, notch.width + 200), height: notch.height + peekBodyHeight)
        case .expanded:
            CGSize(
                width: expandedWidth,
                height: notch.height + headerHeight + CGFloat(rowCount) * rowHeight + 8
                    + CGFloat(usage.sections) * usageSectionHeight
                    + CGFloat(usage.bars) * usageBarHeight + 10
            )
        }
    }

    public static func panelSize(
        notch: CGSize,
        rowCount: Int,
        usage: UsageLayout = UsageLayout(sections: 1, bars: 0)
    ) -> CGSize {
        IslandMode.allCases.reduce(.zero) { acc, mode in
            let size = shapeSize(mode: mode, notch: notch, rowCount: rowCount, usage: usage)
            return CGSize(width: max(acc.width, size.width), height: max(acc.height, size.height))
        }
    }

    public static func shapeRect(
        mode: IslandMode,
        notch: CGSize,
        rowCount: Int,
        in panelFrame: CGRect,
        usage: UsageLayout = UsageLayout(sections: 1, bars: 0)
    ) -> CGRect {
        let size = shapeSize(mode: mode, notch: notch, rowCount: rowCount, usage: usage)
        return CGRect(
            x: panelFrame.midX - size.width / 2,
            y: panelFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
