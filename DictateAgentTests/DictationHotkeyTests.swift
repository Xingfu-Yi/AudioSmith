import XCTest
@testable import DictateAgent

final class DictationHotkeyTests: XCTestCase {
    func testEveryShortcutUsesAUniquePhysicalKeyCode() {
        let keyCodes = DictationHotkey.allCases.map(\.keyCode)
        XCTAssertEqual(Set(keyCodes).count, keyCodes.count)
    }

    func testFunctionKeyRemainsTheDefaultChoice() {
        XCTAssertEqual(DictationHotkey.function.rawValue, "function")
        XCTAssertEqual(DictationHotkey.function.displayName, "Fn")
        XCTAssertEqual(DictationHotkey.function.keyCode, 63)
    }
}

