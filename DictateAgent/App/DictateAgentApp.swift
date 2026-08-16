import AppKit
import SwiftUI

@main
struct DictateAgentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared
    @StateObject private var skills = SkillManager.shared
    @StateObject private var hotkeys = HotkeySettings.shared

    var body: some Scene {
        MenuBarExtra("Audio Smith", systemImage: state.statusSymbol) {
            MenuBarView(hotkeys: hotkeys)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(state: state, skills: skills, hotkeys: hotkeys)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var permissionWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if ProcessInfo.processInfo.arguments.contains("--diagnose-permissions") {
            let permissions = Permissions.snapshot()
            let line = "microphone=\(permissions.microphone) "
                + "inputMonitoring=\(permissions.inputMonitoring) "
                + "accessibility=\(permissions.accessibility)\n"
            FileHandle.standardOutput.write(Data(line.utf8))
            NSApp.terminate(nil)
            return
        }
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        if !Permissions.snapshot().allGranted {
            showPermissionSetup()
        }
        AppRuntime.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        AppRuntime.shared.shutdown()
    }

    private func showPermissionSetup() {
        let hostingController = NSHostingController(
            rootView: SettingsView(
                state: AppState.shared,
                skills: SkillManager.shared,
                hotkeys: HotkeySettings.shared
            )
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Audio Smith Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 608, height: 720))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        permissionWindow = window
        NSApp.activate(ignoringOtherApps: true)
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
        SettingsLink {
            Label("系统设置", systemImage: "gearshape")
        }
        Button("退出") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
