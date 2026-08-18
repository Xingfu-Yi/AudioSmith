import AppKit
import ApplicationServices

enum ScreenLocator {
    static func screenForFocusedWindow(pid: pid_t?) -> NSScreen? {
        guard let pid else { return screenAtPointer() }
        let app = AXUIElementCreateApplication(pid)
        var rawWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &rawWindow) == .success,
              let rawWindow,
              CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else {
            return screenAtPointer()
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
            return screenAtPointer()
        }
        let positionValue = unsafeDowncast(rawPosition, to: AXValue.self)
        let sizeValue = unsafeDowncast(rawSize, to: AXValue.self)

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return screenAtPointer()
        }

        // Accessibility coordinates start at the top-left; AppKit coordinates start at the bottom-left.
        guard let desktopTop = NSScreen.screens.map(\.frame.maxY).max() else { return screenAtPointer() }
        let appKitCenter = CGPoint(x: position.x + size.width / 2, y: desktopTop - position.y - size.height / 2)
        return NSScreen.screens.first(where: { $0.frame.contains(appKitCenter) }) ?? screenAtPointer()
    }

    private static func screenAtPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
    }
}
