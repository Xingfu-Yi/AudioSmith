import AppKit
import ApplicationServices

struct TargetApplication: Sendable {
    let pid: pid_t
    let bundleIdentifier: String?
}

enum PasteResult: Equatable, Sendable {
    case pasted
    case clipboardOnly(reason: String)
}

@MainActor
final class TextInserter {
    func captureTarget() -> TargetApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return TargetApplication(pid: app.processIdentifier, bundleIdentifier: app.bundleIdentifier)
    }

    func insert(_ text: String, into target: TargetApplication?) async -> PasteResult {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        guard !text.isEmpty else { return .clipboardOnly(reason: "没有可粘贴的文字") }
        guard Permissions.snapshot().accessibility else {
            return .clipboardOnly(reason: "未授予辅助功能权限，文字已复制")
        }
        guard let target else { return .clipboardOnly(reason: "原输入应用已不可用，文字已复制") }
        guard !isSecureField(in: target.pid) else {
            return .clipboardOnly(reason: "安全输入框禁止自动粘贴，文字已复制")
        }
        guard let app = NSRunningApplication(processIdentifier: target.pid), !app.isTerminated else {
            return .clipboardOnly(reason: "原输入应用已退出，文字已复制")
        }

        app.activate()
        try? await Task.sleep(for: .milliseconds(90))
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return .clipboardOnly(reason: "无法发送粘贴快捷键，文字已复制")
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return .pasted
    }

    private func isSecureField(in pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var rawElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &rawElement) == .success,
              let rawElement,
              CFGetTypeID(rawElement) == AXUIElementGetTypeID() else {
            // Fail closed: without reliable field metadata, preserve the clipboard but do not synthesize paste.
            return true
        }
        let element = unsafeDowncast(rawElement, to: AXUIElement.self)
        let subrole = attribute(kAXSubroleAttribute, of: element)
        return subrole == "AXSecureTextField"
    }

    private func attribute(_ name: String, of element: AXUIElement) -> String? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &rawValue) == .success else { return nil }
        return rawValue as? String
    }
}
