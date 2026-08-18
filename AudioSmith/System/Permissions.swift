import AppKit
import AVFoundation
import ApplicationServices
import CoreGraphics
import OSLog

enum Permissions {
    private static let logger = Logger(
        subsystem: "com.xingfuyi.AudioSmith",
        category: "permissions"
    )

    static func snapshot() -> PermissionSnapshot {
        let accessibility = AXIsProcessTrusted()
        return PermissionSnapshot(
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            // Accessibility grants both event posting and event listening. Prefer
            // that permission because Audio Smith already needs it for automatic
            // paste, while the separate ListenEvent entry is unreliable at
            // registering newly renamed development builds in System Settings.
            shortcutMonitoring: accessibility || CGPreflightListenEventAccess(),
            accessibility: accessibility
        )
    }

    @MainActor
    static func requestAll() async -> PermissionSnapshot {
        let microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        logger.notice("Microphone authorization before request: \(String(describing: microphoneStatus), privacy: .public)")

        if microphoneStatus == .notDetermined {
            // LSUIElement menu-bar apps can otherwise ask while they are hidden in
            // the background. Bring the visible setup window forward first so the
            // TCC prompt has an active owning application.
            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(for: .milliseconds(150))
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            logger.notice("Microphone authorization request completed: granted=\(granted, privacy: .public)")
        }

        if !AXIsProcessTrusted() {
            // String value of kAXTrustedCheckOptionPrompt. Using the literal avoids
            // Swift 6 treating the imported C global as mutable shared state.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        // TCC changes are asynchronous. Avoid publishing the stale value returned
        // in the same run-loop turn as a permission prompt or System Settings edit.
        var latest = snapshot()
        for _ in 0..<4 where !latest.allGranted {
            try? await Task.sleep(for: .milliseconds(250))
            latest = snapshot()
        }
        logger.notice("Permission request finished: microphone=\(latest.microphone, privacy: .public) shortcutMonitoring=\(latest.shortcutMonitoring, privacy: .public) accessibility=\(latest.accessibility, privacy: .public)")
        return latest
    }

    @MainActor
    static func openPrivacySettings() {
        let current = snapshot()
        let anchor: String
        if !current.microphone {
            anchor = "Privacy_Microphone"
        } else if !current.accessibility {
            anchor = "Privacy_Accessibility"
        } else {
            anchor = "Privacy"
        }
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)

        // URL routing can open the correct pane without activating its window
        // when called by an LSUIElement menu-bar app. Explicitly activate System
        // Settings after LaunchServices has had a chance to launch or reuse it.
        Task { @MainActor in
            for _ in 0..<10 {
                if let settings = NSRunningApplication.runningApplications(
                    withBundleIdentifier: "com.apple.systempreferences"
                ).first {
                    settings.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}
