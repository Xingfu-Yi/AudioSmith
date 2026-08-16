import Combine
import CoreGraphics
import Foundation

enum DictationHotkey: String, CaseIterable, Identifiable, Sendable {
    case function
    case rightOption
    case rightControl
    case rightCommand

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .function: "Fn"
        case .rightOption: "右 Option ⌥"
        case .rightControl: "右 Control ⌃"
        case .rightCommand: "右 Command ⌘"
        }
    }

    var keyCode: Int64 {
        switch self {
        case .function: 63
        case .rightOption: 61
        case .rightControl: 62
        case .rightCommand: 54
        }
    }

    var modifierFlag: CGEventFlags {
        switch self {
        case .function: .maskSecondaryFn
        case .rightOption: .maskAlternate
        case .rightControl: .maskControl
        case .rightCommand: .maskCommand
        }
    }
}

@MainActor
final class HotkeySettings: ObservableObject {
    static let shared = HotkeySettings()

    @Published private(set) var selected: DictationHotkey

    private static let defaultsKey = "dictationHotkey"

    private init(defaults: UserDefaults = .standard) {
        selected = defaults.string(forKey: Self.defaultsKey)
            .flatMap(DictationHotkey.init(rawValue:)) ?? .function
    }

    func select(_ hotkey: DictationHotkey) {
        guard selected != hotkey else { return }
        selected = hotkey
        UserDefaults.standard.set(hotkey.rawValue, forKey: Self.defaultsKey)
    }
}

