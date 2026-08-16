import CoreGraphics
import Foundation
import OSLog

final class PushToTalkKeyMonitor: @unchecked Sendable {
    struct Handlers: Sendable {
        let pressed: @MainActor @Sendable () -> Void
        let released: @MainActor @Sendable () -> Void
        let cancelled: @MainActor @Sendable () -> Void
    }

    private var eventTap: CFMachPort?
    private let logger = Logger(subsystem: "io.dictateagent.DictateAgent", category: "hotkey")
    private var runLoopSource: CFRunLoopSource?
    private let lock = NSLock()
    private var isActivationKeyDown = false
    private var didCancel = false
    private let hotkey: DictationHotkey
    private let handlers: Handlers

    private static let functionKeyCodes: Set<Int64> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

    init(hotkey: DictationHotkey, handlers: Handlers) {
        self.hotkey = hotkey
        self.handlers = handlers
    }

    func start() throws {
        guard eventTap == nil else { return }
        let mask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<PushToTalkKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: pointer
        ) else {
            throw PushToTalkMonitorError.cannotCreateEventTap
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.notice("Event tap started for \(self.hotkey.displayName, privacy: .public)")
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        runLoopSource = nil
        eventTap = nil
        lock.withLock {
            isActivationKeyDown = false
            didCancel = false
        }
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            guard keyCode == hotkey.keyCode else { return }
            let isDown = event.flags.contains(hotkey.modifierFlag)
            var action: Action?
            lock.withLock {
                if isDown && !isActivationKeyDown {
                    isActivationKeyDown = true
                    didCancel = false
                    action = .press
                } else if !isDown && isActivationKeyDown {
                    isActivationKeyDown = false
                    action = didCancel ? nil : .release
                    didCancel = false
                }
            }
            dispatch(action)

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            var shouldCancel = false
            lock.withLock {
                guard isActivationKeyDown else { return }
                let isEscape = keyCode == 53
                let isFnCombination = hotkey == .function && Self.functionKeyCodes.contains(keyCode)
                let isModifierShortcut = hotkey != .function
                guard isEscape || isFnCombination || isModifierShortcut else { return }
                didCancel = true
                shouldCancel = true
            }
            if shouldCancel { dispatch(.cancel) }

        default:
            break
        }
    }

    private func dispatch(_ action: Action?) {
        guard let action else { return }
        switch action {
        case .press: logger.notice("Push-to-talk key down")
        case .release: logger.notice("Push-to-talk key up")
        case .cancel: logger.notice("Push-to-talk request cancelled")
        }
        Task { @MainActor [handlers] in
            switch action {
            case .press: handlers.pressed()
            case .release: handlers.released()
            case .cancel: handlers.cancelled()
            }
        }
    }

    private enum Action: Sendable { case press, release, cancel }
}

enum PushToTalkMonitorError: LocalizedError {
    case cannotCreateEventTap

    var errorDescription: String? {
        "无法监听听写快捷键，请在系统设置中允许“输入监控”，然后重新启动应用。"
    }
}

