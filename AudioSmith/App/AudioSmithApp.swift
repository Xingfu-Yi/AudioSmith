import AppKit
import SwiftUI

@main
struct AudioSmithApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared
    @StateObject private var hotkeys = HotkeySettings.shared

    var body: some Scene {
        MenuBarExtra("Audio Smith", systemImage: state.statusSymbol) {
            MenuBarView(hotkeys: hotkeys)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if ProcessInfo.processInfo.arguments.contains("--diagnose-permissions") {
            let permissions = Permissions.snapshot()
            let line = "microphone=\(permissions.microphone) "
                + "shortcutMonitoring=\(permissions.shortcutMonitoring) "
                + "accessibility=\(permissions.accessibility)\n"
            FileHandle.standardOutput.write(Data(line.utf8))
            NSApp.terminate(nil)
            return
        }
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        if !Permissions.snapshot().allGranted {
            showSettings()
        }
        AppRuntime.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        AppRuntime.shared.shutdown()
    }

    func showSettings() {
        if settingsWindow == nil {
            let hostingController = NSHostingController(
                rootView: SettingsView(
                    state: AppState.shared,
                    skills: SkillManager.shared,
                    hotkeys: HotkeySettings.shared,
                    preferences: DictationPreferences.shared
                )
            )
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Audio Smith Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 608, height: 720))
            window.isReleasedWhenClosed = false
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.center()
            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()

        // MenuBarExtra closes at the end of the current event. Reasserting the
        // ordering on the next run-loop turn prevents that close from returning
        // focus to the previously active browser window.
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.settingsWindow?.makeKeyAndOrderFront(nil)
        }
    }
}

private struct MenuBarView: View {
    @ObservedObject var hotkeys: HotkeySettings

    var body: some View {
        Label("Audio Smith", systemImage: "mic.fill")
        Divider()
        Menu("快捷键（\(hotkeys.selected.displayName)）") {
            ForEach(DictationHotkey.allCases) { candidate in
                Button {
                    AppRuntime.shared.selectHotkey(candidate)
                } label: {
                    if hotkeys.selected == candidate {
                        Label(candidate.displayName, systemImage: "checkmark")
                    } else {
                        Text(candidate.displayName)
                    }
                }
            }
        }
        Button {
            (NSApp.delegate as? AppDelegate)?.showSettings()
        } label: {
            Label("系统设置", systemImage: "gearshape")
        }
        Button("退出") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
