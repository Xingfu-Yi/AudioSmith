import AppKit
import ApplicationServices

enum ScreenLocator {
    static func screenForFocusedWindow(pid: pid_t?) -> NSScreen? {
        guard let pid else { return fallbackScreen() }
        let app = AXUIElementCreateApplication(pid)
        var rawWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &rawWindow) == .success,
              let rawWindow,
              CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else {
            return fallbackScreen()
        }

        let window = unsafeDowncast(rawWindow, to: AXUIElement.self)
        var rawPosition: CFTypeRef?
        var rawSize: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &rawPosition) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &rawSize) == .success,
              let rawPosition,
              let rawSize,
              CFGetTypeID(rawPosition) == AXValueGetTypeID(),
              CFGetTypeID(rawSize) == AXValueGetTypeID() else {
            return fallbackScreen()
        }
        let positionValue = unsafeDowncast(rawPosition, to: AXValue.self)
        let sizeValue = unsafeDowncast(rawSize, to: AXValue.self)

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return fallbackScreen()
        }

        // Accessibility coordinates start at the top-left; AppKit coordinates start at the bottom-left.
        let screens = NSScreen.screens
        guard let primaryTop = primaryScreenTop(in: screens.map(\.frame)) else { return fallbackScreen() }
        let windowFrame = appKitFrame(position: position, size: size, primaryScreenTop: primaryTop)

        // A window may span displays. Selecting the largest intersection is more
        // reliable than testing its center, especially for maximized and full-screen
        // windows whose reported AX frame can include an adjacent display edge.
        return screens.enumerated().max { lhs, rhs in
            intersectionArea(lhs.element.frame, windowFrame) < intersectionArea(rhs.element.frame, windowFrame)
        }.flatMap { intersectionArea($0.element.frame, windowFrame) > 0 ? $0.element : nil }
            ?? fallbackScreen()
    }

    static func appKitFrame(position: CGPoint, size: CGSize, primaryScreenTop: CGFloat) -> CGRect {
        CGRect(
            x: position.x,
            y: primaryScreenTop - position.y - size.height,
            width: size.width,
            height: size.height
        )
    }

    static func primaryScreenTop(in frames: [CGRect]) -> CGFloat? {
        frames.first(where: { $0.origin == .zero })?.maxY ?? frames.first?.maxY
    }

    static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        return intersection.width * intersection.height
    }

    private static func fallbackScreen() -> NSScreen? {
        // NSScreen.main follows the window currently receiving keyboard events,
        // which is normally the dictation target. The pointer is only a final
        // fallback; it may be on a different monitor while the user is typing.
        NSScreen.main ?? screenAtPointer()
    }

    private static func screenAtPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
    }
}
