import XCTest
@testable import IslandCore

final class IslandStateTests: XCTestCase {
    func testPinnedIslandStaysExpandedEvenDuringAPeek() {
        XCTAssertEqual(IslandMode.current(expanded: false, pinned: true, peeking: true), .expanded)
        XCTAssertEqual(IslandMode.current(expanded: false, pinned: true, peeking: false), .expanded)
    }

    func testUnpinnedIslandPrefersHoverThenPeekThenCollapsed() {
        XCTAssertEqual(IslandMode.current(expanded: true, pinned: false, peeking: true), .expanded)
        XCTAssertEqual(IslandMode.current(expanded: false, pinned: false, peeking: true), .peek)
        XCTAssertEqual(IslandMode.current(expanded: false, pinned: false, peeking: false), .collapsed)
    }

    // Closed, the usage dropdown is one summary line, which is the default layout.
    func testClosedUsageDropdownIsOneLine() {
        XCTAssertEqual(UsageLayout.make(open: false, claudeBars: 2, agyBars: 2), UsageLayout(sections: 1, bars: 0))
    }

    func testOpenUsageDropdownAddsAnAgySectionOnlyWhenAgyHasBars() {
        XCTAssertEqual(UsageLayout.make(open: true, claudeBars: 2, agyBars: 2), UsageLayout(sections: 2, bars: 4))
        XCTAssertEqual(UsageLayout.make(open: true, claudeBars: 2, agyBars: 0), UsageLayout(sections: 1, bars: 2))
        XCTAssertEqual(UsageLayout.make(open: true, claudeBars: 0, agyBars: 0), UsageLayout(sections: 1, bars: 0))
    }
}
