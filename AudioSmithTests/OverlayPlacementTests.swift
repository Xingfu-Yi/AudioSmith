import AppKit
import XCTest
@testable import AudioSmith

final class OverlayPlacementTests: XCTestCase {
    func testNewRecordingResetsPanelToBottomCenter() {
        let origin = OverlayPlacement.origin(
            panelFrame: NSRect(x: 900, y: 700, width: 430, height: 64),
            visibleFrame: NSRect(x: 0, y: 25, width: 1_440, height: 875),
            resetPosition: true
        )

        XCTAssertEqual(origin, NSPoint(x: 505, y: 53))
    }

    func testSpaceRefreshPreservesDraggedPosition() {
        let origin = OverlayPlacement.origin(
            panelFrame: NSRect(x: 120, y: 360, width: 430, height: 64),
            visibleFrame: NSRect(x: 0, y: 25, width: 1_440, height: 875),
            resetPosition: false
        )

        XCTAssertNil(origin)
    }

    func testSpaceRefreshRecoversPanelMovedOffTargetScreen() {
        let origin = OverlayPlacement.origin(
            panelFrame: NSRect(x: -1_000, y: 360, width: 430, height: 64),
            visibleFrame: NSRect(x: 0, y: 25, width: 1_440, height: 875),
            resetPosition: false
        )

        XCTAssertEqual(origin, NSPoint(x: 505, y: 53))
    }
}
