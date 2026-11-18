import CoreGraphics
import XCTest
@testable import IslandCore

final class IslandGeometryTests: XCTestCase {
    private let notch = CGSize(width: 185, height: 32)

    func testShapeSizePerMode() {
        XCTAssertEqual(IslandGeometry.shapeSize(mode: .collapsed, notch: notch, rowCount: 3), CGSize(width: 425, height: 32))
        XCTAssertEqual(IslandGeometry.shapeSize(mode: .peek, notch: notch, rowCount: 3), CGSize(width: 385, height: 96))
        XCTAssertEqual(IslandGeometry.shapeSize(mode: .peek, notch: CGSize(width: 300, height: 38), rowCount: 0), CGSize(width: 500, height: 102))
        XCTAssertEqual(IslandGeometry.shapeSize(mode: .expanded, notch: notch, rowCount: 6), CGSize(width: 440, height: 32 + 36 + 6 * 44 + 30 + 10))
    }

    // The panel never resizes during a mode change, so it must already hold the largest shape.
    func testPanelIsTheSmallestSizeHoldingEveryMode() {
        for rows in [0, 1, 6, 12] {
            let panel = IslandGeometry.panelSize(notch: notch, rowCount: rows)
            let shapes = IslandMode.allCases.map { IslandGeometry.shapeSize(mode: $0, notch: notch, rowCount: rows) }
            XCTAssertEqual(panel.width, shapes.map(\.width).max())
            XCTAssertEqual(panel.height, shapes.map(\.height).max())
        }
        XCTAssertEqual(IslandGeometry.panelSize(notch: CGSize(width: 400, height: 32), rowCount: 0), CGSize(width: 640, height: 108))
    }

    // AppKit coordinates: origin bottom-left, so the shape hangs from the panel's top edge.
    func testShapeRectHangsFromTopCentreOfPanel() {
        let panel = CGRect(x: 100, y: 800, width: 580, height: 136)
        let collapsed = IslandGeometry.shapeRect(mode: .collapsed, notch: notch, rowCount: 0, in: panel)
        XCTAssertEqual(collapsed, CGRect(x: 177.5, y: 904, width: 425, height: 32))
        let expanded = IslandGeometry.shapeRect(mode: .expanded, notch: notch, rowCount: 0, in: panel)
        XCTAssertEqual(expanded.maxY, panel.maxY)
        XCTAssertEqual(expanded.midX, panel.midX)
        XCTAssertFalse(collapsed.contains(CGPoint(x: 300, y: 850)))
        XCTAssertTrue(expanded.contains(CGPoint(x: 300, y: 850)))
    }
}
