import XCTest
@testable import AudioSmith

final class ScreenLocatorTests: XCTestCase {
    func testAccessibilityFrameUsesPrimaryScreenTopInsteadOfDesktopMaximum() {
        let frame = ScreenLocator.appKitFrame(
            position: CGPoint(x: 100, y: 80),
            size: CGSize(width: 800, height: 600),
            primaryScreenTop: 1_080
        )

        XCTAssertEqual(frame, CGRect(x: 100, y: 400, width: 800, height: 600))
    }

    func testPrimaryScreenTopPrefersDisplayAtGlobalOrigin() {
        let upperDisplay = CGRect(x: 0, y: 1_080, width: 1_920, height: 1_080)
        let primaryDisplay = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)

        XCTAssertEqual(ScreenLocator.primaryScreenTop(in: [upperDisplay, primaryDisplay]), 1_080)
    }

    func testIntersectionAreaSupportsWindowsSpanningDisplays() {
        let leftDisplay = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let rightDisplay = CGRect(x: 1_920, y: 0, width: 2_560, height: 1_440)
        let window = CGRect(x: 1_700, y: 100, width: 1_300, height: 900)

        XCTAssertGreaterThan(
            ScreenLocator.intersectionArea(rightDisplay, window),
            ScreenLocator.intersectionArea(leftDisplay, window)
        )
    }
}
